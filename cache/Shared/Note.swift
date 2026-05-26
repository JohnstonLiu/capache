import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var rtfData: Data
    var plainText: String
    var updatedAt: Date
    var folderID: UUID?
    var isPinned: Bool
    var isArchived: Bool
    var lastSyncedContentHash: String?
    var lastSyncedAt: Date?
    var isCloudSyncEnabled: Bool
    var isConflict: Bool
    var conflictParentID: UUID?
    var conflictCreatedAt: Date?

    init(
        id: UUID,
        title: String = "",
        rtfData: Data,
        plainText: String,
        updatedAt: Date,
        folderID: UUID? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        lastSyncedContentHash: String? = nil,
        lastSyncedAt: Date? = nil,
        isCloudSyncEnabled: Bool = true,
        isConflict: Bool = false,
        conflictParentID: UUID? = nil,
        conflictCreatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.rtfData = rtfData
        self.plainText = plainText
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.lastSyncedContentHash = lastSyncedContentHash
        self.lastSyncedAt = lastSyncedAt
        self.isCloudSyncEnabled = isCloudSyncEnabled
        self.isConflict = isConflict
        self.conflictParentID = conflictParentID
        self.conflictCreatedAt = conflictCreatedAt
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        attributedText: NSAttributedString,
        updatedAt: Date = Date(),
        folderID: UUID? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        lastSyncedContentHash: String? = nil,
        lastSyncedAt: Date? = nil,
        isCloudSyncEnabled: Bool = true,
        isConflict: Bool = false,
        conflictParentID: UUID? = nil,
        conflictCreatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.rtfData = RichTextCodec.rtfData(from: attributedText)
        self.plainText = attributedText.string
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.lastSyncedContentHash = lastSyncedContentHash
        self.lastSyncedAt = lastSyncedAt
        self.isCloudSyncEnabled = isCloudSyncEnabled
        self.isConflict = isConflict
        self.conflictParentID = conflictParentID
        self.conflictCreatedAt = conflictCreatedAt
    }

    static func empty(id: UUID = UUID()) -> Note {
        Note(id: id, attributedText: NSAttributedString(string: ""), updatedAt: Date())
    }

    var displayTitle: String {
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitTitle.isEmpty {
            return explicitTitle
        }

        let firstLine = plainText
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? "Untitled" : firstLine
    }

    var previewText: String {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "jot..."
        }
        return trimmed
    }

    var searchableText: String {
        "\(title)\n\(plainText)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case rtfData
        case plainText
        case updatedAt
        case folderID
        case isPinned
        case isArchived
        case lastSyncedContentHash
        case lastSyncedAt
        case isCloudSyncEnabled
        case isConflict
        case conflictParentID
        case conflictCreatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        rtfData = try container.decode(Data.self, forKey: .rtfData)
        plainText = try container.decode(String.self, forKey: .plainText)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        lastSyncedContentHash = try container.decodeIfPresent(String.self, forKey: .lastSyncedContentHash)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        isCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCloudSyncEnabled) ?? true
        isConflict = try container.decodeIfPresent(Bool.self, forKey: .isConflict) ?? false
        conflictParentID = try container.decodeIfPresent(UUID.self, forKey: .conflictParentID)
        conflictCreatedAt = try container.decodeIfPresent(Date.self, forKey: .conflictCreatedAt)
    }
}
