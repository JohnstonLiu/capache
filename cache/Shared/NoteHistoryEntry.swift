import Foundation

struct NoteHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let noteID: UUID
    let rtfData: Data
    let plainText: String
    let createdAt: Date
    let contentHash: String
}
