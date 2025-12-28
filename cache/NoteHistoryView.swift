import SwiftUI

struct NoteHistoryView: View {
    let noteID: UUID
    let onRestore: (NoteHistoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [NoteHistoryEntry] = []
    @State private var previewEntry: NoteHistoryEntry?
    @State private var showClearConfirm = false

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
                    .onDelete(perform: deleteEntries)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        showClearConfirm = true
                    }
                    .disabled(entries.isEmpty)
                }
            }
        }
        .onAppear {
            reload()
        }
        .alert("Clear history?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                SharedStore.shared.clearHistory(for: noteID)
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .sheet(item: $previewEntry) { entry in
            NoteHistoryPreviewView(entry: entry) {
                onRestore(entry)
                dismiss()
            }
        }
    }

    private func reload() {
        entries = SharedStore.shared.listHistory(for: noteID)
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            SharedStore.shared.deleteHistoryEntry(id: entries[index].id)
        }
        reload()
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
