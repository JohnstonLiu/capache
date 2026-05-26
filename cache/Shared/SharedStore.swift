import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import CryptoKit

final class SharedStore {
    struct WidgetBackgroundRefreshCredentials {
        let supabaseURL: URL
        let refreshToken: String
        let syncKeyData: Data
    }

    static let shared = SharedStore()
    static let didChangeNotification = Notification.Name("SharedStoreDidChange")

    static let appGroupID = "group.me.johnstonliu.cache"

    private let queue: DispatchQueue
    private let notesKey = "notes"
    private let foldersKey = "folders"
    private let historyKey = "noteHistory"
    private let notesBackupKey = "notes.backup"
    private let foldersBackupKey = "folders.backup"
    private let historyBackupKey = "noteHistory.backup"
    private let legacyMigrationKey = "legacyStandardDefaultsMigratedToAppGroup.v1"
    private let widgetPushTokensKey = "widgetPushTokens.v1"
    private let widgetRefreshTokenKey = "widgetRefreshToken.v1"
    private let widgetRefreshSupabaseURLKey = "widgetRefreshSupabaseURL.v1"
    private let widgetRefreshSyncKeyDataKey = "widgetRefreshSyncKeyData.v1"
    private let storeDirectoryName = "SharedStore"
    private let notesFileName = "notes.json"
    private let foldersFileName = "folders.json"
    private let historyFileName = "noteHistory.json"
    private var reloadWorkItem: DispatchWorkItem?
    private var historyReloadWorkItem: DispatchWorkItem?

    private let defaults: UserDefaults?
    private let storageDirectoryOverride: URL?
    private let fallbackStorageDirectoryOverride: URL?
    private let appContainerLibraryOverride: URL?
    private let shouldReloadWidgets: Bool

    convenience init() {
        self.init(
            defaults: UserDefaults(suiteName: Self.appGroupID),
            shouldMigrate: true,
            shouldReloadWidgets: true
        )
    }

    init(
        defaults: UserDefaults?,
        storageDirectoryURL: URL? = nil,
        fallbackStorageDirectoryURL: URL? = nil,
        appContainerLibraryURL: URL? = nil,
        shouldMigrate: Bool = false,
        shouldReloadWidgets: Bool = false
    ) {
        self.queue = DispatchQueue(label: "SharedStore.queue.\(UUID().uuidString)")
        self.defaults = defaults
        self.storageDirectoryOverride = storageDirectoryURL
        self.fallbackStorageDirectoryOverride = fallbackStorageDirectoryURL
        self.appContainerLibraryOverride = appContainerLibraryURL
        self.shouldReloadWidgets = shouldReloadWidgets

        if shouldMigrate {
            migrateLegacyStandardDefaultsIfNeeded()
        }
    }

    func listNotes() -> [Note] {
        queue.sync {
            sortNotes(loadNotes())
        }
    }

    func listFolders() -> [Folder] {
        queue.sync {
            sortFolders(loadFolders())
        }
    }

    func getFolder(id: UUID) -> Folder? {
        queue.sync {
            loadFolders().first { $0.id == id }
        }
    }

    func getNote(id: UUID) -> Note? {
        queue.sync {
            loadNotes().first { $0.id == id }
        }
    }

    func createNote(
        attributedText: NSAttributedString = NSAttributedString(string: ""),
        title: String = "",
        folderID: UUID? = nil,
        isPinned: Bool = false
    ) -> UUID {
        queue.sync {
            var notes = loadNotes()
            let now = Date()
            let note = Note(
                id: UUID(),
                title: title,
                attributedText: attributedText,
                updatedAt: now,
                folderID: folderID,
                isPinned: isPinned
            )
            notes.append(note)
            saveNotes(notes)
            return note.id
        }
    }

    func updateNote(id: UUID, attributedText: NSAttributedString) {
        queue.sync {
            var notes = loadNotes()
            if let index = notes.firstIndex(where: { $0.id == id }) {
                let previous = notes[index]
                let now = Date()
                notes[index].rtfData = RichTextCodec.rtfData(from: attributedText)
                notes[index].plainText = attributedText.string
                notes[index].updatedAt = now
                saveNotes(notes)
                maybeSaveHistory(previous: previous, updated: notes[index], now: now)
            }
        }
    }

