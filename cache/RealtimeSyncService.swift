import Foundation
import Combine
import Supabase

@MainActor
final class RealtimeSyncService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient?
    private var channel: RealtimeChannelV2?
    private var subscribeTask: Task<Void, Never>?
    private var eventTasks: [Task<Void, Never>] = []
    private var debounceTask: Task<Void, Never>?

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseService.client
    }

    func start(onChange: @escaping @MainActor () async -> Void) {
        guard channel == nil, subscribeTask == nil else { return }
        guard let client else { return }

        subscribeTask = Task { @MainActor [weak self, client] in
            do {
                let session = try await client.auth.session
                let userID = session.user.id
                let filter: RealtimePostgresFilter = .eq("user_id", value: userID)
                let channel = client.channel("capache-sync-\(userID.uuidString)")

                let noteChanges = channel.postgresChange(AnyAction.self, table: "notes", filter: filter)
                let folderChanges = channel.postgresChange(AnyAction.self, table: "folders", filter: filter)
                let historyChanges = channel.postgresChange(AnyAction.self, table: "note_history", filter: filter)

                self?.channel = channel
                self?.eventTasks = [
                    self?.listen(to: noteChanges, onChange: onChange),
                    self?.listen(to: folderChanges, onChange: onChange),
                    self?.listen(to: historyChanges, onChange: onChange),
                ].compactMap { $0 }

                try await channel.subscribeWithError()
                self?.errorMessage = nil
                self?.isActive = true
            } catch {
                if SupabaseSessionInvalidation.isBenignCancellation(error) {
                    self?.isActive = false
                    self?.subscribeTask = nil
                    return
                }

                if SupabaseSessionInvalidation.postIfNeeded(for: error) {
                    self?.errorMessage = "Your sync account is no longer available. Sign in again to resume syncing."
                } else {
                    self?.errorMessage = error.localizedDescription
                }
                self?.isActive = false
                self?.subscribeTask = nil
            }
        }
    }

    func stop() {
        subscribeTask?.cancel()
        eventTasks.forEach { $0.cancel() }
        debounceTask?.cancel()

        let channel = channel
        let client = client
        subscribeTask = nil
        eventTasks = []
        debounceTask = nil
        self.channel = nil
        isActive = false

        if let channel, let client {
            Task {
                await client.removeChannel(channel)
            }
        }
    }

    private func listen(
        to stream: AsyncStream<AnyAction>,
        onChange: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await _ in stream {
                self?.scheduleReload(onChange: onChange)
            }
        }
    }

    private func scheduleReload(onChange: @escaping @MainActor () async -> Void) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                await onChange()
                self?.debounceTask = nil
            } catch {
                self?.debounceTask = nil
            }
        }
    }
}
