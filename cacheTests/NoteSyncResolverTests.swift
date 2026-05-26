import XCTest
@testable import Capache

final class NoteSyncResolverTests: XCTestCase {
    func testSameLocalAndRemoteNoteDoesNotUploadAndMarksRemoteSynced() {
        let note = makeNote(text: "Same")
        let firstHash = NoteSyncResolver.fingerprint(note)
        let secondHash = NoteSyncResolver.fingerprint(note)
        XCTAssertEqual(firstHash, secondHash)

        let plan = NoteSyncResolver.plan(localNotes: [note], remoteNotes: [note])

        XCTAssertTrue(plan.notesToUpload.isEmpty, "Expected no uploads, got \(plan.notesToUpload.map(\.plainText))")
        XCTAssertEqual(plan.remoteNotesToCache.count, 1)
        XCTAssertEqual(plan.remoteNotesToCache.first?.lastSyncedContentHash, firstHash)
    }

    func testBothChangedSinceBaseWithRemoteNewerCachesRemote() {
        let id = UUID()
        let base = makeNote(id: id, title: "Shared", text: "Base", updatedAt: Date(timeIntervalSinceReferenceDate: 10))
        let baseHash = NoteSyncResolver.fingerprint(base)
        let local = makeNote(
            id: id,
            title: "Shared",
            text: "Local edit",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20),
            lastSyncedContentHash: baseHash
        )
        let remote = makeNote(
            id: id,
            title: "Shared",
            text: "Remote edit",
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        let plan = NoteSyncResolver.plan(
            localNotes: [local],
            remoteNotes: [remote],
            now: Date(timeIntervalSinceReferenceDate: 40)
        )

        XCTAssertTrue(plan.notesToUpload.isEmpty)
        XCTAssertEqual(plan.remoteNotesToCache.map(\.id), [id])
        XCTAssertEqual(plan.remoteNotesToCache.first?.plainText, "Remote edit")
    }

