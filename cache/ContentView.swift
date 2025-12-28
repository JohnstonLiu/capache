//
//  ContentView.swift
//  cache
//
//  Created by Johnston Liu on 2025-12-28.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = NotesViewModel()
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                ForEach(viewModel.notes) { note in
                    NavigationLink(value: note.id) {
                        Text(note.plainText.isEmpty ? AttributedString("jot...") : RichTextCodec.attributedForDisplay(note: note))
                            .lineLimit(2)
                    }
                }
                .onDelete(perform: viewModel.deleteNotes)
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let id = viewModel.createNote()
                        router.path.append(id)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                viewModel.reload()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.reload()
                }
            }
            .navigationDestination(for: UUID.self) { noteID in
                NoteEditorView(noteID: noteID)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppRouter())
}
