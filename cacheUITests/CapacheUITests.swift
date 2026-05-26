import XCTest

final class CapacheUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--capache-ui-testing-local-only")
        app.launch()
        return app
    }

    private func tapControl(
        named label: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let candidates = [
                app.buttons[label],
                app.popUpButtons[label],
                app.menuItems[label]
            ]

            if let hittable = candidates.first(where: { $0.exists && $0.isHittable }) {
                tapElement(hittable)
                return
            }

            if let existing = candidates.first(where: { $0.exists }) {
                tapElement(existing)
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail("Could not find control named \(label)", file: file, line: line)
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testAppLaunchesToNotesList() {
        let app = launchApp()

        let notesNavigationBar = app.navigationBars["Notes"]
        let emptyNotesText = app.staticTexts["No Notes"]

        XCTAssertTrue(
            notesNavigationBar.waitForExistence(timeout: 5) || emptyNotesText.waitForExistence(timeout: 2),
            "Capache should launch into the notes list without requiring login."
        )
    }

    func testNoteActionsMenuOpensFromEditor() {
        let app = launchApp()

        let newNoteButton = app.buttons["New Note"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5))
        newNoteButton.tap()

        let noteActionsButton = app.buttons["Note Actions"]
        XCTAssertTrue(noteActionsButton.waitForExistence(timeout: 5))
        tapElement(noteActionsButton)

        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 3))
    }

    func testFolderRowOpensFolder() {
        let app = launchApp()

        let folderName = "UITest Folder \(UUID().uuidString.prefix(6))"

        tapControl(named: "Filter Notes", in: app)
        tapControl(named: "New Folder", in: app, timeout: 3)

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(folderName)

        tapControl(named: "Save", in: app)
        XCTAssertTrue(app.navigationBars[folderName].waitForExistence(timeout: 5))

        tapControl(named: "Notes", in: app, timeout: 3)

        tapControl(named: "Folder \(folderName)", in: app)

        XCTAssertTrue(app.navigationBars[folderName].waitForExistence(timeout: 5))
    }
}
