import CryptoKit
import Foundation

enum StandardSyncEncryption {
    static let version = 1
    static let keyByteCount = 32

    struct NoteContent: Codable, Equatable {
        let title: String
        let rtfDataBase64: String
        let plainText: String
    }

    struct HistoryContent: Codable, Equatable {
        let rtfDataBase64: String
        let plainText: String
    }

    static func generateKeyData() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    static func validateKeyData(_ keyData: Data) throws {
        guard keyData.count == keyByteCount else {
            throw StandardSyncEncryptionError.invalidKeyLength
        }
    }

    static func noteContent(from note: Note) -> NoteContent {
        NoteContent(
            title: note.title,
            rtfDataBase64: note.rtfData.base64EncodedString(),
            plainText: note.plainText
        )
    }

    static func historyContent(from entry: NoteHistoryEntry) -> HistoryContent {
        HistoryContent(
            rtfDataBase64: entry.rtfData.base64EncodedString(),
            plainText: entry.plainText
        )
    }

    static func encryptNoteContent(_ content: NoteContent, keyData: Data) throws -> String {
        try encrypt(content, keyData: keyData)
    }

    static func decryptNoteContent(_ payload: String, keyData: Data) throws -> NoteContent {
        try decrypt(payload, as: NoteContent.self, keyData: keyData)
    }

    static func encryptHistoryContent(_ content: HistoryContent, keyData: Data) throws -> String {
        try encrypt(content, keyData: keyData)
    }

    static func decryptHistoryContent(_ payload: String, keyData: Data) throws -> HistoryContent {
        try decrypt(payload, as: HistoryContent.self, keyData: keyData)
    }

    private static func encrypt<T: Encodable>(_ value: T, keyData: Data) throws -> String {
        try validateKeyData(keyData)
        let plaintext = try JSONEncoder().encode(value)
        let sealedBox = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData))
        guard let combined = sealedBox.combined else {
            throw StandardSyncEncryptionError.missingCombinedCiphertext
        }
        return combined.base64EncodedString()
    }

    private static func decrypt<T: Decodable>(_ payload: String, as type: T.Type, keyData: Data) throws -> T {
        try validateKeyData(keyData)
        guard let data = Data(base64Encoded: payload) else {
            throw StandardSyncEncryptionError.invalidPayload
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))
        return try JSONDecoder().decode(type, from: plaintext)
    }
}

enum StandardSyncEncryptionError: LocalizedError {
    case invalidKeyLength
    case invalidPayload
    case missingCombinedCiphertext

    var errorDescription: String? {
        switch self {
        case .invalidKeyLength:
            return "The sync encryption key is invalid."
        case .invalidPayload:
            return "The encrypted sync payload is invalid."
        case .missingCombinedCiphertext:
            return "The encrypted sync payload could not be created."
        }
    }
}