    func updateNoteTitle(id: UUID, title: String) {
        queue.sync {
            var notes = loadNotes()
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].title = title
            notes[index].updatedAt = Date()
            saveNotes(notes)
        }
    }

    func moveNote(id: UUID, folderID: UUID?) {
        queue.sync {
            var notes = loadNotes()
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].folderID = folderID
            notes[index].updatedAt = Date()
            saveNotes(notes)
        }
    }

    func setNotePinned(id: UUID, isPinned: Bool) {
        queue.sync {
            var notes = loadNotes()
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].isPinned = isPinned
            notes[index].updatedAt = Date()
            saveNotes(notes)
        }
    }

    func setNoteArchived(id: UUID, isArchived: Bool) {
        queue.sync {
            var notes = loadNotes()
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].isArchived = isArchived
            notes[index].updatedAt = Date()
            saveNotes(notes)
        }
    }

    func markConflictResolved(id: UUID) {
        queue.sync {
            var notes = loadNotes()
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].isConflict = false
            notes[index].conflictParentID = nil
            notes[index].conflictCreatedAt = nil
            notes[index].updatedAt = Date()
            saveNotes(notes)
        }
    }

    func setNoteCloudSyncEnabled(id: UUID, isEnabled: Bool) {
        queue.sync {
            var notes = loadNotes()
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].isCloudSyncEnabled = isEnabled
            notes[index].updatedAt = Date()
            if !isEnabled {
                notes[index].lastSyncedContentHash = nil
                notes[index].lastSyncedAt = nil
            }
            saveNotes(notes)
        }
    }

    func setAllNotesCloudSyncEnabled(_ isEnabled: Bool) {
        queue.sync {
            var notes = loadNotes()
            for index in notes.indices {
                notes[index].isCloudSyncEnabled = isEnabled
                if !isEnabled {
                    notes[index].lastSyncedContentHash = nil
                    notes[index].lastSyncedAt = nil
                }
            }
            saveNotes(notes)
        }
    }

    func deleteNote(id: UUID) {
        queue.sync {
            var notes = loadNotes()
            notes.removeAll { $0.id == id }
            saveNotes(notes)
            deleteHistory(for: id)
        }
    }

    func createFolder(name: String, parentID: UUID? = nil) -> Folder {
        queue.sync {
            let now = Date()
            let folder = Folder(name: name, parentID: parentID, createdAt: now, updatedAt: now)
            var folders = loadFolders()
            folders.append(folder)
            saveFolders(folders)
            return folder
        }
    }

    func renameFolder(id: UUID, name: String) {
        queue.sync {
            var folders = loadFolders()
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            folders[index].name = name
            folders[index].updatedAt = Date()
            saveFolders(folders)
        }
    }

    func deleteFolder(id: UUID) {
        queue.sync {
            var folders = loadFolders()
            let parentID = folders.first { $0.id == id }?.parentID
            folders.removeAll { $0.id == id }
            for index in folders.indices where folders[index].parentID == id {
                folders[index].parentID = parentID
                folders[index].updatedAt = Date()
            }
            saveFolders(folders)

            var notes = loadNotes()
            for index in notes.indices where notes[index].folderID == id {
                notes[index].folderID = parentID
                notes[index].updatedAt = Date()
            }
            saveNotes(notes)
        }
    }

    func replaceNotesCache(_ notes: [Note]) {
        queue.sync {
            saveNotes(notes)
        }
    }

    func cacheNote(_ note: Note) {
        queue.sync {
            var notes = loadNotes()
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            } else {
                notes.append(note)
            }
            saveNotes(notes)
        }
    }

    func replaceFoldersCache(_ folders: [Folder]) {
        queue.sync {
            saveFolders(folders)
        }
    }

    func cacheFolder(_ folder: Folder) {
        queue.sync {
            var folders = loadFolders()
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index] = folder
            } else {
                folders.append(folder)
            }
            saveFolders(folders)
        }
    }

    func replaceHistoryCache(_ entries: [NoteHistoryEntry], for noteID: UUID) {
        queue.sync {
            var history = loadHistory().filter { $0.noteID != noteID }
            history.append(contentsOf: entries)
            saveHistory(pruneHistory(history, for: noteID))
        }
    }

    func cacheHistoryEntry(_ entry: NoteHistoryEntry) {
        queue.sync {
            var history = loadHistory()
            history.removeAll { $0.id == entry.id }
            history.append(entry)
            saveHistory(pruneHistory(history, for: entry.noteID))
        }
    }

    func clearCache() {
        queue.sync {
            backupCurrentNotesIfNeeded()
            backupCurrentFoldersIfNeeded()
            backupCurrentHistoryIfNeeded()
            removeStorageFile(named: notesFileName)
            removeStorageFile(named: foldersFileName)
            removeStorageFile(named: historyFileName)
            defaults?.removeObject(forKey: notesKey)
            defaults?.removeObject(forKey: foldersKey)
            defaults?.removeObject(forKey: historyKey)
            reloadWidgetsDebounced()
        }
    }

    func listHistory(for noteID: UUID) -> [NoteHistoryEntry] {
        queue.sync {
            loadHistory().filter { $0.noteID == noteID }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func listAllHistory() -> [NoteHistoryEntry] {
        queue.sync {
            loadHistory().sorted { $0.createdAt > $1.createdAt }
        }
    }

    func reloadWidgets() {
        reloadWidgetsDebounced()
    }

    func recordWidgetPushToken(_ tokenData: Data) {
        recordWidgetPushToken(Self.hexString(from: tokenData))
    }

    func recordWidgetPushToken(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return }

        queue.sync {
            var tokens = defaults?.stringArray(forKey: widgetPushTokensKey) ?? []
            tokens.removeAll { $0 == cleaned }
            tokens.append(cleaned)
            defaults?.set(tokens, forKey: widgetPushTokensKey)
        }
    }

    func widgetPushTokens() -> [String] {
        queue.sync {
            defaults?.stringArray(forKey: widgetPushTokensKey) ?? []
        }
    }

    func currentOrCreateWidgetRefreshToken() -> String {
        queue.sync {
            if let existing = defaults?.string(forKey: widgetRefreshTokenKey),
               !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return existing
            }

            let token = Self.randomBase64URLToken()
            defaults?.set(token, forKey: widgetRefreshTokenKey)
            return token
        }
    }

    func saveWidgetBackgroundRefreshCredentials(
        supabaseURLString: String,
        refreshToken: String,
        syncKeyData: Data
    ) {
        let trimmedURL = supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedToken.isEmpty, !syncKeyData.isEmpty else { return }

        queue.sync {
            defaults?.set(trimmedURL, forKey: widgetRefreshSupabaseURLKey)
            defaults?.set(trimmedToken, forKey: widgetRefreshTokenKey)
            defaults?.set(syncKeyData, forKey: widgetRefreshSyncKeyDataKey)
        }
    }

    func widgetBackgroundRefreshCredentials() -> WidgetBackgroundRefreshCredentials? {
        queue.sync {
            guard let urlString = defaults?.string(forKey: widgetRefreshSupabaseURLKey),
                  let url = URL(string: urlString),
                  let refreshToken = defaults?.string(forKey: widgetRefreshTokenKey),
                  let syncKeyData = defaults?.data(forKey: widgetRefreshSyncKeyDataKey),
                  !refreshToken.isEmpty,
                  !syncKeyData.isEmpty else {
                return nil
            }

            return WidgetBackgroundRefreshCredentials(
                supabaseURL: url,
                refreshToken: refreshToken,
                syncKeyData: syncKeyData
            )
        }
    }

    func clearWidgetBackgroundRefreshCredentials() {
        queue.sync {
            defaults?.removeObject(forKey: widgetPushTokensKey)
            defaults?.removeObject(forKey: widgetRefreshTokenKey)
            defaults?.removeObject(forKey: widgetRefreshSupabaseURLKey)
            defaults?.removeObject(forKey: widgetRefreshSyncKeyDataKey)
        }
    }

    func deleteHistoryEntry(id: UUID) {
        queue.sync {
            var history = loadHistory()
            history.removeAll { $0.id == id }
            saveHistory(history)
        }
    }

    func clearHistory(for noteID: UUID) {
        queue.sync {
            var history = loadHistory()
            history.removeAll { $0.noteID == noteID }
            saveHistory(history)
        }
    }

    private func loadNotes() -> [Note] {
        loadArray(forKey: notesKey, backupKey: notesBackupKey, fileName: notesFileName, as: Note.self)
    }

    private func loadFolders() -> [Folder] {
        loadArray(forKey: foldersKey, backupKey: foldersBackupKey, fileName: foldersFileName, as: Folder.self)
    }

    private func saveNotes(_ notes: [Note]) {
        do {
            backupCurrentNotesIfNeeded()
            let data = try JSONEncoder().encode(notes)
            writeStorageData(data, fileName: notesFileName)
            defaults?.set(data, forKey: notesKey)
            reloadWidgetsDebounced()
            notifyDidChange()
        } catch {
            // No-op: keep storage resilient to encoding errors.
        }
    }

    private func saveFolders(_ folders: [Folder]) {
        do {
            backupCurrentFoldersIfNeeded()
            let data = try JSONEncoder().encode(folders)
            writeStorageData(data, fileName: foldersFileName)
            defaults?.set(data, forKey: foldersKey)
            reloadWidgetsDebounced()
            notifyDidChange()
        } catch {
            // No-op: keep storage resilient to encoding errors.
        }
    }

    private func loadHistory() -> [NoteHistoryEntry] {
        loadArray(forKey: historyKey, backupKey: historyBackupKey, fileName: historyFileName, as: NoteHistoryEntry.self)
    }

    private func saveHistory(_ history: [NoteHistoryEntry]) {
        do {
            backupCurrentHistoryIfNeeded()
            let data = try JSONEncoder().encode(history)
            writeStorageData(data, fileName: historyFileName)
            defaults?.set(data, forKey: historyKey)
        } catch {
            // No-op: keep storage resilient to encoding errors.
        }
    }

    private func loadArray<Element: Decodable>(
        forKey key: String,
        backupKey: String,
        fileName: String,
        as elementType: Element.Type
    ) -> [Element] {
        let fileData = readStorageData(fileName: fileName)
        let fileValues = decodeArray(elementType, from: fileData)
        let defaultsData = defaults?.data(forKey: key)
        let defaultsValues = decodeArray(elementType, from: defaultsData)

        if let fileValues, let defaultsData, let defaultsValues, fileValues.isEmpty, !defaultsValues.isEmpty {
            writeStorageData(defaultsData, fileName: fileName)
            defaults?.set(defaultsData, forKey: backupKey)
            return defaultsValues
        }

        if let fileData {
            if let fileValues {
                defaults?.set(fileData, forKey: key)
                return fileValues
            }
            preserveUnreadableData(fileData, key: "\(key).file")
        }

        if let defaultsData, let defaultsValues {
            writeStorageData(defaultsData, fileName: fileName)
            defaults?.set(defaultsData, forKey: backupKey)
            return defaultsValues
        }

        if let defaultsData {
            preserveUnreadableData(defaultsData, key: key)
        }

        guard let backupData = defaults?.data(forKey: backupKey),
              let backupValues = decodeArray(elementType, from: backupData) else {
            return []
        }
        writeStorageData(backupData, fileName: fileName)
        defaults?.set(backupData, forKey: key)
        return backupValues
    }

    private func decodeArray<Element: Decodable>(_ elementType: Element.Type, from data: Data?) -> [Element]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([Element].self, from: data)
    }

    private func migrateLegacyStandardDefaultsIfNeeded() {
        guard let sharedDefaults = defaults,
              !Bundle.main.bundlePath.hasSuffix(".appex"),
              !sharedDefaults.bool(forKey: legacyMigrationKey) else {
            return
        }

        migrateLegacyArray(
            key: notesKey,
            backupKey: notesBackupKey,
            fileName: notesFileName,
            as: Note.self,
            from: .standard,
            to: sharedDefaults
        )
        migrateLegacyArray(
            key: foldersKey,
            backupKey: foldersBackupKey,
            fileName: foldersFileName,
            as: Folder.self,
            from: .standard,
            to: sharedDefaults
        )
        migrateLegacyArray(
            key: historyKey,
            backupKey: historyBackupKey,
            fileName: historyFileName,
            as: NoteHistoryEntry.self,
            from: .standard,
            to: sharedDefaults
        )
        migrateFallbackStorageArrayIfNeeded(
            key: notesKey,
            backupKey: notesBackupKey,
            fileName: notesFileName,
            as: Note.self,
            to: sharedDefaults
        )
        migrateFallbackStorageArrayIfNeeded(
            key: foldersKey,
            backupKey: foldersBackupKey,
            fileName: foldersFileName,
            as: Folder.self,
            to: sharedDefaults
        )
        migrateFallbackStorageArrayIfNeeded(
            key: historyKey,
            backupKey: historyBackupKey,
            fileName: historyFileName,
            as: NoteHistoryEntry.self,
            to: sharedDefaults
        )

        sharedDefaults.set(true, forKey: legacyMigrationKey)
    }

    private func migrateLegacyArray<Element: Decodable>(
        key: String,
        backupKey: String,
        fileName: String,
        as elementType: Element.Type,
        from legacyDefaults: UserDefaults,
        to sharedDefaults: UserDefaults
    ) {
        guard let legacyData = legacyDefaults.data(forKey: key),
              let legacyValues = decodeArray(elementType, from: legacyData),
              !legacyValues.isEmpty else {
            return
        }

        let fileValues = decodeArray(elementType, from: readStorageData(fileName: fileName)) ?? []
        let sharedValues = decodeArray(elementType, from: sharedDefaults.data(forKey: key)) ?? []
        if fileValues.isEmpty && sharedValues.isEmpty {
            writeStorageData(legacyData, fileName: fileName)
            sharedDefaults.set(legacyData, forKey: key)
            sharedDefaults.set(legacyData, forKey: backupKey)
        } else {
            sharedDefaults.set(legacyData, forKey: "\(key).legacyBackup")
        }
    }

    private func migrateFallbackStorageArrayIfNeeded<Element: Decodable>(
        key: String,
        backupKey: String,
        fileName: String,
        as elementType: Element.Type,
        to sharedDefaults: UserDefaults
    ) {
        let fallbackData = fallbackStorageData(forKey: key, fileName: fileName, as: elementType)
        guard let fallbackData,
              let fallbackValues = decodeArray(elementType, from: fallbackData),
              !fallbackValues.isEmpty else {
            return
        }

        let fileValues = decodeArray(elementType, from: readStorageData(fileName: fileName)) ?? []
        let sharedValues = decodeArray(elementType, from: sharedDefaults.data(forKey: key)) ?? []
        if fileValues.isEmpty && sharedValues.isEmpty {
            writeStorageData(fallbackData, fileName: fileName)
            sharedDefaults.set(fallbackData, forKey: key)
            sharedDefaults.set(fallbackData, forKey: backupKey)
        } else {
            sharedDefaults.set(fallbackData, forKey: "\(key).fallbackBackup")
        }
    }

    private func backupCurrentNotesIfNeeded() {
        backupCurrentArray(forKey: notesKey, backupKey: notesBackupKey, fileName: notesFileName, as: Note.self)
    }

    private func backupCurrentFoldersIfNeeded() {
        backupCurrentArray(forKey: foldersKey, backupKey: foldersBackupKey, fileName: foldersFileName, as: Folder.self)
    }

    private func backupCurrentHistoryIfNeeded() {
        backupCurrentArray(forKey: historyKey, backupKey: historyBackupKey, fileName: historyFileName, as: NoteHistoryEntry.self)
    }

    private func backupCurrentArray<Element: Decodable>(
        forKey key: String,
        backupKey: String,
        fileName: String,
        as elementType: Element.Type
    ) {
        guard let data = primaryStorageData(forKey: key, fileName: fileName),
              let values = decodeArray(elementType, from: data),
              !values.isEmpty else {
            return
        }
        defaults?.set(data, forKey: backupKey)
        writeStorageData(data, fileName: backupFileName(for: fileName))
    }

    private func preserveUnreadableData(_ data: Data, key: String) {
        defaults?.set(data, forKey: "\(key).unreadableBackup")
    }

    private func primaryStorageData(forKey key: String, fileName: String) -> Data? {
        readStorageData(fileName: fileName) ?? defaults?.data(forKey: key)
    }

    private func fallbackStorageData<Element: Decodable>(
        forKey key: String,
        fileName: String,
        as elementType: Element.Type
    ) -> Data? {
        if let fileURL = fallbackStorageDirectoryURL()?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: fileURL),
           let values = decodeArray(elementType, from: data),
           !values.isEmpty {
            return data
        }

        if let data = fallbackSuiteDefaultsData(forKey: key),
           let values = decodeArray(elementType, from: data),
           !values.isEmpty {
            return data
        }

        return nil
    }

    private func fallbackSuiteDefaultsData(forKey key: String) -> Data? {
        guard let preferencesURL = appContainerLibraryURL()?
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(Self.appGroupID).plist", isDirectory: false),
            let plistData = try? Data(contentsOf: preferencesURL),
            let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist[key] as? Data
    }

    private func backupFileName(for fileName: String) -> String {
        fileName.replacingOccurrences(of: ".json", with: ".backup.json")
    }

    private func readStorageData(fileName: String) -> Data? {
        guard let fileURL = storageFileURL(named: fileName) else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }

    private func writeStorageData(_ data: Data, fileName: String) {
        guard let fileURL = storageFileURL(named: fileName) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // UserDefaults remains as a compatibility cache if file persistence fails.
        }
    }

    private func removeStorageFile(named fileName: String) {
        guard let fileURL = storageFileURL(named: fileName) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func storageFileURL(named fileName: String) -> URL? {
        storageDirectoryURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    private func storageDirectoryURL() -> URL? {
        if let storageDirectoryOverride {
            return storageDirectoryOverride
        }

        let fileManager = FileManager.default
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return groupURL.appendingPathComponent(storeDirectoryName, isDirectory: true)
        }

        return fallbackStorageDirectoryURL()
    }

    private func fallbackStorageDirectoryURL() -> URL? {
        if let fallbackStorageDirectoryOverride {
            return fallbackStorageDirectoryOverride
        }

        return appContainerApplicationSupportURL()?
            .appendingPathComponent("Capache", isDirectory: true)
            .appendingPathComponent(storeDirectoryName, isDirectory: true)
    }

    private func appContainerApplicationSupportURL() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private func appContainerLibraryURL() -> URL? {
        if let appContainerLibraryOverride {
            return appContainerLibraryOverride
        }

        return try? FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    private func maybeSaveHistory(previous: Note, updated: Note, now: Date) {
        let history = loadHistory().filter { $0.noteID == updated.id }
        let latest = history.max(by: { $0.createdAt < $1.createdAt })

        let contentHash = hashData(updated.rtfData)
        if let latest, latest.contentHash == contentHash {
            return
        }

        let minInterval: TimeInterval = 60 * 10
        let lastDate = latest?.createdAt ?? .distantPast
        let lengthDelta = abs(updated.plainText.count - (latest?.plainText.count ?? 0))
        let shouldSnapshot = now.timeIntervalSince(lastDate) >= minInterval || lengthDelta >= 50
        if !shouldSnapshot {
            return
        }

        var allHistory = loadHistory()
        let entry = NoteHistoryEntry(
            id: UUID(),
            noteID: updated.id,
            rtfData: updated.rtfData,
            plainText: updated.plainText,
            createdAt: now,
            contentHash: contentHash
        )
        allHistory.append(entry)

        let pruned = pruneHistory(allHistory, for: updated.id)
        saveHistory(pruned)
    }

    private func pruneHistory(_ history: [NoteHistoryEntry], for noteID: UUID) -> [NoteHistoryEntry] {
        let limit = 20
        let other = history.filter { $0.noteID != noteID }
        let mine = history.filter { $0.noteID == noteID }.sorted { $0.createdAt > $1.createdAt }
        let kept = Array(mine.prefix(limit))
        return other + kept
    }

    private func deleteHistory(for noteID: UUID) {
        var history = loadHistory()
        history.removeAll { $0.noteID == noteID }
        saveHistory(history)
    }

    private func sortNotes(_ notes: [Note]) -> [Note] {
        notes.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func sortFolders(_ folders: [Folder]) -> [Folder] {
        folders.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomBase64URLToken() -> String {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func reloadWidgetsDebounced() {
        guard shouldReloadWidgets else {
            return
        }

        #if canImport(WidgetKit)
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
        #endif
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
