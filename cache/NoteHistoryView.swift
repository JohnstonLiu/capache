import SwiftUI

struct NoteHistoryView: View {
    let noteID: UUID
    let syncEnabled: Bool
    let onClose: () -> Void
    let onRestore: (NoteHistoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [NoteHistoryEntry] = []
    @State private var previewEntry: NoteHistoryEntry?
    @State private var showClearConfirm = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No history yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        Button {
                            previewEntry = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text(entry.plainText.isEmpty ? "jot..." : entry.plainText)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete { offsets in
                        Task {
                            await deleteEntries(at: offsets)
                        }
                    }
                }
            }
            .overlay {
                if isLoading && entries.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        showClearConfirm = true
                    }
                    .disabled(entries.isEmpty)
                }
            }
        }
        .task {
            await reload()
        }
        .alert("Clear history?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                Task {
                    await clearHistory()
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
        .sheet(item: $previewEntry) { entry in
            NoteHistoryPreviewView(entry: entry) {
                onRestore(entry)
                close()
            }
        }
    }

    private func close() {
        onClose()
        dismiss()
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            errorMessage = nil
            if syncEnabled {
                entries = try await SupabaseNoteStore.shared.listHistory(for: noteID)
            } else {
                entries = SharedStore.shared.listHistory(for: noteID)
            }
        } catch {
            entries = SharedStore.shared.listHistory(for: noteID)
            handleSyncError(error)
        }
    }

    private func deleteEntries(at offsets: IndexSet) async {
        for index in offsets {
            do {
                if syncEnabled {
                    try await SupabaseNoteStore.shared.deleteHistoryEntry(id: entries[index].id)
                } else {
                    SharedStore.shared.deleteHistoryEntry(id: entries[index].id)
                }
            } catch {
                handleSyncError(error)
            }
        }
        await reload()
    }

    private func clearHistory() async {
        do {
            if syncEnabled {
                try await SupabaseNoteStore.shared.clearHistory(for: noteID)
            } else {
                SharedStore.shared.clearHistory(for: noteID)
            }
            await reload()
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

private struct NoteHistoryPreviewView: View {
    let entry: NoteHistoryEntry
    let onRestore: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(RichTextCodec.attributedForDisplay(note: Note(id: entry.noteID, rtfData: entry.rtfData, plainText: entry.plainText, updatedAt: entry.createdAt)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        onRestore()
                    }
                }
            }
        }
    }
}
