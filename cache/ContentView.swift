//
//  ContentView.swift
//  cache
//
//  Created by Johnston Liu on 2025-12-28.
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = NotesViewModel()
    @StateObject private var realtimeSync = RealtimeSyncService()
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var scope: NoteListScope = .root
    @State private var searchText = ""
    @State private var showFolderEditor = false
    @State private var showSignIn = false
    @State private var editingFolder: Folder?
    @State private var folderNameDraft = ""
    @State private var folderPendingDelete: Folder?
    @State private var exportFile: ExportFile?
    @State private var dataActionErrorMessage: String?
    @State private var showDeleteSyncedDataConfirm = false
    @State private var isDeletingSyncedData = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var showDeleteAccountVerification = false
    @State private var deleteAccountVerificationCode = ""
    @State private var deleteAccountConfirmationText = ""

    private var visibleNotes: [Note] {
        viewModel.visibleNotes(for: scope, searchText: searchText)
    }

    private var visibleFolders: [Folder] {
        guard scope == .root || currentFolderID != nil else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentID = currentFolderID

        let folders = viewModel.folders.filter { $0.parentID == parentID }
        guard !query.isEmpty else { return folders }
        return folders.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    private var currentFolderID: UUID? {
        if case let .folder(id) = scope {
            return id
        }
        return nil
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            presentedContent
        }
    }

    private var baseContent: some View {
        notesList
            .overlay {
                notesOverlay
            }
            .navigationTitle(viewModel.title(for: scope))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar {
                toolbarContent
            }
    }

    private var lifecycleContent: some View {
        baseContent
            .refreshable {
                await auth.refreshSession()
                await viewModel.reload(syncEnabled: auth.canSync)
            }
            .task {
                await auth.refreshSession()
                await viewModel.reload(syncEnabled: auth.canSync)
                configureRealtimeSync()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await auth.refreshSession()
                        await viewModel.reload(syncEnabled: auth.canSync)
                        configureRealtimeSync()
                    }
                } else if newPhase == .background {
                    realtimeSync.stop()
                }
            }
            .onChange(of: router.path) { _, path in
                if path.isEmpty {
                    Task {
                        await viewModel.reload(syncEnabled: auth.canSync)
                    }
                }
            }
            .onChange(of: auth.phase) { _, _ in
                Task {
                    await viewModel.reload(syncEnabled: auth.canSync)
                    configureRealtimeSync()
                }
            }
            .onChange(of: auth.syncEnabled) { _, _ in
                Task {
                    await viewModel.reload(syncEnabled: auth.canSync)
                    configureRealtimeSync()
                }
            }
            .onChange(of: viewModel.folders) { _, folders in
                if case let .folder(id) = scope, !folders.contains(where: { $0.id == id }) {
                    scope = .root
                }
            }
    }

    private var presentedContent: some View {
        lifecycleContent
            .alert("Sync Error", isPresented: syncErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showFolderEditor) {
                FolderEditorSheet(
                    title: editingFolder == nil ? "New Folder" : "Rename Folder",
                    name: $folderNameDraft,
                    onCancel: {
                        showFolderEditor = false
                    },
                    onSave: {
                        Task {
                            await saveFolder()
                        }
                    }
                )
            }
            .sheet(isPresented: $showSignIn) {
                SignInView()
                    .environmentObject(auth)
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .sheet(isPresented: $showDeleteAccountVerification) {
                DeleteAccountVerificationSheet(
                    email: auth.userEmail ?? "",
                    code: $deleteAccountVerificationCode,
                    confirmationText: $deleteAccountConfirmationText,
                    isWorking: isDeletingAccount,
                    onCancel: {
                        showDeleteAccountVerification = false
                    },
                    onResendCode: {
                        Task {
                            await sendDeleteAccountVerificationCode()
                        }
                    },
                    onDelete: {
                        Task {
                            await verifyAndDeleteAccount()
                        }
                    }
                )
            }
            .alert("Data Action Failed", isPresented: dataActionErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataActionErrorMessage ?? "")
            }
            .confirmationDialog(
                "Delete synced cloud data?",
                isPresented: $showDeleteSyncedDataConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Synced Cloud Data", role: .destructive) {
                    Task {
                        await deleteSyncedCloudData()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes notes, folders, and note history from Supabase for your signed-in account. Local notes on this device stay here, and sync will turn off. Other devices will need to sign in again.")
            }
            .confirmationDialog(
                "Delete account?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        await beginDeleteAccountVerification()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes your Supabase account and synced cloud data. Local notes on this device stay here. You will need to verify a fresh email code before deletion.")
            }
            .confirmationDialog(
                "Delete folder?",
                isPresented: folderDeletionBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Folder", role: .destructive) {
                    guard let folder = folderPendingDelete else { return }
                    Task {
                        await viewModel.deleteFolder(folder, syncEnabled: auth.canSync)
                        if scope == .folder(folder.id) {
                            scope = folder.parentID.map(NoteListScope.folder) ?? .root
                        }
                        folderPendingDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    folderPendingDelete = nil
                }
            } message: {
                Text("Notes and subfolders in this folder will move up one level.")
            }
            .navigationDestination(for: UUID.self) { noteID in
                NoteEditorView(noteID: noteID)
                    .id(noteID)
            }
    }

    private var notesList: some View {
        List {
            if let folderNavigationTarget {
                FolderNavigationItem(
                    title: folderNavigationTarget.title,
                    onOpen: {
                        scope = folderNavigationTarget.scope
                    }
                )
            }

            if !visibleFolders.isEmpty {
                Section("Folders") {
                    ForEach(visibleFolders) { folder in
                        FolderListItem(
                            folder: folder,
                            noteCount: noteCount(in: folder),
                            childFolderCount: childFolderCount(in: folder),
                            onOpen: {
                                scope = .folder(folder.id)
                            },
                            onRename: {
                                presentRenameFolder(folder)
                            },
                            onDelete: {
                                folderPendingDelete = folder
                            }
                        )
                    }
                }
            }

            if visibleFolders.isEmpty {
                notesSectionRows
            } else if !visibleNotes.isEmpty {
                Section("Notes") {
                    notesSectionRows
                }
            }
        }
    }

    private var notesSectionRows: some View {
        ForEach(visibleNotes) { note in
            NoteListItem(
                note: note,
                folderName: viewModel.folderName(for: note.folderID),
                folders: viewModel.folders,
                isSignedIn: auth.isSignedIn,
                syncEnabled: auth.canSync,
                viewModel: viewModel
            )
        }
        .onDelete(perform: deleteNotes)
    }

    @ViewBuilder
    private var notesOverlay: some View {
        if viewModel.isLoading && viewModel.notes.isEmpty {
            ProgressView()
        } else if visibleNotes.isEmpty && visibleFolders.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: Text(emptyDescription)
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            SyncMenu(
                showSignIn: $showSignIn,
                isSyncing: viewModel.isLoading && auth.canSync,
                hasPendingChanges: viewModel.hasPendingCloudChanges,
                lastSyncCompletedAt: viewModel.lastSyncCompletedAt,
                isRealtimeActive: realtimeSync.isActive,
                realtimeErrorMessage: realtimeSync.errorMessage,
                syncErrorMessage: viewModel.errorMessage,
                isDeletingSyncedData: isDeletingSyncedData,
                isDeletingAccount: isDeletingAccount,
                onExport: exportLocalData,
                onDeleteSyncedData: {
                    showDeleteSyncedDataConfirm = true
                },
                onDeleteAccount: {
                    showDeleteAccountConfirm = true
                }
            )
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            FilterMenu(
                scope: $scope,
                folders: viewModel.folders,
                activeFolder: activeFolder,
                onNewFolder: presentNewFolder,
                onRenameFolder: presentRenameFolder,
                onDeleteFolder: { folder in
                    folderPendingDelete = folder
                }
            )

            Button {
                createNote()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Note")
        }
    }

    private var activeFolder: Folder? {
        guard case let .folder(id) = scope else { return nil }
        return viewModel.folders.first { $0.id == id }
    }

    private var syncErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: clearSyncError
        )
    }

    private var dataActionErrorBinding: Binding<Bool> {
        Binding(
            get: { dataActionErrorMessage != nil },
            set: clearDataActionError
        )
    }

    private var folderDeletionBinding: Binding<Bool> {
        Binding(
            get: { folderPendingDelete != nil },
            set: clearFolderDeletion
        )
    }

    private var emptyTitle: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Notes" : "No Results"
    }

    private var emptySystemImage: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "note.text" : "magnifyingglass"
    }

    private var emptyDescription: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search."
        }
        switch scope {
        case .root:
            return "Create a note or folder to start."
        case .all:
            return "Create notes or choose a folder to start."
        case .pinned:
            return "Pinned notes will appear here."
        case .archived:
            return "Archived notes will appear here."
        case .folder:
            return "Create a note or folder here."
        }
    }

    private func presentNewFolder() {
        editingFolder = nil
        folderNameDraft = ""
        showFolderEditor = true
    }

    private func presentRenameFolder(_ folder: Folder) {
        editingFolder = folder
        folderNameDraft = folder.displayName
        showFolderEditor = true
    }

    private func clearSyncError(_ isPresented: Bool) {
        if !isPresented {
            viewModel.errorMessage = nil
        }
    }

    private func configureRealtimeSync() {
        guard auth.canSync, scenePhase == .active else {
            realtimeSync.stop()
            return
        }

        realtimeSync.start {
            await viewModel.reload(syncEnabled: true)
        }
    }

    private func clearDataActionError(_ isPresented: Bool) {
        if !isPresented {
            dataActionErrorMessage = nil
        }
    }

    private func clearFolderDeletion(_ isPresented: Bool) {
        if !isPresented {
            folderPendingDelete = nil
        }
    }

    private func saveFolder() async {
        if let editingFolder {
            await viewModel.renameFolder(editingFolder, name: folderNameDraft, syncEnabled: auth.canSync)
        } else if let folder = await viewModel.createFolder(
            name: folderNameDraft,
            parentID: currentFolderID,
            syncEnabled: auth.canSync
        ) {
            scope = .folder(folder.id)
        }
        showFolderEditor = false
    }

    private func deleteNotes(at offsets: IndexSet) {
        let notesToDelete: [Note] = offsets.map { visibleNotes[$0] }
        let syncEnabled = auth.canSync
        Task {
            await viewModel.deleteNotes(notesToDelete, syncEnabled: syncEnabled)
        }
    }

    private func noteCount(in folder: Folder) -> Int {
        viewModel.notes.filter { note in
            note.folderID == folder.id && !note.isArchived
        }.count
    }

    private func childFolderCount(in folder: Folder) -> Int {
        viewModel.folders.filter { $0.parentID == folder.id }.count
    }

    private var folderNavigationTarget: (title: String, scope: NoteListScope)? {
        guard case let .folder(folderID) = scope else { return nil }
        let folder = viewModel.folders.first { $0.id == folderID }
        guard let parentID = folder?.parentID else {
            return ("Notes", .root)
        }
        let parentName = viewModel.folders.first { $0.id == parentID }?.displayName ?? "Parent Folder"
        return (parentName, .folder(parentID))
    }

    private func createNote() {
        let targetScope = (scope == .archived || scope == .all) ? .root : scope
        let syncEnabled = auth.canSync
        Task {
            if let id = await viewModel.createNote(in: targetScope, syncEnabled: syncEnabled) {
                router.path.append(id)
            }
        }
    }

    private func exportLocalData() {
        do {
            dataActionErrorMessage = nil
            exportFile = ExportFile(url: try NoteExportService.exportLocalData())
        } catch {
            handleDataActionError(error)
        }
    }

    private func deleteSyncedCloudData() async {
        guard auth.isSignedIn, !isDeletingSyncedData else { return }
        isDeletingSyncedData = true
        defer { isDeletingSyncedData = false }

        do {
            dataActionErrorMessage = nil
            try await SupabaseNoteStore.shared.deleteSyncedData()
            await finishCloudDataRemoval(signOut: true)
        } catch {
            if SupabaseSessionInvalidation.isBenignCancellation(error) {
                return
            }
            if SupabaseSessionInvalidation.isSessionInvalidation(error) {
                await finishCloudDataRemoval(signOut: true)
            } else {
                handleDataActionError(error)
            }
        }
    }

    private func beginDeleteAccountVerification() async {
        let sent = await sendDeleteAccountVerificationCode()
        if sent {
            deleteAccountVerificationCode = ""
            deleteAccountConfirmationText = ""
            showDeleteAccountVerification = true
        }
    }

    private func sendDeleteAccountVerificationCode() async -> Bool {
        guard auth.isSignedIn, !isDeletingAccount else { return false }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        dataActionErrorMessage = nil
        if await auth.sendDeletionVerificationCode() {
            return true
        }

        dataActionErrorMessage = auth.errorMessage ?? "Could not send a verification code."
        return false
    }

    private func verifyAndDeleteAccount() async {
        guard auth.isSignedIn, !isDeletingAccount else { return }
        guard deleteAccountConfirmationText == "DELETE" else {
            dataActionErrorMessage = "Type DELETE to confirm account deletion."
            return
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        guard await auth.verifyDeletionCode(deleteAccountVerificationCode) else {
            dataActionErrorMessage = auth.errorMessage ?? "Could not verify the deletion code."
            return
        }

        do {
            dataActionErrorMessage = nil
            try await SupabaseNoteStore.shared.deleteAccount()
            await finishCloudDataRemoval(signOut: true)
            clearDeleteAccountVerificationState()
        } catch {
            if SupabaseSessionInvalidation.isBenignCancellation(error) {
                return
            }
            if SupabaseSessionInvalidation.isSessionInvalidation(error) {
                await finishCloudDataRemoval(signOut: true)
                clearDeleteAccountVerificationState()
            } else {
                handleDataActionError(error)
            }
        }
    }

    private func handleDataActionError(_ error: Error) {
        guard !SupabaseSessionInvalidation.isBenignCancellation(error) else { return }

        if SupabaseSessionInvalidation.postIfNeeded(for: error) {
            dataActionErrorMessage = "Your sync account is no longer available. Sign in again to resume syncing."
        } else {
            dataActionErrorMessage = error.localizedDescription
        }
    }

    private func finishCloudDataRemoval(signOut: Bool) async {
        realtimeSync.stop()
        SharedStore.shared.setAllNotesCloudSyncEnabled(false)
        auth.setSyncEnabled(false)
        if signOut {
            await auth.signOut()
        }
        await viewModel.reload(syncEnabled: false)
    }

    private func clearDeleteAccountVerificationState() {
        deleteAccountVerificationCode = ""
        deleteAccountConfirmationText = ""
        showDeleteAccountVerification = false
    }
}

