import AppIntents
import Foundation

struct NoteEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static var defaultQuery = NoteQuery()

    let id: UUID
    let text: String
    let updatedAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(previewText(text))",
            subtitle: "\(updatedAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    private func previewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Empty note"
        }
        return String(trimmed.prefix(64))
    }
}

struct NoteQuery: EntityQuery {
    func entities(matching string: String) async throws -> [NoteEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = SharedStore.shared.listNotes()
        let filtered = trimmed.isEmpty
            ? notes
            : notes.filter { $0.plainText.localizedCaseInsensitiveContains(trimmed) }
        return filtered.map { note in
            NoteEntity(id: note.id, text: note.plainText, updatedAt: note.updatedAt)
        }
    }

    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        let notes = SharedStore.shared.listNotes()
        let map = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            guard let note = map[id] else { return nil }
            return NoteEntity(id: note.id, text: note.plainText, updatedAt: note.updatedAt)
        }
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        SharedStore.shared.listNotes().map { note in
            NoteEntity(id: note.id, text: note.plainText, updatedAt: note.updatedAt)
        }
    }
}
