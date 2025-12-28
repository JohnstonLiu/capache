import Combine
import Foundation

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []

    func reload() {
        notes = SharedStore.shared.listNotes()
    }

    func createNote() -> UUID {
        let id = SharedStore.shared.createNote()
        reload()
        return id
    }

    func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let id = notes[index].id
            SharedStore.shared.deleteNote(id: id)
        }
        reload()
    }
}
