import CryptoKit
import Foundation

enum NoteSyncResolver {
    struct Plan {
        var notesToUpload: [Note] = []
        var remoteNotesToCache: [Note] = []
        var localNotesToKeep: [Note] = []
    }

    static func plan(localNotes: [Note], remoteNotes: [Note], now: Date = Date()) -> Plan {
        _ = now
        var plan = Plan()
        let remoteByID = Dictionary(uniqueKeysWithValues: remoteNotes.map { ($0.id, $0) })

        for local in localNotes {
            guard local.isCloudSyncEnabled else {
                plan.localNotesToKeep.append(local.withoutLocalSyncState())
                continue
            }

            guard let remote = remoteByID[local.id] else {
                if !local.hasSyncBaseline {
                    plan.notesToUpload.append(local.withoutLocalSyncState())
                } else if local.hasUnsyncedLocalChanges {
                    plan.notesToUpload.append(local.withoutLocalSyncState())
                }
                continue
            }

            let localHash = fingerprint(local)
            let remoteHash = fingerprint(remote)
            if localHash == remoteHash {
                plan.remoteNotesToCache.append(markSynced(remote, hash: remoteHash, at: remote.updatedAt))
                continue
            }

            let baseHash = local.lastSyncedContentHash
            let localChanged = baseHash.map { $0 != localHash } ?? true
            let remoteChanged = baseHash.map { $0 != remoteHash } ?? true

            if localChanged && remoteChanged {
                if local.updatedAt >= remote.updatedAt {
                    plan.notesToUpload.append(local.withoutLocalSyncState())
                } else {
                    plan.remoteNotesToCache.append(markSynced(remote, hash: remoteHash, at: remote.updatedAt))
                }
            } else if localChanged {
                plan.notesToUpload.append(local.withoutLocalSyncState())
            } else {
                plan.remoteNotesToCache.append(markSynced(remote, hash: remoteHash, at: remote.updatedAt))
            }
        }

        return plan
    }

    static func conflictCopy(from source: Note, parentID: UUID, now: Date = Date()) -> Note {
        let displayTitle = source.displayTitle
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let copiedTitle: String
        if title.localizedCaseInsensitiveContains("conflict copy") {
            copiedTitle = title
        } else if title.isEmpty {
            copiedTitle = "Conflict copy - \(displayTitle)"
        } else {
            copiedTitle = "Conflict copy - \(title)"
        }

        return Note(
            id: conflictCopyID(for: source, parentID: parentID),
            title: copiedTitle,
            rtfData: source.rtfData,
            plainText: source.plainText,
            updatedAt: now,
            folderID: source.folderID,
            isPinned: source.isPinned,
            isArchived: source.isArchived,
            isConflict: true,
            conflictParentID: parentID,
            conflictCreatedAt: now
        )
    }

    static func duplicateConflictCopyIDs(in notes: [Note]) -> [UUID] {
        var keeperByKey: [String: Note] = [:]
        var duplicates: [UUID] = []

        for note in notes where note.isConflict {
            guard let parentID = note.conflictParentID else {
                continue
            }

            let key = "\(parentID.uuidString)|\(fingerprint(note))"
            guard let keeper = keeperByKey[key] else {
                keeperByKey[key] = note
                continue
            }

            if shouldKeepConflictCopy(note, over: keeper) {
                duplicates.append(keeper.id)
                keeperByKey[key] = note
            } else {
                duplicates.append(note.id)
            }
        }

        return duplicates
    }

    static func markSynced(_ note: Note, hash: String? = nil, at date: Date? = nil) -> Note {
        var note = note
        note.isCloudSyncEnabled = true
        note.lastSyncedContentHash = hash ?? fingerprint(note)
        note.lastSyncedAt = date ?? note.updatedAt
        return note
    }

    static func fingerprint(_ note: Note) -> String {
        let parts = [
            note.title,
            note.rtfData.base64EncodedString(),
            note.plainText,
            note.folderID?.uuidString ?? "",
            note.isPinned ? "1" : "0",
            note.isArchived ? "1" : "0",
            note.isConflict ? "1" : "0",
            note.conflictParentID?.uuidString ?? "",
        ]
        let canonical = parts.map(lengthPrefixed).joined(separator: "|")
        let data = Data(canonical.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    private static func conflictCopyID(for source: Note, parentID: UUID) -> UUID {
        let seed = "CapacheConflictCopy.v1|\(parentID.uuidString)|\(fingerprint(source))"
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15]
        ))
    }

    private static func shouldKeepConflictCopy(_ candidate: Note, over keeper: Note) -> Bool {
        if candidate.updatedAt != keeper.updatedAt {
            return candidate.updatedAt > keeper.updatedAt
        }
        return candidate.id.uuidString < keeper.id.uuidString
    }
}

private extension Note {
    var hasSyncBaseline: Bool {
        lastSyncedContentHash != nil || lastSyncedAt != nil
    }

    var hasUnsyncedLocalChanges: Bool {
        guard let lastSyncedContentHash else {
            return true
        }
        return NoteSyncResolver.fingerprint(self) != lastSyncedContentHash
    }

    func withoutLocalSyncState() -> Note {
        var note = self
        note.lastSyncedContentHash = nil
        note.lastSyncedAt = nil
        return note
    }
}
