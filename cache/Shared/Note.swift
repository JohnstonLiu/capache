import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var rtfData: Data
    var plainText: String
    var updatedAt: Date

    init(id: UUID, rtfData: Data, plainText: String, updatedAt: Date) {
        self.id = id
        self.rtfData = rtfData
        self.plainText = plainText
        self.updatedAt = updatedAt
    }

    init(id: UUID = UUID(), attributedText: NSAttributedString, updatedAt: Date = Date()) {
        self.id = id
        self.rtfData = RichTextCodec.rtfData(from: attributedText)
        self.plainText = attributedText.string
        self.updatedAt = updatedAt
    }

    static func empty(id: UUID = UUID()) -> Note {
        Note(id: id, attributedText: NSAttributedString(string: ""), updatedAt: Date())
    }
}
