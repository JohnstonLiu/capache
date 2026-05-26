import AppIntents
import Foundation

struct NoteEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static var defaultQuery = NoteQuery()

    let id: UUID
    let title: String
    let text: String
    let updatedAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(updatedAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }
}

struct NoteQuery: EntityQuery {
    func entities(matching string: String) async throws -> [NoteEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = SharedStore.shared.listNotes()
        let filtered = trimmed.isEmpty
            ? notes
            : notes.filter { $0.searchableText.localizedCaseInsensitiveContains(trimmed) }
        return filtered.map { note in
            NoteEntity(id: note.id, title: note.displayTitle, text: note.plainText, updatedAt: note.updatedAt)
        }
    }

    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        let notes = SharedStore.shared.listNotes()
        let map = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            guard let note = map[id] else { return nil }
            return NoteEntity(id: note.id, title: note.displayTitle, text: note.plainText, updatedAt: note.updatedAt)
        }
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        SharedStore.shared.listNotes().filter { !$0.isArchived }.map { note in
            NoteEntity(id: note.id, title: note.displayTitle, text: note.plainText, updatedAt: note.updatedAt)
        }
    }
}
