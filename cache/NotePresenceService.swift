import Combine
import Foundation
import Supabase
#if canImport(UIKit)
import UIKit
#endif

struct NotePresencePeer: Identifiable, Equatable {
    let id: String
    let platform: String
}

@MainActor
final class NotePresenceService: ObservableObject {
    @Published private(set) var otherOpenDevices: [NotePresencePeer] = []
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient?
    private let deviceID = UUID().uuidString
    private var channel: RealtimeChannelV2?
    private var subscribeTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var presenceByDeviceID: [String: NotePresenceState] = [:]
    private var currentNoteID: UUID?

    var isOpenElsewhere: Bool {
        !otherOpenDevices.isEmpty
    }

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseService.client
    }

    func start(noteID: UUID) {
        guard currentNoteID != noteID || channel == nil else { return }
        stop()

        guard let client else { return }
        currentNoteID = noteID

        subscribeTask = Task { @MainActor [weak self, client] in
            guard let self else { return }

            do {
                let session = try await client.auth.session
                let channel = client.channel("capache-note-presence-\(session.user.id.uuidString)-\(noteID.uuidString)") { config in
                    config.presence.key = self.deviceID
                }
                let presenceStream = channel.presenceChange()

                self.channel = channel
                self.presenceTask = self.listen(to: presenceStream)

                try await channel.subscribeWithError()
                try await channel.track(NotePresenceState.current(deviceID: self.deviceID, noteID: noteID))
                self.errorMessage = nil
            } catch {
                if SupabaseSessionInvalidation.isBenignCancellation(error) {
                    self.clearPresenceState()
                    self.subscribeTask = nil
                    return
                }

                self.errorMessage = error.localizedDescription
                self.clearPresenceState()
                self.subscribeTask = nil
            }
        }
    }

    func stop() {
        subscribeTask?.cancel()
        presenceTask?.cancel()

        let channel = channel
        let client = client

        subscribeTask = nil
        presenceTask = nil
        self.channel = nil
        currentNoteID = nil
        clearPresenceState()

        if let channel, let client {
            Task {
                await channel.untrack()
                await client.removeChannel(channel)
            }
        }
    }

    private func listen(to stream: AsyncStream<any PresenceAction>) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await action in stream {
                self?.handle(action)
            }
        }
    }

    private func handle(_ action: any PresenceAction) {
        for presence in action.joins.values {
            guard let state = try? presence.decodeState(as: NotePresenceState.self) else {
                continue
            }
            guard let currentNoteID, state.deviceID != deviceID, state.noteID == currentNoteID else {
                continue
            }
            presenceByDeviceID[state.deviceID] = state
        }

        for presence in action.leaves.values {
            guard let state = try? presence.decodeState(as: NotePresenceState.self) else {
                continue
            }
            presenceByDeviceID[state.deviceID] = nil
        }

        otherOpenDevices = presenceByDeviceID.values
            .sorted { $0.openedAt < $1.openedAt }
            .map {
                NotePresencePeer(id: $0.deviceID, platform: $0.platform)
            }
    }

    private func clearPresenceState() {
        presenceByDeviceID = [:]
        otherOpenDevices = []
    }
}

private struct NotePresenceState: Codable, Equatable {
    let deviceID: String
    let platform: String
    let noteID: UUID
    let openedAt: TimeInterval

    static func current(deviceID: String, noteID: UUID) -> NotePresenceState {
        NotePresenceState(
            deviceID: deviceID,
            platform: platform,
            noteID: noteID,
            openedAt: Date().timeIntervalSince1970
        )
    }

    private static var platform: String {
#if targetEnvironment(macCatalyst)
        return "Mac"
#elseif os(iOS)
#if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
#else
        return "iOS"
#endif
#else
        return "Device"
#endif
    }
}
