import XCTest
@testable import Capache

final class NoteListScopeTests: XCTestCase {
    func testRootScopeOnlyShowsRootNotesAndAllScopeShowsEveryActiveNote() {
        let folderID = UUID()
        let notes = [
            makeNote("Root note"),
            makeNote("Folder note", folderID: folderID),
            makeNote("Archived root note", isArchived: true)
        ]
        let folders = [
            Folder(id: folderID, name: "Projects")
        ]

        XCTAssertEqual(
            NotesViewModel.visibleNotes(notes, folders: folders, for: .root, searchText: "").map(\.plainText),
            ["Root note"]
        )
        XCTAssertEqual(
            NotesViewModel.visibleNotes(notes, folders: folders, for: .all, searchText: "").map(\.plainText),
            ["Root note", "Folder note"]
        )
        XCTAssertEqual(
            NotesViewModel.visibleNotes(notes, folders: folders, for: .folder(folderID), searchText: "").map(\.plainText),
            ["Folder note"]
        )
    }

    func testRootScopeSearchDoesNotLeakFolderNotes() {
        let folderID = UUID()
        let notes = [
            makeNote("Root note"),
            makeNote("Folder note", folderID: folderID)
        ]
        let folders = [
            Folder(id: folderID, name: "Projects")
        ]

        XCTAssertTrue(
            NotesViewModel.visibleNotes(notes, folders: folders, for: .root, searchText: "Projects").isEmpty
        )
        XCTAssertEqual(
            NotesViewModel.visibleNotes(notes, folders: folders, for: .all, searchText: "Projects").map(\.plainText),
            ["Folder note"]
        )
    }

    private func makeNote(
        _ text: String,
        folderID: UUID? = nil,
        isArchived: Bool = false
    ) -> Note {
        Note(
            attributedText: NSAttributedString(string: text),
            folderID: folderID,
            isArchived: isArchived
        )
    }
}
