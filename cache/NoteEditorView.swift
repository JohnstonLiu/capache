import SwiftUI

struct NoteEditorView: View {
    let noteID: UUID

    @StateObject private var presence = NotePresenceService()
    @State private var title = ""
    @State private var attributedText = NSAttributedString(string: "")
    @State private var command: RichTextCommand?
    @State private var debounceWorkItem: DispatchWorkItem?
    @State private var titleDebounceWorkItem: DispatchWorkItem?
    @State private var isFocused = false
    @State private var showHistory = false
    @State private var showDeleteConfirm = false
    @State private var refreshToken = UUID()
    @State private var errorMessage: String?
    @State private var isDeleting = false
    @State private var isLoadingNote = false
    @State private var folders: [Folder] = []
    @State private var folderID: UUID?
    @State private var isPinned = false
    @State private var isArchived = false
    @State private var isCloudSyncEnabled = true
    @State private var isConflict = false
    @State private var editBaselineContentHash: String?
    @State private var titleRevision = 0
    @State private var savedTitleRevision = 0
    @State private var bodyRevision = 0
    @State private var savedBodyRevision = 0
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if isConflict {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Conflict copy")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Mark Resolved") {
                        Task {
                            await markConflictResolved()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
            }

            if auth.isSignedIn && !isCloudSyncEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                    Text("Local only")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Sync") {
                        Task {
                            await setCloudSyncEnabled(true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.1))
            }

            if auth.canSync && isCloudSyncEnabled && presence.isOpenElsewhere {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.orange)
                    Text(openElsewhereText)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
            }

            TextField("Title", text: $title)
                .font(.title2.weight(.semibold))
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .disabled(isLoadingNote)
                .onChange(of: title) { _, _ in
                    scheduleTitleSave()
                }

            Divider()

            RichTextEditor(
                attributedText: $attributedText,
                command: $command,
                isFocused: $isFocused,
                refreshToken: $refreshToken
            ) { newValue in
                scheduleSave(with: newValue)
            }
            .disabled(isLoadingNote)
        }
        .onAppear {
#if !targetEnvironment(macCatalyst)
            isFocused = true
#endif
        }
        .task(id: noteID) {
            await loadNote()
        }
        .onDisappear {
            presence.stop()
            if !isDeleting {
                debounceWorkItem?.cancel()
                titleDebounceWorkItem?.cancel()
                Task {
                    await saveTitle()
                    await save(attributedText)
                }
            }
        }
        .onChange(of: auth.canSync) { _, _ in
            configurePresence()
        }
        .onChange(of: isCloudSyncEnabled) { _, _ in
            configurePresence()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .navigationTitle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Note" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                editorActionsMenu
            }
#if !targetEnvironment(macCatalyst)
            ToolbarItemGroup(placement: .keyboard) {
                Button("B") { command = .toggleBold }
                Button("I") { command = .toggleItalic }
                Button("U") { command = .toggleUnderline }
                Button("T") { command = .title }
                Button("H") { command = .heading }
                Button("Body") { command = .body }
                Button("-") { command = .bulletedList }
                Button("1.") { command = .numberedList }
                Button("[]") { command = .checklist }
                Button("A+") { command = .increaseFont }
                Button("A-") { command = .decreaseFont }
            }
