import XCTest
@testable import Capache

final class NoteModelTests: XCTestCase {
    func testLegacyNotesDecodeWithNewMetadataDefaults() throws {
        let id = UUID()
        let updatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let legacyNote = LegacyNote(
            id: id,
            rtfData: RichTextCodec.rtfData(from: NSAttributedString(string: "Legacy body")),
            plainText: "Legacy body",
            updatedAt: updatedAt
        )

        let data = try JSONEncoder().encode([legacyNote])
        let notes = try JSONDecoder().decode([Note].self, from: data)

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.id, id)
        XCTAssertEqual(notes.first?.title, "")
        XCTAssertEqual(notes.first?.plainText, "Legacy body")
        XCTAssertEqual(notes.first?.updatedAt, updatedAt)
        XCTAssertNil(notes.first?.folderID)
        XCTAssertEqual(notes.first?.isPinned, false)
        XCTAssertEqual(notes.first?.isArchived, false)
        XCTAssertNil(notes.first?.lastSyncedContentHash)
        XCTAssertNil(notes.first?.lastSyncedAt)
        XCTAssertEqual(notes.first?.isCloudSyncEnabled, true)
        XCTAssertEqual(notes.first?.isConflict, false)
        XCTAssertNil(notes.first?.conflictParentID)
        XCTAssertNil(notes.first?.conflictCreatedAt)
    }

    func testDisplayTitlePrefersExplicitTitleThenFirstLineThenUntitled() {
        XCTAssertEqual(
            Note(title: "Explicit", attributedText: NSAttributedString(string: "Body")).displayTitle,
            "Explicit"
        )
        XCTAssertEqual(
            Note(attributedText: NSAttributedString(string: "First line\nSecond line")).displayTitle,
            "First line"
        )
        XCTAssertEqual(
            Note(attributedText: NSAttributedString(string: "   \n")).displayTitle,
            "Untitled"
        )
    }
}

private struct LegacyNote: Encodable {
    let id: UUID
    let rtfData: Data
    let plainText: String
    let updatedAt: Date
}
