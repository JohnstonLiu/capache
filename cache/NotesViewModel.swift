import Combine
import Foundation

enum NoteListScope: Hashable {
    case root
    case all
    case pinned
    case archived
    case folder(UUID)

    var folderID: UUID? {
        if case let .folder(id) = self {
            return id
        }
        return nil
    }
}

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var folders: [Folder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var lastSyncCompletedAt: Date?

    private let store = SupabaseNoteStore.shared
    private var cancellables: Set<AnyCancellable> = []

    var hasPendingCloudChanges: Bool {
        notes.contains { note in
            guard note.isCloudSyncEnabled else { return false }
            guard let lastSyncedContentHash = note.lastSyncedContentHash else { return true }
            return NoteSyncResolver.fingerprint(note) != lastSyncedContentHash
        }
    }

    init(notificationCenter: NotificationCenter = .default) {
        notificationCenter.publisher(for: SharedStore.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadLocalCache()
                }
            }
            .store(in: &cancellables)
    }

    func reload(syncEnabled: Bool) async {
        isLoading = true
        defer { isLoading = false }

        guard syncEnabled else {
            errorMessage = nil
            loadLocalCache()
            return
        }

        do {
            errorMessage = nil
            notes = try await store.listNotes()
            folders = try await store.listFolders()
            try? await store.prepareWidgetBackgroundRefresh()
            lastSyncCompletedAt = Date()
            SharedStore.shared.reloadWidgets()
        } catch {
            loadLocalCache()
            handleSyncError(error)
        }
    }

    private func loadLocalCache() {
        notes = SharedStore.shared.listNotes()
        folders = SharedStore.shared.listFolders()
    }

    func visibleNotes(for scope: NoteListScope, searchText: String) -> [Note] {
        Self.visibleNotes(notes, folders: folders, for: scope, searchText: searchText)
    }

    static func visibleNotes(
        _ notes: [Note],
        folders: [Folder],
        for scope: NoteListScope,
        searchText: String
    ) -> [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            switch scope {
            case .root:
                guard note.folderID == nil, !note.isArchived else { return false }
            case .all:
                guard !note.isArchived else { return false }
            case .pinned:
                guard note.isPinned, !note.isArchived else { return false }
            case .archived:
                guard note.isArchived else { return false }
            case let .folder(folderID):
                guard note.folderID == folderID, !note.isArchived else { return false }
            }

            guard !query.isEmpty else { return true }
            if note.searchableText.localizedCaseInsensitiveContains(query) {
                return true
            }
            if let folderID = note.folderID,
               folderName(for: folderID, in: folders).localizedCaseInsensitiveContains(query) {
                return true
            }
            return false
        }
    }

    func folderName(for id: UUID?) -> String {
        guard let id else { return "No Folder" }
        return folders.first { $0.id == id }?.displayName ?? "Missing Folder"
    }

    func title(for scope: NoteListScope) -> String {
        switch scope {
        case .root:
            return "Notes"
        case .all:
            return "All Notes"
        case .pinned:
            return "Pinned"
        case .archived:
            return "Archive"
        case let .folder(id):
            return folderName(for: id)
        }
    }

    private static func folderName(for id: UUID, in folders: [Folder]) -> String {
        folders.first { $0.id == id }?.displayName ?? "Missing Folder"
    }

    func createNote(in scope: NoteListScope, syncEnabled: Bool) async -> UUID? {
        do {
            errorMessage = nil
            let id: UUID
            if syncEnabled {
                id = try await store.createNote(folderID: scope.folderID, isPinned: scope == .pinned)
            } else {
                id = SharedStore.shared.createNote(folderID: scope.folderID, isPinned: scope == .pinned)
            }
            await reload(syncEnabled: syncEnabled)
            return id
        } catch {
            handleSyncError(error)
            return nil
        }
    }

    func deleteNotes(_ notesToDelete: [Note], syncEnabled: Bool) async {
        for note in notesToDelete {
            do {
                if syncEnabled {
                    try await store.deleteNote(id: note.id)
                } else {
                    SharedStore.shared.deleteNote(id: note.id)
                }
            } catch {
                handleSyncError(error)
            }
        }
        await reload(syncEnabled: syncEnabled)
    }

    func togglePinned(_ note: Note, syncEnabled: Bool) async {
        do {
            errorMessage = nil
            if syncEnabled {
                try await store.setNotePinned(id: note.id, isPinned: !note.isPinned)
            } else {
                SharedStore.shared.setNotePinned(id: note.id, isPinned: !note.isPinned)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    func setArchived(_ note: Note, isArchived: Bool, syncEnabled: Bool) async {
        do {
            errorMessage = nil
            if syncEnabled {
                try await store.setNoteArchived(id: note.id, isArchived: isArchived)
            } else {
                SharedStore.shared.setNoteArchived(id: note.id, isArchived: isArchived)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    func markConflictResolved(_ note: Note, syncEnabled: Bool) async {
        do {
            errorMessage = nil
            if syncEnabled {
                try await store.markConflictResolved(id: note.id)
            } else {
                SharedStore.shared.markConflictResolved(id: note.id)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    func setCloudSyncEnabled(_ note: Note, isEnabled: Bool, syncEnabled: Bool) async {
        do {
            errorMessage = nil
            if syncEnabled {
                try await store.setNoteCloudSyncEnabled(id: note.id, isEnabled: isEnabled)
            } else {
                SharedStore.shared.setNoteCloudSyncEnabled(id: note.id, isEnabled: isEnabled)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    func move(_ note: Note, to folderID: UUID?, syncEnabled: Bool) async {
        do {
            errorMessage = nil
            if syncEnabled {
                try await store.moveNote(id: note.id, folderID: folderID)
            } else {
                SharedStore.shared.moveNote(id: note.id, folderID: folderID)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    func createFolder(name: String, parentID: UUID? = nil, syncEnabled: Bool) async -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            errorMessage = nil
            let folder: Folder
            if syncEnabled {
                folder = try await store.createFolder(name: trimmed, parentID: parentID)
            } else {
                folder = SharedStore.shared.createFolder(name: trimmed, parentID: parentID)
            }
            await reload(syncEnabled: syncEnabled)
            return folder
        } catch {
            handleSyncError(error)
            return nil
        }
    }

    func renameFolder(_ folder: Folder, name: String, syncEnabled: Bool) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            errorMessage = nil
            if syncEnabled {
                try await store.renameFolder(id: folder.id, name: trimmed)
            } else {
                SharedStore.shared.renameFolder(id: folder.id, name: trimmed)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    func deleteFolder(_ folder: Folder, syncEnabled: Bool) async {
        do {
            errorMessage = nil
            if syncEnabled {
                try await store.deleteFolder(id: folder.id)
            } else {
                SharedStore.shared.deleteFolder(id: folder.id)
            }
            await reload(syncEnabled: syncEnabled)
        } catch {
            handleSyncError(error)
        }
    }

    private func handleSyncError(_ error: Error) {
        guard !SupabaseSessionInvalidation.isBenignCancellation(error) else { return }

        if SupabaseSessionInvalidation.postIfNeeded(for: error) {
            errorMessage = "Your sync account is no longer available. Sign in again to resume syncing."
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
