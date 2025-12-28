import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import CryptoKit

final class SharedStore {
    static let shared = SharedStore()

    static let appGroupID = "group.me.johnstonliu.cache"

    private let queue = DispatchQueue(label: "SharedStore.queue")
    private let notesKey = "notes"
    private let historyKey = "noteHistory"
    private var reloadWorkItem: DispatchWorkItem?
    private var historyReloadWorkItem: DispatchWorkItem?

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupID)
    }

    func listNotes() -> [Note] {
        queue.sync {
            loadNotes().sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func getNote(id: UUID) -> Note? {
        queue.sync {
            loadNotes().first { $0.id == id }
        }
    }

    func createNote(attributedText: NSAttributedString = NSAttributedString(string: "")) -> UUID {
        queue.sync {
            var notes = loadNotes()
            let now = Date()
            let note = Note(id: UUID(), attributedText: attributedText, updatedAt: now)
            notes.append(note)
            saveNotes(notes)
            return note.id
        }
    }

    func updateNote(id: UUID, attributedText: NSAttributedString) {
        queue.sync {
            var notes = loadNotes()
            if let index = notes.firstIndex(where: { $0.id == id }) {
                let previous = notes[index]
                let now = Date()
                notes[index].rtfData = RichTextCodec.rtfData(from: attributedText)
                notes[index].plainText = attributedText.string
                notes[index].updatedAt = now
                saveNotes(notes)
                maybeSaveHistory(previous: previous, updated: notes[index], now: now)
            }
        }
    }

    func deleteNote(id: UUID) {
        queue.sync {
            var notes = loadNotes()
            notes.removeAll { $0.id == id }
            saveNotes(notes)
            deleteHistory(for: id)
        }
    }

    func listHistory(for noteID: UUID) -> [NoteHistoryEntry] {
        queue.sync {
            loadHistory().filter { $0.noteID == noteID }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func deleteHistoryEntry(id: UUID) {
        queue.sync {
            var history = loadHistory()
            history.removeAll { $0.id == id }
            saveHistory(history)
        }
    }

    func clearHistory(for noteID: UUID) {
        queue.sync {
            var history = loadHistory()
            history.removeAll { $0.noteID == noteID }
            saveHistory(history)
        }
    }

    private func loadNotes() -> [Note] {
        guard let data = defaults?.data(forKey: notesKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([Note].self, from: data)
        } catch {
            return []
        }
    }

    private func saveNotes(_ notes: [Note]) {
        do {
            let data = try JSONEncoder().encode(notes)
            defaults?.set(data, forKey: notesKey)
            reloadWidgetsDebounced()
        } catch {
            // No-op: keep storage resilient to encoding errors.
        }
    }

    private func loadHistory() -> [NoteHistoryEntry] {
        guard let data = defaults?.data(forKey: historyKey) else {
            return []
        }
        return (try? JSONDecoder().decode([NoteHistoryEntry].self, from: data)) ?? []
    }

    private func saveHistory(_ history: [NoteHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(history)
            defaults?.set(data, forKey: historyKey)
        } catch {
            // No-op: keep storage resilient to encoding errors.
        }
    }

    private func maybeSaveHistory(previous: Note, updated: Note, now: Date) {
        let history = loadHistory().filter { $0.noteID == updated.id }
        let latest = history.max(by: { $0.createdAt < $1.createdAt })

        let contentHash = hashData(updated.rtfData)
        if let latest, latest.contentHash == contentHash {
            return
        }

        let minInterval: TimeInterval = 60 * 10
        let lastDate = latest?.createdAt ?? .distantPast
        let lengthDelta = abs(updated.plainText.count - (latest?.plainText.count ?? 0))
        let shouldSnapshot = now.timeIntervalSince(lastDate) >= minInterval || lengthDelta >= 50
        if !shouldSnapshot {
            return
        }

        var allHistory = loadHistory()
        let entry = NoteHistoryEntry(
            id: UUID(),
            noteID: updated.id,
            rtfData: updated.rtfData,
            plainText: updated.plainText,
            createdAt: now,
            contentHash: contentHash
        )
        allHistory.append(entry)

        let pruned = pruneHistory(allHistory, for: updated.id)
        saveHistory(pruned)
    }

    private func pruneHistory(_ history: [NoteHistoryEntry], for noteID: UUID) -> [NoteHistoryEntry] {
        let limit = 20
        let other = history.filter { $0.noteID != noteID }
        let mine = history.filter { $0.noteID == noteID }.sorted { $0.createdAt > $1.createdAt }
        let kept = Array(mine.prefix(limit))
        return other + kept
    }

    private func deleteHistory(for noteID: UUID) {
        var history = loadHistory()
        history.removeAll { $0.noteID == noteID }
        saveHistory(history)
    }

    private func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func reloadWidgetsDebounced() {
        #if canImport(WidgetKit)
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
        #endif
    }
}