#endif
        }
        .alert("Delete note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    debounceWorkItem?.cancel()
                    titleDebounceWorkItem?.cancel()
                    do {
                        if auth.canSync {
                            try await SupabaseNoteStore.shared.deleteNote(id: noteID)
                        } else {
                            SharedStore.shared.deleteNote(id: noteID)
                        }
                        dismiss()
                    } catch {
                        isDeleting = false
                        handleSyncError(error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .alert("Sync Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showHistory) {
            NoteHistoryView(
                noteID: noteID,
                syncEnabled: auth.canSync && isCloudSyncEnabled,
                onClose: {
                    showHistory = false
                }
            ) { entry in
                attributedText = RichTextCodec.attributedString(from: entry.rtfData)
                bodyRevision += 1
                let revision = bodyRevision
                refreshToken = UUID()
                Task {
                    await save(attributedText, force: true, targetBodyRevision: revision)
                }
            }
        }
    }

    private var editorActionsMenu: some View {
        Menu {
            Button {
                Task {
                    await setPinned(!isPinned)
                }
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Section("Folder") {
                Button {
                    Task {
                        await move(to: nil)
                    }
                } label: {
                    Label("No Folder", systemImage: folderID == nil ? "checkmark.circle.fill" : "tray")
                }

                ForEach(folders) { folder in
                    Button {
                        Task {
                            await move(to: folder.id)
                        }
                    } label: {
                        Label(folderPath(for: folder), systemImage: folderID == folder.id ? "checkmark.circle.fill" : "folder")
                    }
                }
            }

            if auth.isSignedIn {
                Button {
                    Task {
                        await setCloudSyncEnabled(!isCloudSyncEnabled)
                    }
                } label: {
                    Label(
                        isCloudSyncEnabled ? "Keep Local Only" : "Sync This Note",
                        systemImage: isCloudSyncEnabled ? "icloud.slash" : "icloud.and.arrow.up"
                    )
                }
            }

            Button {
                showHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            Button {
                Task {
                    await setArchived(!isArchived)
                }
            } label: {
                Label(isArchived ? "Restore" : "Archive", systemImage: "archivebox")
            }

            if isConflict {
                Button {
                    Task {
                        await markConflictResolved()
                    }
                } label: {
                    Label("Mark Resolved", systemImage: "checkmark.seal")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Note Actions")
    }

    private var openElsewhereText: String {
        if presence.otherOpenDevices.count == 1, let peer = presence.otherOpenDevices.first {
            return "Open on \(peer.platform)"
        }
        return "Open on another device"
    }

    private func loadNote() async {
        isLoadingNote = true
        defer { isLoadingNote = false }

        do {
            if auth.canSync {
                folders = try await SupabaseNoteStore.shared.listFolders()
            } else {
                folders = SharedStore.shared.listFolders()
            }
        } catch {
            SupabaseSessionInvalidation.postIfNeeded(for: error)
            folders = SharedStore.shared.listFolders()
        }

        do {
            let note = try await loadCurrentNote()
            guard let note else {
                title = ""
                attributedText = NSAttributedString(string: "")
                folderID = nil
                isPinned = false
                isArchived = false
                isCloudSyncEnabled = true
                isConflict = false
                editBaselineContentHash = nil
                presence.stop()
                return
            }
            applyLoadedNote(note)
            configurePresence()
        } catch {
            if let note = SharedStore.shared.getNote(id: noteID) {
                applyLoadedNote(note)
                configurePresence()
            } else {
                title = ""
                attributedText = NSAttributedString(string: "")
                folderID = nil
                isPinned = false
                isArchived = false
                isCloudSyncEnabled = true
                isConflict = false
                editBaselineContentHash = nil
                presence.stop()
            }
            handleSyncError(error)
        }
    }

    private func loadCurrentNote() async throws -> Note? {
        if auth.canSync {
            return try await SupabaseNoteStore.shared.getNote(id: noteID)
        }
        return SharedStore.shared.getNote(id: noteID)
    }

    private func scheduleSave(with newValue: NSAttributedString) {
        guard !isLoadingNote else { return }
        bodyRevision += 1
        let revision = bodyRevision
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task {
                await save(newValue, targetBodyRevision: revision)
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func scheduleTitleSave() {
        guard !isLoadingNote else { return }
        titleRevision += 1
        let revision = titleRevision
        titleDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task {
                await saveTitle(targetTitleRevision: revision)
            }
        }
        titleDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func save(
        _ newValue: NSAttributedString,
        force: Bool = false,
        targetBodyRevision: Int? = nil
    ) async {
        if let targetBodyRevision, targetBodyRevision != bodyRevision {
            return
        }
        guard force || bodyRevision != savedBodyRevision else { return }

        let bodyRevisionAtStart = targetBodyRevision ?? bodyRevision
        let titleRevisionAtStart = titleRevision

        do {
            if auth.canSync {
                let saved = try await SupabaseNoteStore.shared.updateNote(
                    id: noteID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    attributedText: newValue,
                    expectedBaseHash: editBaselineContentHash
                )
                editBaselineContentHash = saved.lastSyncedContentHash
            } else {
                SharedStore.shared.updateNote(id: noteID, attributedText: newValue)
            }

            if bodyRevision == bodyRevisionAtStart {
                savedBodyRevision = bodyRevisionAtStart
            }
            if titleRevision == titleRevisionAtStart {
                savedTitleRevision = titleRevisionAtStart
            }
        } catch {
            handleSyncError(error)
        }
    }

    private func saveTitle(force: Bool = false, targetTitleRevision: Int? = nil) async {
        if let targetTitleRevision, targetTitleRevision != titleRevision {
            return
        }
        guard force || titleRevision != savedTitleRevision else { return }

        let titleRevisionAtStart = targetTitleRevision ?? titleRevision
        let bodyRevisionAtStart = bodyRevision

        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if auth.canSync {
                let saved = try await SupabaseNoteStore.shared.updateNote(
                    id: noteID,
                    title: trimmedTitle,
                    attributedText: attributedText,
                    expectedBaseHash: editBaselineContentHash
                )
                editBaselineContentHash = saved.lastSyncedContentHash
            } else {
                SharedStore.shared.updateNoteTitle(id: noteID, title: trimmedTitle)
            }

            if titleRevision == titleRevisionAtStart {
                savedTitleRevision = titleRevisionAtStart
            }
            if bodyRevision == bodyRevisionAtStart {
                savedBodyRevision = bodyRevisionAtStart
            }
        } catch {
            handleSyncError(error)
        }
    }

    private func move(to newFolderID: UUID?) async {
        let previousFolderID = folderID
        folderID = newFolderID
        do {
            if auth.canSync {
                try await SupabaseNoteStore.shared.moveNote(id: noteID, folderID: newFolderID)
            } else {
                SharedStore.shared.moveNote(id: noteID, folderID: newFolderID)
            }
        } catch {
            folderID = previousFolderID
            handleSyncError(error)
        }
    }

    private func setPinned(_ newValue: Bool) async {
        let previousValue = isPinned
        isPinned = newValue
        do {
            if auth.canSync {
                try await SupabaseNoteStore.shared.setNotePinned(id: noteID, isPinned: newValue)
            } else {
                SharedStore.shared.setNotePinned(id: noteID, isPinned: newValue)
            }
        } catch {
            isPinned = previousValue
            handleSyncError(error)
        }
    }

    private func setArchived(_ newValue: Bool) async {
        let previousValue = isArchived
        isArchived = newValue
        do {
            if auth.canSync {
                try await SupabaseNoteStore.shared.setNoteArchived(id: noteID, isArchived: newValue)
            } else {
                SharedStore.shared.setNoteArchived(id: noteID, isArchived: newValue)
            }
        } catch {
            isArchived = previousValue
            handleSyncError(error)
        }
    }

    private func setCloudSyncEnabled(_ newValue: Bool) async {
        let previousValue = isCloudSyncEnabled
        isCloudSyncEnabled = newValue
        debounceWorkItem?.cancel()
        titleDebounceWorkItem?.cancel()

        do {
            await saveTitle()
            await save(attributedText)
            if auth.canSync {
                try await SupabaseNoteStore.shared.setNoteCloudSyncEnabled(id: noteID, isEnabled: newValue)
            } else {
                SharedStore.shared.setNoteCloudSyncEnabled(id: noteID, isEnabled: newValue)
            }
            configurePresence()
        } catch {
            isCloudSyncEnabled = previousValue
            configurePresence()
            handleSyncError(error)
        }
    }

    private func markConflictResolved() async {
        let previousValue = isConflict
        isConflict = false
        do {
            if auth.canSync {
                try await SupabaseNoteStore.shared.markConflictResolved(id: noteID)
            } else {
                SharedStore.shared.markConflictResolved(id: noteID)
            }
        } catch {
            isConflict = previousValue
            handleSyncError(error)
        }
    }

    private func applyLoadedNote(_ note: Note) {
        title = note.title
        attributedText = RichTextCodec.attributedString(from: note.rtfData)
        folderID = note.folderID
        isPinned = note.isPinned
        isArchived = note.isArchived
        isCloudSyncEnabled = note.isCloudSyncEnabled
        isConflict = note.isConflict
        editBaselineContentHash = note.lastSyncedContentHash ?? NoteSyncResolver.fingerprint(note)
        titleRevision = 0
        savedTitleRevision = 0
        bodyRevision = 0
        savedBodyRevision = 0
        refreshToken = UUID()
    }

    private func configurePresence() {
        guard scenePhase == .active, auth.canSync, isCloudSyncEnabled else {
            presence.stop()
            return
        }

        presence.start(noteID: noteID)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await loadNote()
            }
        case .inactive, .background:
            presence.stop()
            flushPendingSaves()
        @unknown default:
            presence.stop()
        }
    }

    private func flushPendingSaves() {
        guard !isDeleting else { return }

        debounceWorkItem?.cancel()
        titleDebounceWorkItem?.cancel()
        Task {
            await saveTitle()
            await save(attributedText)
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

    private func folderPath(for folder: Folder) -> String {
        var names = [folder.displayName]
        var parentID = folder.parentID
        var visited = Set([folder.id])

        while let id = parentID,
              !visited.contains(id),
              let parent = folders.first(where: { $0.id == id }) {
            visited.insert(id)
            names.insert(parent.displayName, at: 0)
            parentID = parent.parentID
        }

        return names.joined(separator: " / ")
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(noteID: UUID())
    }
    .environmentObject(AuthViewModel())
}
