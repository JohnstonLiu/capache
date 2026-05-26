import Foundation

enum NoteExportService {
    static func exportLocalData(
        from store: SharedStore = .shared,
        to exportDirectory: URL? = nil
    ) throws -> URL {
        let payload = NoteExportPayload(
            exportedAt: Date(),
            notes: store.listNotes(),
            folders: store.listFolders(),
            history: store.listAllHistory()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(payload)
        let directory = exportDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Capache Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory
            .appendingPathComponent("capache-export-\(fileTimestamp()).json", isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct NoteExportPayload: Encodable {
    let schemaVersion = 1
    let exportedAt: Date
    let notes: [Note]
    let folders: [Folder]
    let history: [NoteHistoryEntry]
}
