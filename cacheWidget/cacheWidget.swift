import WidgetKit
import SwiftUI

struct cacheWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = entry.note {
                Text(note.plainText.isEmpty ? AttributedString("jot...") : RichTextCodec.attributedForDisplay(note: note))
                    .lineLimit(nil)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if entry.isMissingSelection {
                Text("Note not found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No note selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 10)
        .padding(.top, 4)
        .widgetURL(widgetURL(for: entry.note))
    }

    private func widgetURL(for note: Note?) -> URL? {
        guard let note else { return nil }
        return URL(string: "cache://edit?id=\(note.id.uuidString)")
    }

}

struct cacheWidget: Widget {
    let kind: String = "cacheWidget"

    var body: some WidgetConfiguration {
        let config = AppIntentConfiguration(kind: kind, intent: SelectNoteIntent.self, provider: Provider()) { entry in
            cacheWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Cache Note")
        .description("Show a selected note.")
        .supportedFamilies([.systemLarge])

        if #available(iOS 17.0, *) {
            return config.contentMarginsDisabled()
        }
        return config
    }
}
