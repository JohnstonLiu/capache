import CryptoKit
import Foundation

enum WidgetBackgroundRefreshClient {
    static func uploadPendingPushTokens() async {
        guard let credentials = SharedStore.shared.widgetBackgroundRefreshCredentials() else { return }

        let tokens = SharedStore.shared.widgetPushTokens()
        guard !tokens.isEmpty else { return }

        for token in tokens {
            await uploadPushToken(token, credentials: credentials)
        }
    }

    static func refreshNote(id: UUID) async -> Note? {
        guard let credentials = SharedStore.shared.widgetBackgroundRefreshCredentials() else { return nil }
        let endpoint = credentials.supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("widget-note-snapshot")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(NoteSnapshotRequest(
            refreshToken: credentials.refreshToken,
            noteID: id
        ))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 404 {
                SharedStore.shared.deleteNote(id: id)
                return nil
            }

            guard (200..<300).contains(httpResponse.statusCode) else { return nil }

            let snapshot = try JSONDecoder().decode(NoteSnapshotResponse.self, from: data)
            let note = try snapshot.note.note(keyData: credentials.syncKeyData)
            SharedStore.shared.cacheNote(note)
            return note
        } catch {
            return nil
        }
    }

    private static func uploadPushToken(
        _ token: String,
        credentials: SharedStore.WidgetBackgroundRefreshCredentials
    ) async {
        let endpoint = credentials.supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("widget-register-push-token")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(PushTokenRegistrationRequest(
            refreshToken: credentials.refreshToken,
            pushToken: token,
            environment: apnsEnvironment
        ))

        _ = try? await URLSession.shared.data(for: request)
    }

    private static var apnsEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}

private struct PushTokenRegistrationRequest: Encodable {
    let refreshToken: String
    let pushToken: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case pushToken = "push_token"
        case environment
    }
}

private struct NoteSnapshotRequest: Encodable {
    let refreshToken: String
    let noteID: UUID

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case noteID = "note_id"
    }
}

private struct NoteSnapshotResponse: Decodable {
    let note: WidgetRemoteNote
}

private struct WidgetRemoteNote: Decodable {
    let id: UUID
    let title: String?
    let rtfData: String?
    let plainText: String?
    let encryptedPayload: String?
    let encryptionVersion: Int?
    let updatedAt: String
    let folderID: UUID?
    let isPinned: Bool?
    let isArchived: Bool?
    let contentHash: String?

    func note(keyData: Data) throws -> Note {
        let content: WidgetNoteContent
        if let encryptedPayload, !encryptedPayload.isEmpty, encryptionVersion == 1 {
            content = try WidgetNoteCrypto.decrypt(encryptedPayload, keyData: keyData)
        } else {
            content = WidgetNoteContent(
                title: title ?? "",
                rtfDataBase64: rtfData ?? "",
                plainText: plainText ?? ""
            )
        }

        var note = Note(
            id: id,
            title: content.title,
            rtfData: Data(base64Encoded: content.rtfDataBase64) ?? Data(),
            plainText: content.plainText,
            updatedAt: WidgetSupabaseDate.parse(updatedAt),
            folderID: folderID,
            isPinned: isPinned ?? false,
            isArchived: isArchived ?? false
        )
        note.lastSyncedContentHash = contentHash
        note.lastSyncedAt = note.updatedAt
        note.isCloudSyncEnabled = true
        return note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case rtfData = "rtf_data"
        case plainText = "plain_text"
        case encryptedPayload = "encrypted_payload"
        case encryptionVersion = "encryption_version"
        case updatedAt = "updated_at"
        case folderID = "folder_id"
        case isPinned = "is_pinned"
        case isArchived = "is_archived"
        case contentHash = "content_hash"
    }
}

private struct WidgetNoteContent: Codable {
    let title: String
    let rtfDataBase64: String
    let plainText: String
}

private enum WidgetNoteCrypto {
    static func decrypt(_ payload: String, keyData: Data) throws -> WidgetNoteContent {
        guard let data = Data(base64Encoded: payload) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))
        return try JSONDecoder().decode(WidgetNoteContent.self, from: plaintext)
    }
}

private enum WidgetSupabaseDate {
    static func parse(_ value: String) -> Date {
        fractionalFormatter().date(from: value)
            ?? wholeSecondFormatter().date(from: value)
            ?? Date()
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func wholeSecondFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
