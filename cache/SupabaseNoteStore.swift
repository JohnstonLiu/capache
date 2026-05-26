import CryptoKit
import Foundation
import Supabase

final class SupabaseNoteStore {
    static let shared = SupabaseNoteStore()

    private let client: SupabaseClient?
    private var cachedStandardEncryptionKeyData: Data?
    private var cachedStandardEncryptionKeyUserID: UUID?

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseService.client
    }

    func listNotes() async throws -> [Note] {
        let client = try await requireActiveClient()
        _ = try await syncLocalFoldersIfNeeded(client: client)
        let keyData = try await standardEncryptionKeyData(client: client)
        let remoteNoteRows = try await fetchRemoteNoteRows(client: client)
        let remoteNotes = try remoteNoteRows.map { try $0.note(keyData: keyData) }
        try await encryptLegacyRemoteNotesIfNeeded(
            remoteRows: remoteNoteRows,
            remoteNotes: remoteNotes,
            client: client
        )
        let migratedNotes = try await migrateLocalNotesIfNeeded(remoteNotes: remoteNotes, client: client)
        return sortNotes(migratedNotes)
    }

    func listFolders() async throws -> [Folder] {
        let client = try await requireActiveClient()
        let folders = try await syncLocalFoldersIfNeeded(client: client)
        SharedStore.shared.replaceFoldersCache(folders)
        return folders
    }

    func prepareWidgetBackgroundRefresh() async throws {
        let client = try await requireActiveClient()
        let keyData = try await standardEncryptionKeyData(client: client)
        let refreshToken = SharedStore.shared.currentOrCreateWidgetRefreshToken()

        SharedStore.shared.saveWidgetBackgroundRefreshCredentials(
            supabaseURLString: SupabaseConfig.urlString,
            refreshToken: refreshToken,
            syncKeyData: keyData
        )

        try await registerWidgetRefreshToken(refreshToken, client: client)
        try await registerWidgetPushTokens(client: client)
    }

    func getNote(id: UUID) async throws -> Note? {
        let cached = SharedStore.shared.getNote(id: id)
        if let cached, !cached.isCloudSyncEnabled {
            return cached
        }

        let client = try await requireActiveClient()
        let response: PostgrestResponse<[RemoteNote]> = try await client
            .from("notes")
            .select(Self.noteColumns)
            .eq("id", value: id)
            .limit(1)
            .execute()

        let keyData = try await standardEncryptionKeyData(client: client)
        guard let note = try response.value.first?.note(keyData: keyData) else {
            return cached
        }

        let syncedNote = NoteSyncResolver.markSynced(note)
        SharedStore.shared.cacheNote(syncedNote)
        return syncedNote
    }

    func createNote(
        attributedText: NSAttributedString = NSAttributedString(string: ""),
        title: String = "",
        folderID: UUID? = nil,
        isPinned: Bool = false
    ) async throws -> UUID {
        let client = try await requireActiveClient()
        let note = Note(
            id: UUID(),
            title: title,
            attributedText: attributedText,
            updatedAt: Date(),
            folderID: folderID,
            isPinned: isPinned
        )
        SharedStore.shared.cacheNote(note)
        do {
            try await upsert(note: note, client: client)
            SharedStore.shared.cacheNote(NoteSyncResolver.markSynced(note))
            await requestWidgetRefresh(client: client)
        } catch {
            SupabaseSessionInvalidation.postIfNeeded(for: error)
            // Keep the local note. The next sync pass will upload it because it has no baseline.
        }
        return note.id
    }

    @discardableResult
    func updateNote(
        id: UUID,
        attributedText: NSAttributedString,
        expectedBaseHash: String? = nil
    ) async throws -> Note {
        try await updateNote(
            id: id,
            title: nil,
            attributedText: attributedText,
            expectedBaseHash: expectedBaseHash
        )
    }

    @discardableResult
    func updateNote(
        id: UUID,
        title: String?,
        attributedText: NSAttributedString,
        expectedBaseHash: String? = nil
    ) async throws -> Note {
        let client = try await requireActiveClient()
        let previous = try await existingNote(id: id, client: client) ?? Note.empty(id: id)
        var note = previous
        if let title {
            note.title = title
        }
        note.rtfData = RichTextCodec.rtfData(from: attributedText)
        note.plainText = attributedText.string
        note.updatedAt = Date()
        if let expectedBaseHash {
            note.lastSyncedContentHash = expectedBaseHash
        }
        let historyEntry = historySnapshot(previous: previous, updated: note, now: note.updatedAt)

        SharedStore.shared.cacheNote(note)
        if let historyEntry {
            SharedStore.shared.cacheHistoryEntry(historyEntry)
        }

        guard note.isCloudSyncEnabled else {
            return note
        }

        try await upsertLastWriterWins(note: note, client: client)
        let syncedNote = NoteSyncResolver.markSynced(note)
        SharedStore.shared.cacheNote(syncedNote)

        if let historyEntry {
            try await insertHistory(entry: historyEntry, client: client)
        }

        await requestWidgetRefresh(client: client)
        return syncedNote
    }

    @discardableResult
    func updateNoteTitle(id: UUID, title: String, expectedBaseHash: String? = nil) async throws -> Note {
        try await updateNoteMetadata(
            id: id,
            mutate: { note in
                note.title = title
            },
            expectedBaseHash: expectedBaseHash
        )
    }

    func moveNote(id: UUID, folderID: UUID?) async throws {
        try await updateNoteMetadata(id: id) { note in
            note.folderID = folderID
        }
    }

    func setNotePinned(id: UUID, isPinned: Bool) async throws {
        try await updateNoteMetadata(id: id) { note in
            note.isPinned = isPinned
        }
    }

    func setNoteArchived(id: UUID, isArchived: Bool) async throws {
        try await updateNoteMetadata(id: id) { note in
            note.isArchived = isArchived
        }
    }

    func markConflictResolved(id: UUID) async throws {
        try await updateNoteMetadata(id: id) { note in
            note.isConflict = false
            note.conflictParentID = nil
            note.conflictCreatedAt = nil
        }
    }

    func setNoteCloudSyncEnabled(id: UUID, isEnabled: Bool) async throws {
        let client = try await requireActiveClient()
        var note = try await existingNote(id: id, client: client) ?? Note.empty(id: id)
        note.isCloudSyncEnabled = isEnabled
        note.updatedAt = Date()

        if isEnabled {
            try await upsertLastWriterWins(note: note, client: client)
            SharedStore.shared.cacheNote(NoteSyncResolver.markSynced(note))
        } else {
            note.lastSyncedContentHash = nil
            note.lastSyncedAt = nil
            try await deleteRemoteNoteIfPresent(id: id, client: client)
            SharedStore.shared.cacheNote(note)
        }
        await requestWidgetRefresh(client: client)
    }

    func createFolder(name: String, parentID: UUID? = nil) async throws -> Folder {
        let client = try await requireActiveClient()
        let now = Date()
        let folder = Folder(name: name, parentID: parentID, createdAt: now, updatedAt: now)
        try await client
            .from("folders")
            .insert(RemoteFolderPayload(folder: folder))
            .execute()
        SharedStore.shared.cacheFolder(folder)
        return folder
    }

    func renameFolder(id: UUID, name: String) async throws {
        let client = try await requireActiveClient()
        var folder = SharedStore.shared.getFolder(id: id) ?? Folder(id: id, name: name)
        folder.name = name
        folder.updatedAt = Date()
        try await client
            .from("folders")
            .upsert(RemoteFolderPayload(folder: folder), onConflict: "id")
            .execute()
        SharedStore.shared.cacheFolder(folder)
    }

    func deleteFolder(id: UUID) async throws {
        let client = try await requireActiveClient()
        let parentID = SharedStore.shared.getFolder(id: id)?.parentID
        try await client
            .from("folders")
            .update(FolderParentUpdatePayload(parentID: parentID))
            .eq("parent_id", value: id)
            .execute()
        try await client
            .from("notes")
            .update(NoteFolderUpdatePayload(folderID: parentID))
            .eq("folder_id", value: id)
            .execute()
        try await client
            .from("folders")
            .delete()
            .eq("id", value: id)
            .execute()
        SharedStore.shared.deleteFolder(id: id)
    }

    func deleteNote(id: UUID) async throws {
        let client = try await requireActiveClient()
        if let note = SharedStore.shared.getNote(id: id), !note.isCloudSyncEnabled {
            SharedStore.shared.deleteNote(id: id)
            return
        }

        try await client
            .from("notes")
            .delete()
            .eq("id", value: id)
            .execute()
        SharedStore.shared.deleteNote(id: id)
        await requestWidgetRefresh(client: client)
    }

    func listHistory(for noteID: UUID) async throws -> [NoteHistoryEntry] {
        let client = try await requireActiveClient()
        let response: PostgrestResponse<[RemoteHistoryEntry]> = try await client
            .from("note_history")
            .select(Self.historyColumns)
            .eq("note_id", value: noteID)
            .order("created_at", ascending: false)
            .execute()

        let keyData = try await standardEncryptionKeyData(client: client)
        let entries = try response.value.map { try $0.entry(keyData: keyData) }
        try await encryptLegacyHistoryEntriesIfNeeded(
            remoteRows: response.value,
            entries: entries,
            client: client
        )
        SharedStore.shared.replaceHistoryCache(entries, for: noteID)
        return entries
    }

    func deleteHistoryEntry(id: UUID) async throws {
        let client = try await requireActiveClient()
        try await client
            .from("note_history")
            .delete()
            .eq("id", value: id)
            .execute()
        SharedStore.shared.deleteHistoryEntry(id: id)
    }

    func clearHistory(for noteID: UUID) async throws {
        let client = try await requireActiveClient()
        try await client
            .from("note_history")
            .delete()
            .eq("note_id", value: noteID)
            .execute()
        SharedStore.shared.clearHistory(for: noteID)
    }

    func deleteSyncedData() async throws {
        let client = try await requireActiveClient()
        let userID = try await client.auth.session.user.id

        try await client
            .from("note_history")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("notes")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("folders")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("sync_keys")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("widget_snapshot_receipts")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("widget_push_receipts")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("widget_push_tokens")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        try await client
            .from("widget_refresh_tokens")
            .delete()
            .eq("user_id", value: userID)
            .execute()

        cachedStandardEncryptionKeyData = nil
        cachedStandardEncryptionKeyUserID = nil
        SharedStore.shared.clearWidgetBackgroundRefreshCredentials()
    }

    func deleteAccount() async throws {
        let client = try await requireActiveClient()
        try await client.functions.invoke("delete-user")
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else {
            throw SupabaseConfigurationError.missingPublishableKey
        }
        return client
    }

    private func requireActiveClient() async throws -> SupabaseClient {
        let client = try requireClient()
        do {
            _ = try await client.auth.user()
            return client
        } catch {
            SupabaseSessionInvalidation.postIfNeeded(for: error)
            throw error
        }
    }

    private func fetchNotes(client: SupabaseClient) async throws -> [Note] {
        let keyData = try await standardEncryptionKeyData(client: client)
        let rows = try await fetchRemoteNoteRows(client: client)
        return try rows.map { try $0.note(keyData: keyData) }
    }

    private func fetchRemoteNoteRows(client: SupabaseClient) async throws -> [RemoteNote] {
        let response: PostgrestResponse<[RemoteNote]> = try await client
            .from("notes")
            .select(Self.noteColumns)
            .order("updated_at", ascending: false)
            .execute()
        return response.value
    }

    private func fetchFolders(client: SupabaseClient) async throws -> [Folder] {
        let response: PostgrestResponse<[RemoteFolder]> = try await client
            .from("folders")
            .select(Self.folderColumns)
            .order("name", ascending: true)
            .execute()
        return response.value.map(\.folder)
    }

    private func upsert(note: Note, client: SupabaseClient) async throws {
        if let folderID = note.folderID, let folder = SharedStore.shared.getFolder(id: folderID) {
            try await upsert(folder: folder, client: client)
        }

        let keyData = try await standardEncryptionKeyData(client: client)
        let payload = try RemoteNotePayload(note: note, keyData: keyData)
        try await client
            .from("notes")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    private func upsert(folder: Folder, client: SupabaseClient) async throws {
        try await client
            .from("folders")
            .upsert(RemoteFolderPayload(folder: folder), onConflict: "id")
            .execute()
    }

    private func registerWidgetRefreshToken(_ refreshToken: String, client: SupabaseClient) async throws {
        let payload = RemoteWidgetRefreshTokenPayload(tokenHash: hashString(refreshToken))
        try await client
            .from("widget_refresh_tokens")
            .upsert(payload, onConflict: "token_hash")
            .execute()
    }

    private func registerWidgetPushTokens(client: SupabaseClient) async throws {
        let tokens = SharedStore.shared.widgetPushTokens()
        guard !tokens.isEmpty else { return }

        let payloads = tokens.map {
            RemoteWidgetPushTokenPayload(token: $0, environment: Self.apnsEnvironment)
        }

        try await client
            .from("widget_push_tokens")
            .upsert(payloads, onConflict: "token")
            .execute()
    }

    private func requestWidgetRefresh(client: SupabaseClient) async {
        do {
            try await client.functions.invoke("send-widget-refresh")
        } catch {
            // Widget refresh pushes are best-effort and must not block note persistence.
        }
    }

    private func insertHistory(entry: NoteHistoryEntry, client: SupabaseClient) async throws {
        let keyData = try await standardEncryptionKeyData(client: client)
        let payload = try RemoteHistoryPayload(entry: entry, keyData: keyData)
        try await client
            .from("note_history")
            .insert(payload)
            .execute()
    }

    private func fetchLatestHistoryEntry(noteID: UUID, client: SupabaseClient) async throws -> NoteHistoryEntry? {
        let response: PostgrestResponse<[RemoteHistoryEntry]> = try await client
            .from("note_history")
            .select(Self.historyColumns)
            .eq("note_id", value: noteID)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        let keyData = try await standardEncryptionKeyData(client: client)
        return try response.value.first?.entry(keyData: keyData)
    }

    @discardableResult
    private func updateNoteMetadata(
        id: UUID,
        mutate: (inout Note) -> Void,
        expectedBaseHash: String? = nil
    ) async throws -> Note {
        let client = try await requireActiveClient()
        var note = try await existingNote(id: id, client: client) ?? Note.empty(id: id)
        mutate(&note)
        note.updatedAt = Date()
        if let expectedBaseHash {
            note.lastSyncedContentHash = expectedBaseHash
        }
        SharedStore.shared.cacheNote(note)

        guard note.isCloudSyncEnabled else {
            return note
        }

        try await upsertLastWriterWins(note: note, client: client)
        let syncedNote = NoteSyncResolver.markSynced(note)
        SharedStore.shared.cacheNote(syncedNote)
        await requestWidgetRefresh(client: client)
        return syncedNote
    }

    private func existingNote(id: UUID, client: SupabaseClient) async throws -> Note? {
        if let cached = SharedStore.shared.getNote(id: id) {
            return cached
        }

        let response: PostgrestResponse<[RemoteNote]> = try await client
            .from("notes")
            .select(Self.noteColumns)
            .eq("id", value: id)
            .limit(1)
            .execute()

        let keyData = try await standardEncryptionKeyData(client: client)
        let note = try response.value.first?.note(keyData: keyData)
        if let note {
            SharedStore.shared.cacheNote(note)
        }
        return note
    }

    private func syncLocalFoldersIfNeeded(client: SupabaseClient) async throws -> [Folder] {
        let remoteFolders = try await fetchFolders(client: client)
        let remoteByID = Dictionary(uniqueKeysWithValues: remoteFolders.map { ($0.id, $0) })
        let localFolders = SharedStore.shared.listFolders()

        for folder in localFolders {
            if let remote = remoteByID[folder.id], remote.updatedAt >= folder.updatedAt {
                continue
            }
            try await upsert(folder: folder, client: client)
        }

        return try await fetchFolders(client: client)
    }

    private func standardEncryptionKeyData(client: SupabaseClient) async throws -> Data {
        let userID = try await client.auth.session.user.id
        if let cachedStandardEncryptionKeyData, cachedStandardEncryptionKeyUserID == userID {
            return cachedStandardEncryptionKeyData
        }

        if let remoteKey = try await fetchRemoteSyncKey(client: client) {
            let keyData = try remoteKey.validatedKeyData()
            cachedStandardEncryptionKeyData = keyData
            cachedStandardEncryptionKeyUserID = userID
            return keyData
        }

        let keyData = StandardSyncEncryption.generateKeyData()
        let payload = RemoteSyncKeyPayload(userID: userID, keyData: keyData)

        do {
            try await client
                .from("sync_keys")
                .insert(payload)
                .execute()
            cachedStandardEncryptionKeyData = keyData
            cachedStandardEncryptionKeyUserID = userID
            return keyData
        } catch {
            // Another device may have created the recoverable key at the same time.
            if let remoteKey = try await fetchRemoteSyncKey(client: client) {
                let keyData = try remoteKey.validatedKeyData()
                cachedStandardEncryptionKeyData = keyData
                cachedStandardEncryptionKeyUserID = userID
                return keyData
            }
            throw error
        }
    }

    private func fetchRemoteSyncKey(client: SupabaseClient) async throws -> RemoteSyncKey? {
        let response: PostgrestResponse<[RemoteSyncKey]> = try await client
            .from("sync_keys")
            .select(Self.syncKeyColumns)
            .limit(1)
            .execute()

        return response.value.first
    }

    private func migrateLocalNotesIfNeeded(remoteNotes: [Note], client: SupabaseClient) async throws -> [Note] {
        let localNotes = SharedStore.shared.listNotes()
        let localOnlyIDs = Set(localNotes.filter { !$0.isCloudSyncEnabled }.map(\.id))
        for remoteNote in remoteNotes where localOnlyIDs.contains(remoteNote.id) {
            try await deleteRemoteNoteIfPresent(id: remoteNote.id, client: client)
        }

        let remoteNotesForPlanning = remoteNotes.filter { !localOnlyIDs.contains($0.id) }
        let plan = NoteSyncResolver.plan(localNotes: localNotes, remoteNotes: remoteNotesForPlanning)
        for note in plan.notesToUpload {
            try await upsert(note: note, client: client)
        }

        let syncedNotes = try await fetchNotes(client: client)
        let dedupedNotes = try await removeDuplicateConflictCopies(from: syncedNotes, client: client)
        let syncedVisibleNotes = dedupedNotes.filter { !localOnlyIDs.contains($0.id) }
        let mergedNotes = sortNotes(syncedVisibleNotes + plan.localNotesToKeep)
        SharedStore.shared.replaceNotesCache(mergedNotes)
        return mergedNotes
    }

    private func encryptLegacyRemoteNotesIfNeeded(
        remoteRows: [RemoteNote],
        remoteNotes: [Note],
        client: SupabaseClient
    ) async throws {
        let notesByID = Dictionary(uniqueKeysWithValues: remoteNotes.map { ($0.id, $0) })
        for remoteRow in remoteRows where remoteRow.needsEncryptionMigration {
            guard let note = notesByID[remoteRow.id] else { continue }
            try await upsert(note: note, client: client)
        }
    }

    private func encryptLegacyHistoryEntriesIfNeeded(
        remoteRows: [RemoteHistoryEntry],
        entries: [NoteHistoryEntry],
        client: SupabaseClient
    ) async throws {
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for remoteRow in remoteRows where remoteRow.needsEncryptionMigration {
            guard let entry = entriesByID[remoteRow.id] else { continue }
            let keyData = try await standardEncryptionKeyData(client: client)
            let payload = try RemoteHistoryPayload(entry: entry, keyData: keyData)
            try await client
                .from("note_history")
                .upsert(payload, onConflict: "id")
                .execute()
        }
    }

    private func upsertLastWriterWins(note: Note, client: SupabaseClient) async throws {
        let remote = try await fetchRemoteNote(id: note.id, client: client)
        if let remote {
            try await preserveRemoteVersionIfNeeded(remote, beforeUploading: note, client: client)
        }
        try await upsert(note: note, client: client)
    }

    private func preserveRemoteVersionIfNeeded(
        _ remote: Note,
        beforeUploading note: Note,
        client: SupabaseClient
    ) async throws {
        guard remote.id == note.id else { return }
        guard NoteSyncResolver.fingerprint(remote) != NoteSyncResolver.fingerprint(note) else { return }

        let contentHash = hashData(remote.rtfData)
        if SharedStore.shared.listHistory(for: remote.id).contains(where: { $0.contentHash == contentHash }) {
            return
        }

        if try await fetchLatestHistoryEntry(noteID: remote.id, client: client)?.contentHash == contentHash {
            return
        }

        let entry = NoteHistoryEntry(
            id: UUID(),
            noteID: remote.id,
            rtfData: remote.rtfData,
            plainText: remote.plainText,
            createdAt: remote.updatedAt,
            contentHash: contentHash
        )
        SharedStore.shared.cacheHistoryEntry(entry)
        try await insertHistory(entry: entry, client: client)
    }

    private func fetchRemoteNote(id: UUID, client: SupabaseClient) async throws -> Note? {
        let response: PostgrestResponse<[RemoteNote]> = try await client
            .from("notes")
            .select(Self.noteColumns)
            .eq("id", value: id)
            .limit(1)
            .execute()

        let keyData = try await standardEncryptionKeyData(client: client)
        return try response.value.first?.note(keyData: keyData)
    }

    private func deleteRemoteNoteIfPresent(id: UUID, client: SupabaseClient) async throws {
        try await client
            .from("notes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    private func removeDuplicateConflictCopies(from notes: [Note], client: SupabaseClient) async throws -> [Note] {
        let duplicateIDs = NoteSyncResolver.duplicateConflictCopyIDs(in: notes)
        guard !duplicateIDs.isEmpty else {
            return notes
        }

        for id in duplicateIDs {
            try await client
                .from("notes")
                .delete()
                .eq("id", value: id)
                .execute()
        }

        return try await fetchNotes(client: client)
    }

    private func historySnapshot(previous: Note?, updated: Note, now: Date) -> NoteHistoryEntry? {
        let latest = SharedStore.shared.listHistory(for: updated.id).first
        let contentHash = hashData(updated.rtfData)

        if let latest, latest.contentHash == contentHash {
            return nil
        }

        let minInterval: TimeInterval = 60 * 10
        let lastDate = latest?.createdAt ?? .distantPast
        let previousLength = latest?.plainText.count ?? previous?.plainText.count ?? 0
        let lengthDelta = abs(updated.plainText.count - previousLength)
        let shouldSnapshot = now.timeIntervalSince(lastDate) >= minInterval || lengthDelta >= 50

        guard shouldSnapshot else {
            return nil
        }

        return NoteHistoryEntry(
            id: UUID(),
            noteID: updated.id,
            rtfData: updated.rtfData,
            plainText: updated.plainText,
            createdAt: now,
            contentHash: contentHash
        )
    }

    private func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func hashString(_ value: String) -> String {
        hashData(Data(value.utf8))
    }

    private func sortNotes(_ notes: [Note]) -> [Note] {
        notes.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

private extension SupabaseNoteStore {
    static let noteColumns = "id,title,rtf_data,plain_text,encrypted_payload,encryption_version,updated_at,folder_id,is_pinned,is_archived,content_hash,is_conflict,conflict_parent_id,conflict_created_at"
    static let folderColumns = "id,name,parent_id,created_at,updated_at"
    static let historyColumns = "id,note_id,rtf_data,plain_text,encrypted_payload,encryption_version,created_at,content_hash"
    static let syncKeyColumns = "user_id,key_data,key_version,created_at,updated_at"

    static var apnsEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}

private struct RemoteNote: Decodable {
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
    let isConflict: Bool?
    let conflictParentID: UUID?
    let conflictCreatedAt: String?

    var needsEncryptionMigration: Bool {
        encryptedPayload?.isEmpty != false || encryptionVersion != StandardSyncEncryption.version
    }

    func note(keyData: Data) throws -> Note {
        let content: StandardSyncEncryption.NoteContent
        if let encryptedPayload, !encryptedPayload.isEmpty {
            content = try StandardSyncEncryption.decryptNoteContent(encryptedPayload, keyData: keyData)
        } else {
            content = StandardSyncEncryption.NoteContent(
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
            updatedAt: SupabaseDate.parse(updatedAt),
            folderID: folderID,
            isPinned: isPinned ?? false,
            isArchived: isArchived ?? false,
            isConflict: isConflict ?? false,
            conflictParentID: conflictParentID,
            conflictCreatedAt: conflictCreatedAt.map(SupabaseDate.parse)
        )
        note.lastSyncedContentHash = contentHash?.isEmpty == false ? contentHash : NoteSyncResolver.fingerprint(note)
        note.lastSyncedAt = note.updatedAt
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
        case isConflict = "is_conflict"
        case conflictParentID = "conflict_parent_id"
        case conflictCreatedAt = "conflict_created_at"
    }
}

private struct RemoteNotePayload: Encodable {
    let id: UUID
    let title: String
    let rtfData: String
    let plainText: String
    let encryptedPayload: String
    let encryptionVersion: Int
    let updatedAt: String
    let folderID: UUID?
    let isPinned: Bool
    let isArchived: Bool
    let contentHash: String
    let isConflict: Bool
    let conflictParentID: UUID?
    let conflictCreatedAt: String?

    init(note: Note, keyData: Data) throws {
        self.id = note.id
        self.title = ""
        self.rtfData = ""
        self.plainText = ""
        self.encryptedPayload = try StandardSyncEncryption.encryptNoteContent(
            StandardSyncEncryption.noteContent(from: note),
            keyData: keyData
        )
        self.encryptionVersion = StandardSyncEncryption.version
        self.updatedAt = SupabaseDate.format(note.updatedAt)
        self.folderID = note.folderID
        self.isPinned = note.isPinned
        self.isArchived = note.isArchived
        self.contentHash = NoteSyncResolver.fingerprint(note)
        self.isConflict = note.isConflict
        self.conflictParentID = note.conflictParentID
        self.conflictCreatedAt = note.conflictCreatedAt.map(SupabaseDate.format)
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
        case isConflict = "is_conflict"
        case conflictParentID = "conflict_parent_id"
        case conflictCreatedAt = "conflict_created_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(rtfData, forKey: .rtfData)
        try container.encode(plainText, forKey: .plainText)
        try container.encode(encryptedPayload, forKey: .encryptedPayload)
        try container.encode(encryptionVersion, forKey: .encryptionVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        if let folderID {
            try container.encode(folderID, forKey: .folderID)
        } else {
            try container.encodeNil(forKey: .folderID)
        }
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(isConflict, forKey: .isConflict)
        if let conflictParentID {
            try container.encode(conflictParentID, forKey: .conflictParentID)
        } else {
            try container.encodeNil(forKey: .conflictParentID)
        }
        if let conflictCreatedAt {
            try container.encode(conflictCreatedAt, forKey: .conflictCreatedAt)
        } else {
            try container.encodeNil(forKey: .conflictCreatedAt)
        }
    }
}

private struct RemoteFolder: Decodable {
    let id: UUID
    let name: String
    let parentID: UUID?
    let createdAt: String
    let updatedAt: String

    var folder: Folder {
        Folder(
            id: id,
            name: name,
            parentID: parentID,
            createdAt: SupabaseDate.parse(createdAt),
            updatedAt: SupabaseDate.parse(updatedAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct RemoteFolderPayload: Encodable {
    let id: UUID
    let name: String
    let parentID: UUID?
    let createdAt: String
    let updatedAt: String

    init(folder: Folder) {
        self.id = folder.id
        self.name = folder.displayName
        self.parentID = folder.parentID
        self.createdAt = SupabaseDate.format(folder.createdAt)
        self.updatedAt = SupabaseDate.format(folder.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct FolderParentUpdatePayload: Encodable {
    let parentID: UUID?

    enum CodingKeys: String, CodingKey {
        case parentID = "parent_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let parentID {
            try container.encode(parentID, forKey: .parentID)
        } else {
            try container.encodeNil(forKey: .parentID)
        }
    }
}

private struct NoteFolderUpdatePayload: Encodable {
    let folderID: UUID?

    enum CodingKeys: String, CodingKey {
        case folderID = "folder_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let folderID {
            try container.encode(folderID, forKey: .folderID)
        } else {
            try container.encodeNil(forKey: .folderID)
        }
    }
}

private struct RemoteSyncKey: Decodable {
    let userID: UUID
    let keyData: String
    let keyVersion: Int

    func validatedKeyData() throws -> Data {
        guard keyVersion == StandardSyncEncryption.version,
              let data = Data(base64Encoded: keyData) else {
            throw StandardSyncEncryptionError.invalidKeyLength
        }
        try StandardSyncEncryption.validateKeyData(data)
        return data
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case keyData = "key_data"
        case keyVersion = "key_version"
    }
}

private struct RemoteSyncKeyPayload: Encodable {
    let userID: UUID
    let keyData: String
    let keyVersion: Int

    init(userID: UUID, keyData: Data) {
        self.userID = userID
        self.keyData = keyData.base64EncodedString()
        self.keyVersion = StandardSyncEncryption.version
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case keyData = "key_data"
        case keyVersion = "key_version"
    }
}

private struct RemoteWidgetRefreshTokenPayload: Encodable {
    let tokenHash: String
    let platform: String
    let updatedAt: String

    init(tokenHash: String) {
        self.tokenHash = tokenHash
        self.platform = "ios"
        self.updatedAt = SupabaseDate.format(Date())
    }

    enum CodingKeys: String, CodingKey {
        case tokenHash = "token_hash"
        case platform
        case updatedAt = "updated_at"
    }
}

private struct RemoteWidgetPushTokenPayload: Encodable {
    let token: String
    let environment: String
    let platform: String
    let updatedAt: String

    init(token: String, environment: String) {
        self.token = token
        self.environment = environment
        self.platform = "ios"
        self.updatedAt = SupabaseDate.format(Date())
    }

    enum CodingKeys: String, CodingKey {
        case token
        case environment
        case platform
        case updatedAt = "updated_at"
    }
}

private struct RemoteHistoryEntry: Decodable {
    let id: UUID
    let noteID: UUID
    let rtfData: String?
    let plainText: String?
    let encryptedPayload: String?
    let encryptionVersion: Int?
    let createdAt: String
    let contentHash: String

    var needsEncryptionMigration: Bool {
        encryptedPayload?.isEmpty != false || encryptionVersion != StandardSyncEncryption.version
    }

    func entry(keyData: Data) throws -> NoteHistoryEntry {
        let content: StandardSyncEncryption.HistoryContent
        if let encryptedPayload, !encryptedPayload.isEmpty {
            content = try StandardSyncEncryption.decryptHistoryContent(encryptedPayload, keyData: keyData)
        } else {
            content = StandardSyncEncryption.HistoryContent(
                rtfDataBase64: rtfData ?? "",
                plainText: plainText ?? ""
            )
        }

        return NoteHistoryEntry(
            id: id,
            noteID: noteID,
            rtfData: Data(base64Encoded: content.rtfDataBase64) ?? Data(),
            plainText: content.plainText,
            createdAt: SupabaseDate.parse(createdAt),
            contentHash: contentHash
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case noteID = "note_id"
        case rtfData = "rtf_data"
        case plainText = "plain_text"
        case encryptedPayload = "encrypted_payload"
        case encryptionVersion = "encryption_version"
        case createdAt = "created_at"
        case contentHash = "content_hash"
    }
}

private struct RemoteHistoryPayload: Encodable {
    let id: UUID
    let noteID: UUID
    let rtfData: String
    let plainText: String
    let encryptedPayload: String
    let encryptionVersion: Int
    let createdAt: String
    let contentHash: String

    init(entry: NoteHistoryEntry, keyData: Data) throws {
        self.id = entry.id
        self.noteID = entry.noteID
        self.rtfData = ""
        self.plainText = ""
        self.encryptedPayload = try StandardSyncEncryption.encryptHistoryContent(
            StandardSyncEncryption.historyContent(from: entry),
            keyData: keyData
        )
        self.encryptionVersion = StandardSyncEncryption.version
        self.createdAt = SupabaseDate.format(entry.createdAt)
        self.contentHash = entry.contentHash
    }

    enum CodingKeys: String, CodingKey {
        case id
        case noteID = "note_id"
        case rtfData = "rtf_data"
        case plainText = "plain_text"
        case encryptedPayload = "encrypted_payload"
        case encryptionVersion = "encryption_version"
        case createdAt = "created_at"
        case contentHash = "content_hash"
    }
}

private enum SupabaseDate {
    nonisolated static func format(_ date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    nonisolated static func parse(_ value: String) -> Date {
        fractionalFormatter().date(from: value)
            ?? wholeSecondFormatter().date(from: value)
            ?? Date()
    }

    private nonisolated static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private nonisolated static func wholeSecondFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
