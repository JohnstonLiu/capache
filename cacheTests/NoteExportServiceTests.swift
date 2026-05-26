import XCTest
@testable import Capache

final class NoteExportServiceTests: XCTestCase {
    private var rootURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacheExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        defaultsSuiteName = "CapacheExportTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootURL)
        defaults = nil
        defaultsSuiteName = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    func testExportIncludesNotesFoldersAndHistory() throws {
        let store = SharedStore(
            defaults: defaults,
            storageDirectoryURL: rootURL.appendingPathComponent("SharedStore", isDirectory: true),
            shouldMigrate: false,
            shouldReloadWidgets: false
        )
        let folder = store.createFolder(name: "Research")
        let noteID = store.createNote(
            attributedText: NSAttributedString(string: "Draft"),
            title: "Paper",
            folderID: folder.id
        )
        store.updateNote(id: noteID, attributedText: NSAttributedString(string: "Draft with a long enough update to create note history."))

        let exportURL = try NoteExportService.exportLocalData(
            from: store,
            to: rootURL.appendingPathComponent("Exports", isDirectory: true)
        )
        let data = try Data(contentsOf: exportURL)
        let payload = try JSONDecoder.withISO8601Dates.decode(ExportPayload.self, from: data)

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.notes.map(\.id), [noteID])
        XCTAssertEqual(payload.notes.first?.title, "Paper")
        XCTAssertEqual(payload.folders.map(\.id), [folder.id])
        XCTAssertEqual(payload.history.count, 1)
        XCTAssertEqual(payload.history.first?.noteID, noteID)
    }
}

private struct ExportPayload: Decodable {
    let schemaVersion: Int
    let notes: [Note]
    let folders: [Folder]
    let history: [NoteHistoryEntry]
}

private extension JSONDecoder {
    static var withISO8601Dates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
