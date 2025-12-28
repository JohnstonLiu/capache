import AppIntents

struct SelectNoteIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Note"
    static var description = IntentDescription("Choose which note to display.")

    @Parameter(title: "Note")
    var note: NoteEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$note)")
    }
}