    func testBothChangedSinceBaseWithLocalNewerUploadsLocalOnly() {
        let id = UUID()
        let base = makeNote(id: id, text: "Base", updatedAt: Date(timeIntervalSinceReferenceDate: 10))
        let baseHash = NoteSyncResolver.fingerprint(base)
        let local = makeNote(
            id: id,
            text: "Local newer",
            updatedAt: Date(timeIntervalSinceReferenceDate: 40),
            lastSyncedContentHash: baseHash
        )
        let remote = makeNote(
            id: id,
            text: "Remote older",
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        let plan = NoteSyncResolver.plan(
            localNotes: [local],
            remoteNotes: [remote],
            now: Date(timeIntervalSinceReferenceDate: 50)
        )

        XCTAssertEqual(plan.notesToUpload.count, 1)
        XCTAssertEqual(plan.notesToUpload.first?.id, id)
        XCTAssertEqual(plan.notesToUpload.first?.plainText, "Local newer")
        XCTAssertFalse(plan.notesToUpload.first?.isConflict ?? true)
        XCTAssertTrue(plan.remoteNotesToCache.isEmpty)
    }

    func testMissingBaselineUsesNewerVersion() {
        let id = UUID()
        let local = makeNote(
            id: id,
            text: "Local without baseline",
            updatedAt: Date(timeIntervalSinceReferenceDate: 40)
        )
        let remote = makeNote(
            id: id,
            text: "Remote without baseline",
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        let plan = NoteSyncResolver.plan(localNotes: [local], remoteNotes: [remote])

        XCTAssertEqual(plan.notesToUpload.count, 1)
        XCTAssertEqual(plan.notesToUpload.first?.id, id)
        XCTAssertEqual(plan.notesToUpload.first?.plainText, "Local without baseline")
        XCTAssertFalse(plan.notesToUpload.first?.isConflict ?? true)
        XCTAssertTrue(plan.remoteNotesToCache.isEmpty)
    }

    func testUnsyncedLocalNoteMissingRemoteUploadsForInitialMigration() {
        let local = makeNote(text: "Local only")

        let plan = NoteSyncResolver.plan(localNotes: [local], remoteNotes: [])

        XCTAssertEqual(plan.notesToUpload.map(\.id), [local.id])
    }

    func testPreviouslySyncedLocalNoteMissingRemoteDoesNotResurrectDeletedRemoteNote() {
        let note = makeNote(text: "Deleted elsewhere")
        let syncedNote = NoteSyncResolver.markSynced(note)

        let plan = NoteSyncResolver.plan(localNotes: [syncedNote], remoteNotes: [])

        XCTAssertTrue(plan.notesToUpload.isEmpty)
        XCTAssertTrue(plan.remoteNotesToCache.isEmpty)
        XCTAssertTrue(plan.localNotesToKeep.isEmpty)
    }

    func testPreviouslySyncedLocalEditMissingRemoteUploadsLocal() {
        let id = UUID()
        let base = makeNote(id: id, text: "Base")
        let baseHash = NoteSyncResolver.fingerprint(base)
        let local = makeNote(
            id: id,
            text: "Offline edit",
            updatedAt: Date(timeIntervalSinceReferenceDate: 20),
            lastSyncedContentHash: baseHash
        )

        let plan = NoteSyncResolver.plan(
            localNotes: [local],
            remoteNotes: [],
            now: Date(timeIntervalSinceReferenceDate: 30)
        )

        XCTAssertEqual(plan.notesToUpload.count, 1)
        XCTAssertEqual(plan.notesToUpload.first?.id, id)
        XCTAssertEqual(plan.notesToUpload.first?.plainText, "Offline edit")
        XCTAssertEqual(plan.notesToUpload.first?.isConflict, false)
        XCTAssertNil(plan.notesToUpload.first?.conflictParentID)
        XCTAssertTrue(plan.remoteNotesToCache.isEmpty)
    }

    func testLocalOnlyNoteIsKeptAndNotUploaded() {
        let local = makeNote(text: "Private", isCloudSyncEnabled: false)

        let plan = NoteSyncResolver.plan(localNotes: [local], remoteNotes: [])

        XCTAssertTrue(plan.notesToUpload.isEmpty)
        XCTAssertTrue(plan.remoteNotesToCache.isEmpty)
        XCTAssertEqual(plan.localNotesToKeep.map(\.id), [local.id])
        XCTAssertEqual(plan.localNotesToKeep.first?.isCloudSyncEnabled, false)
    }

    func testConflictCopyIDIsStableForSameParentAndContent() {
        let parentID = UUID()
        let source = makeNote(title: "Shared", text: "Remote version")

        let firstCopy = NoteSyncResolver.conflictCopy(
            from: source,
            parentID: parentID,
            now: Date(timeIntervalSinceReferenceDate: 10)
        )
        let secondCopy = NoteSyncResolver.conflictCopy(
            from: source,
            parentID: parentID,
            now: Date(timeIntervalSinceReferenceDate: 20)
        )

        XCTAssertEqual(firstCopy.id, secondCopy.id)
        XCTAssertEqual(firstCopy.title, "Conflict copy - Shared")
        XCTAssertEqual(secondCopy.title, "Conflict copy - Shared")
    }

    func testDuplicateConflictCopiesAreDetectedByParentAndContent() {
        let parentID = UUID()
        let source = makeNote(title: "Shared", text: "Remote version")
        let oldDuplicate = makeConflictCopyLike(
            source,
            parentID: parentID,
            updatedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let newestDuplicate = makeConflictCopyLike(
            source,
            parentID: parentID,
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        let differentParent = makeConflictCopyLike(
            source,
            parentID: UUID(),
            updatedAt: Date(timeIntervalSinceReferenceDate: 30)
        )

        let duplicates = NoteSyncResolver.duplicateConflictCopyIDs(in: [
            oldDuplicate,
            newestDuplicate,
            differentParent,
        ])

        XCTAssertEqual(duplicates, [oldDuplicate.id])
    }

    private func makeNote(
        id: UUID = UUID(),
        title: String = "",
        text: String,
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 10),
        lastSyncedContentHash: String? = nil,
        isCloudSyncEnabled: Bool = true
    ) -> Note {
        Note(
            id: id,
            title: title,
            attributedText: NSAttributedString(string: text),
            updatedAt: updatedAt,
            lastSyncedContentHash: lastSyncedContentHash,
            isCloudSyncEnabled: isCloudSyncEnabled
        )
    }

    private func makeConflictCopyLike(_ source: Note, parentID: UUID, updatedAt: Date) -> Note {
        Note(
            id: UUID(),
            title: "Conflict copy - \(source.displayTitle)",
            rtfData: source.rtfData,
            plainText: source.plainText,
            updatedAt: updatedAt,
            folderID: source.folderID,
            isPinned: source.isPinned,
            isArchived: source.isArchived,
            isConflict: true,
            conflictParentID: parentID,
            conflictCreatedAt: updatedAt
        )
    }
}
