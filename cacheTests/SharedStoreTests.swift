import XCTest
@testable import Capache

final class SharedStoreTests: XCTestCase {
    private var rootURL: URL!
    private var storageURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacheSharedStoreTests-\(UUID().uuidString)", isDirectory: true)
        storageURL = rootURL.appendingPathComponent("SharedStore", isDirectory: true)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        defaultsSuiteName = "CapacheSharedStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootURL)
        defaults = nil
        defaultsSuiteName = nil
        storageURL = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    func testNotesFoldersAndHistoryPersistInFileBackedStore() throws {
        let store = makeStore()
        let folder = store.createFolder(name: "Projects")
        let noteID = store.createNote(
            attributedText: NSAttributedString(string: "Initial"),
            title: "Plan",
            folderID: folder.id,
            isPinned: true
        )

        store.updateNote(id: noteID, attributedText: NSAttributedString(string: "Initial plus enough text to create a useful history snapshot."))

        let reloadedStore = makeStore()
        let notes = reloadedStore.listNotes()
        let folders = reloadedStore.listFolders()
        let history = reloadedStore.listAllHistory()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.id, noteID)
        XCTAssertEqual(notes.first?.title, "Plan")
        XCTAssertEqual(notes.first?.folderID, folder.id)
        XCTAssertEqual(notes.first?.isPinned, true)
        XCTAssertEqual(notes.first?.plainText, "Initial plus enough text to create a useful history snapshot.")
        XCTAssertEqual(folders.map(\.id), [folder.id])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.noteID, noteID)
    }

    func testDeletingRootFolderMovesNotesAndSubfoldersToRoot() {
        let store = makeStore()
        let folder = store.createFolder(name: "Archive")
        let childFolder = store.createFolder(name: "Nested", parentID: folder.id)
        let noteID = store.createNote(
            attributedText: NSAttributedString(string: "Keep this"),
            folderID: folder.id
        )

        store.deleteFolder(id: folder.id)

        XCTAssertEqual(store.listFolders().map(\.id), [childFolder.id])
        XCTAssertEqual(store.getFolder(id: childFolder.id)?.parentID, nil)
        XCTAssertEqual(store.getNote(id: noteID)?.folderID, nil)
    }

    func testDeletingSubfolderMovesNotesAndChildrenToParent() {
        let store = makeStore()
        let parent = store.createFolder(name: "Projects")
        let child = store.createFolder(name: "Research", parentID: parent.id)
        let grandchild = store.createFolder(name: "Drafts", parentID: child.id)
        let noteID = store.createNote(
            attributedText: NSAttributedString(string: "Keep this"),
            folderID: child.id
        )

        store.deleteFolder(id: child.id)

        XCTAssertNil(store.getFolder(id: child.id))
        XCTAssertEqual(store.getFolder(id: grandchild.id)?.parentID, parent.id)
        XCTAssertEqual(store.getNote(id: noteID)?.folderID, parent.id)
    }

    func testEmptyPrimaryFileFallsBackToNonEmptyDefaultsCache() throws {
        let store = makeStore()
        let noteID = store.createNote(attributedText: NSAttributedString(string: "From defaults"))

        let notesData = try XCTUnwrap(defaults.data(forKey: "notes"))
        XCTAssertFalse(try JSONDecoder().decode([Note].self, from: notesData).isEmpty)

        let emptyArrayData = try JSONEncoder().encode([Note]())
        try emptyArrayData.write(to: storageURL.appendingPathComponent("notes.json"), options: .atomic)

        let recoveredStore = makeStore()
        let notes = recoveredStore.listNotes()

        XCTAssertEqual(notes.map(\.id), [noteID])
        let recoveredFileData = try Data(contentsOf: storageURL.appendingPathComponent("notes.json"))
        XCTAssertEqual(try JSONDecoder().decode([Note].self, from: recoveredFileData).map(\.id), [noteID])
    }

    func testStorePostsChangeNotificationAfterNoteSave() {
        let expectation = expectation(description: "SharedStore posts did-change notification")
        let token = NotificationCenter.default.addObserver(
            forName: SharedStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        makeStore().createNote(attributedText: NSAttributedString(string: "Preview update"))

        wait(for: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(token)
    }

    func testMarkConflictResolvedClearsConflictMetadata() {
        let store = makeStore()
        let parentID = UUID()
        let noteID = store.createNote(
            attributedText: NSAttributedString(string: "Resolve me"),
            title: "Conflict copy",
            isPinned: false
        )
        var note = store.getNote(id: noteID)!
        note.isConflict = true
        note.conflictParentID = parentID
        note.conflictCreatedAt = Date()
        store.cacheNote(note)

        store.markConflictResolved(id: noteID)

        let resolved = store.getNote(id: noteID)
        XCTAssertEqual(resolved?.isConflict, false)
        XCTAssertNil(resolved?.conflictParentID)
        XCTAssertNil(resolved?.conflictCreatedAt)
    }

    func testSetNoteCloudSyncEnabledClearsSyncBaselineWhenDisabled() {
        let store = makeStore()
        let noteID = store.createNote(attributedText: NSAttributedString(string: "Private"))
        var note = store.getNote(id: noteID)!
        note.lastSyncedContentHash = "hash"
        note.lastSyncedAt = Date()
        store.cacheNote(note)

        store.setNoteCloudSyncEnabled(id: noteID, isEnabled: false)

        let localOnly = store.getNote(id: noteID)
        XCTAssertEqual(localOnly?.isCloudSyncEnabled, false)
        XCTAssertNil(localOnly?.lastSyncedContentHash)
        XCTAssertNil(localOnly?.lastSyncedAt)
    }

    func testSetAllNotesCloudSyncEnabledClearsBaselinesWhenDisabled() {
        let store = makeStore()
        let firstID = store.createNote(attributedText: NSAttributedString(string: "First"))
        let secondID = store.createNote(attributedText: NSAttributedString(string: "Second"))
        for id in [firstID, secondID] {
            var note = store.getNote(id: id)!
            note.lastSyncedContentHash = "hash-\(id.uuidString)"
            note.lastSyncedAt = Date()
            store.cacheNote(note)
        }

        store.setAllNotesCloudSyncEnabled(false)

        for note in store.listNotes() {
            XCTAssertEqual(note.isCloudSyncEnabled, false)
            XCTAssertNil(note.lastSyncedContentHash)
            XCTAssertNil(note.lastSyncedAt)
        }
    }

    func testWidgetBackgroundRefreshCredentialsPersistAndClear() throws {
        let store = makeStore()
        let pushToken = Data([0x0a, 0x1b, 0xff])
        let refreshToken = store.currentOrCreateWidgetRefreshToken()
        let syncKeyData = Data(repeating: 7, count: 32)

        store.recordWidgetPushToken(pushToken)
        store.saveWidgetBackgroundRefreshCredentials(
            supabaseURLString: "https://example.supabase.co",
            refreshToken: refreshToken,
            syncKeyData: syncKeyData
        )

        let reloadedStore = makeStore()
        let credentials = try XCTUnwrap(reloadedStore.widgetBackgroundRefreshCredentials())
        XCTAssertEqual(reloadedStore.widgetPushTokens(), ["0a1bff"])
        XCTAssertEqual(credentials.supabaseURL.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(credentials.refreshToken, refreshToken)
        XCTAssertEqual(credentials.syncKeyData, syncKeyData)

        reloadedStore.clearWidgetBackgroundRefreshCredentials()

        XCTAssertTrue(reloadedStore.widgetPushTokens().isEmpty)
        XCTAssertNil(reloadedStore.widgetBackgroundRefreshCredentials())
    }

    private func makeStore() -> SharedStore {
        SharedStore(
            defaults: defaults,
            storageDirectoryURL: storageURL,
            shouldMigrate: false,
            shouldReloadWidgets: false
        )
    }
}