private struct FolderNavigationItem: View {
    let title: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label(title, systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct FolderListItem: View {
    let folder: Folder
    let noteCount: Int
    let childFolderCount: Int
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        row
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .contextMenu {
                Button(action: onRename) {
                    Label("Rename Folder", systemImage: "pencil")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }

                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Folder \(folder.displayName)")
            .accessibilityAddTraits(.isButton)
    }

    private var row: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var detailText: String {
        let folderText = childFolderCount == 1 ? "1 folder" : "\(childFolderCount) folders"
        let noteText = noteCount == 1 ? "1 note" : "\(noteCount) notes"

        if childFolderCount == 0 {
            return noteText
        }
        if noteCount == 0 {
            return folderText
        }
        return "\(folderText) · \(noteText)"
    }
}

private struct NoteListItem: View {
    let note: Note
    let folderName: String
    let folders: [Folder]
    let isSignedIn: Bool
    let syncEnabled: Bool
    let viewModel: NotesViewModel

    var body: some View {
        NavigationLink(value: note.id) {
            NoteRow(
                note: note,
                folderName: folderName
            )
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    await viewModel.togglePinned(note, syncEnabled: syncEnabled)
                }
            } label: {
                Label(pinTitle, systemImage: pinIcon)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            archiveSwipeButton

            Button(role: .destructive) {
                Task {
                    await viewModel.deleteNotes([note], syncEnabled: syncEnabled)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                Task {
                    await viewModel.togglePinned(note, syncEnabled: syncEnabled)
                }
            } label: {
                Label(pinTitle, systemImage: pinIcon)
            }

            MoveNoteMenu(note: note, folders: folders) { folderID in
                Task {
                    await viewModel.move(note, to: folderID, syncEnabled: syncEnabled)
                }
            }

            if isSignedIn {
                Button {
                    Task {
                        await viewModel.setCloudSyncEnabled(
                            note,
                            isEnabled: !note.isCloudSyncEnabled,
                            syncEnabled: syncEnabled
                        )
                    }
                } label: {
                    Label(
                        note.isCloudSyncEnabled ? "Keep Local Only" : "Sync This Note",
                        systemImage: note.isCloudSyncEnabled ? "icloud.slash" : "icloud.and.arrow.up"
                    )
                }
            }

            Button {
                Task {
                    await viewModel.setArchived(note, isArchived: !note.isArchived, syncEnabled: syncEnabled)
                }
            } label: {
                Label(note.isArchived ? "Restore" : "Archive", systemImage: "archivebox")
            }

            if note.isConflict {
                Button {
                    Task {
                        await viewModel.markConflictResolved(note, syncEnabled: syncEnabled)
                    }
                } label: {
                    Label("Mark Resolved", systemImage: "checkmark.seal")
                }
            }
        }
    }

    @ViewBuilder
    private var archiveSwipeButton: some View {
        if note.isArchived {
            Button {
                Task {
                    await viewModel.setArchived(note, isArchived: false, syncEnabled: syncEnabled)
                }
            } label: {
                Label("Restore", systemImage: "archivebox")
            }
            .tint(.blue)
        } else {
            Button {
                Task {
                    await viewModel.setArchived(note, isArchived: true, syncEnabled: syncEnabled)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }

    private var pinTitle: String {
        note.isPinned ? "Unpin" : "Pin"
    }

    private var pinIcon: String {
        note.isPinned ? "pin.slash" : "pin"
    }
}

private struct SyncMenu: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Binding var showSignIn: Bool

    let isSyncing: Bool
    let hasPendingChanges: Bool
    let lastSyncCompletedAt: Date?
    let isRealtimeActive: Bool
    let realtimeErrorMessage: String?
    let syncErrorMessage: String?
    let isDeletingSyncedData: Bool
    let isDeletingAccount: Bool
    let onExport: () -> Void
    let onDeleteSyncedData: () -> Void
    let onDeleteAccount: () -> Void

    var body: some View {
        Menu {
            Section("Sync") {
                Label(statusTitle, systemImage: statusIconName)
                if auth.canSync {
                    Label(realtimeStatusTitle, systemImage: realtimeStatusIconName)
                }
                if syncErrorMessage != nil, auth.canSync {
                    Label("Sync Needs Attention", systemImage: "exclamationmark.triangle")
                }
            }

            Section("Data") {
                Button(action: onExport) {
                    Label("Export Local Data", systemImage: "square.and.arrow.up")
                }
            }

            switch auth.phase {
            case .loading:
                Label("Checking Sync", systemImage: "arrow.triangle.2.circlepath")
            case .unconfigured:
                Label("Sync Not Configured", systemImage: "icloud.slash")
            case .signedOut:
                Button {
                    showSignIn = true
                } label: {
                    Label("Sign In to Sync", systemImage: "person.crop.circle.badge.plus")
                }
            case .signedIn:
                Section(auth.userEmail ?? "Signed In") {
                    Toggle(isOn: Binding(
                        get: { auth.syncEnabled },
                        set: { auth.setSyncEnabled($0) }
                    )) {
                        Label("Sync Notes", systemImage: auth.syncEnabled ? "icloud.fill" : "icloud")
                    }

                    Button {
                        Task {
                            await auth.signOut()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive, action: onDeleteSyncedData) {
                        Label(
                            isDeletingSyncedData ? "Deleting Cloud Data" : "Delete Synced Cloud Data",
                            systemImage: "trash"
                        )
                    }
                    .disabled(isDeletingSyncedData)

                    Button(role: .destructive, action: onDeleteAccount) {
                        Label(
                            isDeletingAccount ? "Deleting Account" : "Delete Account",
                            systemImage: "person.crop.circle.badge.xmark"
                        )
                    }
                    .disabled(isDeletingAccount)
                }
            }
        } label: {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: iconName)
            }
        }
    }

    private var iconName: String {
        if syncErrorMessage != nil && auth.canSync {
            return "icloud.slash"
        }
        if hasPendingChanges && auth.canSync {
            return "icloud.and.arrow.up"
        }
        if auth.canSync {
            return "icloud.fill"
        }
        if auth.isSignedIn {
            return "icloud"
        }
        return "icloud.slash"
    }

    private var statusTitle: String {
        if isSyncing {
            return "Syncing"
        }
        if syncErrorMessage != nil && auth.canSync {
            return "Sync Error"
        }
        if hasPendingChanges && auth.canSync {
            return "Pending Upload"
        }

        switch auth.phase {
        case .loading:
            return "Checking Sync"
        case .unconfigured:
            return "Supabase Not Configured"
        case .signedOut:
            return "Local Only"
        case .signedIn:
            if auth.syncEnabled {
                return lastSyncedTitle ?? "Synced"
            }
            return "Cloud Sync Off"
        }
    }

    private var statusIconName: String {
        if isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        return iconName
    }

    private var lastSyncedTitle: String? {
        guard let lastSyncCompletedAt else { return nil }
        return "Synced \(lastSyncCompletedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var realtimeStatusTitle: String {
        if isRealtimeActive {
            return "Realtime On"
        }
        if realtimeErrorMessage != nil {
            return "Realtime Paused"
        }
        return "Realtime Connecting"
    }

    private var realtimeStatusIconName: String {
        if isRealtimeActive {
            return "dot.radiowaves.left.and.right"
        }
        if realtimeErrorMessage != nil {
            return "antenna.radiowaves.left.and.right.slash"
        }
        return "antenna.radiowaves.left.and.right"
    }
}

private struct NoteRow: View {
    let note: Note
    let folderName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: noteIcon)
                .foregroundStyle(noteIconStyle)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(note.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if note.isConflict {
                        Label("Conflict copy", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    if !note.isCloudSyncEnabled {
                        Label("Local only", systemImage: "icloud.slash")
                            .lineLimit(1)
                    }
                    if note.folderID != nil {
                        Label(folderName, systemImage: "folder")
                            .lineLimit(1)
                    }
                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var noteIcon: String {
        if note.isConflict {
            return "exclamationmark.triangle.fill"
        }
        if note.isArchived {
            return "archivebox"
        }
        return note.isPinned ? "pin.fill" : "doc.text"
    }

    private var noteIconStyle: Color {
        note.isConflict || note.isPinned ? .orange : .secondary
    }
}

private struct FilterMenu: View {
    @Binding var scope: NoteListScope
    let folders: [Folder]
    let activeFolder: Folder?
    let onNewFolder: () -> Void
    let onRenameFolder: (Folder) -> Void
    let onDeleteFolder: (Folder) -> Void

    var body: some View {
        Menu {
            Section("Views") {
                Button {
                    scope = .root
                } label: {
                    Label("Root Folder", systemImage: scope == .root ? "checkmark.circle.fill" : "folder")
                }

                Button {
                    scope = .all
                } label: {
                    Label("All Notes", systemImage: scope == .all ? "checkmark.circle.fill" : "note.text")
                }

                Button {
                    scope = .pinned
                } label: {
                    Label("Pinned", systemImage: scope == .pinned ? "checkmark.circle.fill" : "pin")
                }

                Button {
                    scope = .archived
                } label: {
                    Label("Archive", systemImage: scope == .archived ? "checkmark.circle.fill" : "archivebox")
                }
            }

            Section("Folders") {
                Button {
                    onNewFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                ForEach(folders) { folder in
                    Button {
                        scope = .folder(folder.id)
                    } label: {
                        Label(folderPath(for: folder), systemImage: scope == .folder(folder.id) ? "checkmark.circle.fill" : "folder")
                    }
                }
            }

            if let activeFolder {
                Section("Current Folder") {
                    Button {
                        onRenameFolder(activeFolder)
                    } label: {
                        Label("Rename Folder", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        onDeleteFolder(activeFolder)
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
            }
        } label: {
            Label("Filter Notes", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
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

private struct MoveNoteMenu: View {
    let note: Note
    let folders: [Folder]
    let onMove: (UUID?) -> Void

    var body: some View {
        Menu {
            Button {
                onMove(nil)
            } label: {
                Label("No Folder", systemImage: note.folderID == nil ? "checkmark.circle.fill" : "tray")
            }

            ForEach(folders) { folder in
                Button {
                    onMove(folder.id)
                } label: {
                    Label(folderPath(for: folder), systemImage: note.folderID == folder.id ? "checkmark.circle.fill" : "folder")
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
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

private struct DeleteAccountVerificationSheet: View {
    let email: String
    @Binding var code: String
    @Binding var confirmationText: String
    let isWorking: Bool
    let onCancel: () -> Void
    let onResendCode: () -> Void
    let onDelete: () -> Void

    @State private var resendAvailableAt = Date().addingTimeInterval(30)
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var resendSecondsRemaining: Int {
        max(0, Int(ceil(resendAvailableAt.timeIntervalSince(now))))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(email)
                        .foregroundStyle(.secondary)

                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)

                    TextField("Type DELETE", text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter the fresh verification code sent to your email, then type DELETE. This permanently deletes your sync account and cloud data.")
                }

                Section {
                    Button(resendSecondsRemaining > 0 ? "Resend Code in \(resendSecondsRemaining)s" : "Resend Code") {
                        resendAvailableAt = Date().addingTimeInterval(30)
                        onResendCode()
                    }
                    .disabled(isWorking || resendSecondsRemaining > 0)

                    Button(role: .destructive, action: onDelete) {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Delete Account")
                        }
                    }
                    .disabled(isWorking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || confirmationText != "DELETE")
                }
            }
            .navigationTitle("Verify Deletion")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { date in
                now = date
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isWorking)
                }
            }
        }
    }
}

private struct FolderEditorSheet: View {
    let title: String
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(!canSave)
                }
            }
        }
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if canImport(UIKit)
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    ContentView()
        .environmentObject(AppRouter())
        .environmentObject(AuthViewModel())
}
