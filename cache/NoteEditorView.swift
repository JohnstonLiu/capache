import SwiftUI

struct NoteEditorView: View {
    let noteID: UUID

    @State private var attributedText = NSAttributedString(string: "")
    @State private var command: RichTextCommand?
    @State private var debounceWorkItem: DispatchWorkItem?
    @State private var isFocused = false
    @State private var showHistory = false
    @State private var showDeleteConfirm = false
    @State private var refreshToken = UUID()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RichTextEditor(
            attributedText: $attributedText,
            command: $command,
            isFocused: $isFocused,
            refreshToken: $refreshToken
        ) { newValue in
            scheduleSave(with: newValue)
        }
        .onAppear {
            loadNote()
            isFocused = true
        }
        .onDisappear {
            SharedStore.shared.updateNote(id: noteID, attributedText: attributedText)
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
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
        }
        .alert("Delete note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                SharedStore.shared.deleteNote(id: noteID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .sheet(isPresented: $showHistory) {
            NoteHistoryView(noteID: noteID) { entry in
                attributedText = RichTextCodec.attributedString(from: entry.rtfData)
                SharedStore.shared.updateNote(id: noteID, attributedText: attributedText)
                refreshToken = UUID()
            }
        }
    }

    private func loadNote() {
        if let note = SharedStore.shared.getNote(id: noteID) {
            attributedText = RichTextCodec.attributedString(from: note.rtfData)
        } else {
            attributedText = NSAttributedString(string: "")
        }
    }

    private func scheduleSave(with newValue: NSAttributedString) {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            SharedStore.shared.updateNote(id: noteID, attributedText: newValue)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(noteID: UUID())
    }
}
