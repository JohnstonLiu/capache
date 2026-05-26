import WidgetKit
import SwiftUI

struct NoteEntry: TimelineEntry {
    let date: Date
    let configuration: SelectNoteIntent
    let note: Note?
    let isMissingSelection: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(
            date: Date(),
            configuration: SelectNoteIntent(),
            note: Note(id: UUID(), title: "Quick Note", attributedText: NSAttributedString(string: "Jot something quick..."), updatedAt: Date()),
            isMissingSelection: false
        )
    }

    func snapshot(for configuration: SelectNoteIntent, in context: Context) async -> NoteEntry {
        let result = await loadNote(from: configuration)
        return NoteEntry(date: Date(), configuration: configuration, note: result.note, isMissingSelection: result.isMissingSelection)
    }

    func timeline(for configuration: SelectNoteIntent, in context: Context) async -> Timeline<NoteEntry> {
        let result = await loadNote(from: configuration)
        let entry = NoteEntry(date: Date(), configuration: configuration, note: result.note, isMissingSelection: result.isMissingSelection)
        let refresh = Date().addingTimeInterval(60 * 5)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadNote(from configuration: SelectNoteIntent) async -> (note: Note?, isMissingSelection: Bool) {
        guard let id = configuration.note?.id else {
            return (note: nil, isMissingSelection: false)
        }

        let note = await WidgetBackgroundRefreshClient.refreshNote(id: id) ?? SharedStore.shared.getNote(id: id)
        return (note: note, isMissingSelection: note == nil)
    }
}
