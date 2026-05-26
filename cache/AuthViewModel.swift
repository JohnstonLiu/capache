import Combine
import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case unconfigured
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase
    @Published private(set) var userEmail: String?
    @Published private(set) var syncEnabled: Bool
    @Published var errorMessage: String?

    private let client: SupabaseClient?
    private let notificationCenter: NotificationCenter
    private let syncEnabledKey = "syncEnabled"
    private var cancellables: Set<AnyCancellable> = []
    private var isHandlingSessionInvalidation = false
    private static let localOnlyUITestingArgument = "--capache-ui-testing-local-only"

    init(client: SupabaseClient? = nil, notificationCenter: NotificationCenter = .default) {
        let resolvedClient = client ?? SupabaseService.client
        let forceLocalOnly = ProcessInfo.processInfo.arguments.contains(Self.localOnlyUITestingArgument)
        self.client = resolvedClient
        self.notificationCenter = notificationCenter
        self.syncEnabled = forceLocalOnly ? false : UserDefaults.standard.bool(forKey: syncEnabledKey)
        self.phase = resolvedClient == nil ? .unconfigured : .loading
        if forceLocalOnly {
            UserDefaults.standard.set(false, forKey: syncEnabledKey)
        }

        notificationCenter.publisher(for: SupabaseSessionInvalidation.didInvalidateSession)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleRemoteSessionInvalidation()
                }
            }
            .store(in: &cancellables)
    }

    var isSignedIn: Bool {
        phase == .signedIn
    }

    var canSync: Bool {
        syncEnabled && isSignedIn
    }

    func setSyncEnabled(_ enabled: Bool) {
        syncEnabled = enabled && isSignedIn
        UserDefaults.standard.set(syncEnabled, forKey: syncEnabledKey)
    }

    func refreshSession() async {
        guard let client else {
            phase = .unconfigured
            return
        }

        do {
            let user = try await client.auth.user()
            userEmail = user.email
            phase = .signedIn
        } catch {
            SupabaseSessionInvalidation.postIfNeeded(for: error, notificationCenter: notificationCenter)
            userEmail = nil
            phase = .signedOut
            setSyncEnabled(false)
        }
    }

    func sendCode(to email: String) async -> Bool {
        guard let client else {
            phase = .unconfigured
            return false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter an email address."
            return false
        }

        do {
            errorMessage = nil
            try await client.auth.signInWithOTP(email: trimmedEmail)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func verifyCode(email: String, token: String) async -> Bool {
        guard let client else {
            phase = .unconfigured
            return false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedToken.isEmpty else {
            errorMessage = "Enter the code from your email."
            return false
        }

        do {
            errorMessage = nil
            _ = try await verifyEmailToken(
                client: client,
                email: trimmedEmail,
                token: trimmedToken,
                allowedTypes: [.email, .magiclink, .signup]
            )
            await refreshSession()
            setSyncEnabled(true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendDeletionVerificationCode() async -> Bool {
        guard let client else {
            phase = .unconfigured
            return false
        }

        guard let email = userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !email.isEmpty else {
            errorMessage = "No signed-in email address is available."
            return false
        }

        do {
            errorMessage = nil
            try await client.auth.signInWithOTP(email: email, shouldCreateUser: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func verifyDeletionCode(_ token: String) async -> Bool {
        guard let client else {
            phase = .unconfigured
            return false
        }

        guard let email = userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !email.isEmpty else {
            errorMessage = "No signed-in email address is available."
            return false
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            errorMessage = "Enter the code from your email."
            return false
        }

        do {
            errorMessage = nil
            _ = try await verifyEmailToken(
                client: client,
                email: email,
                token: trimmedToken,
                allowedTypes: [.email, .magiclink]
            )
            await refreshSession()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        guard let client else {
            phase = .unconfigured
            return
        }

        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }

        userEmail = nil
        phase = .signedOut
        setSyncEnabled(false)
        SharedStore.shared.clearWidgetBackgroundRefreshCredentials()
    }

    private func handleRemoteSessionInvalidation() async {
        guard !isHandlingSessionInvalidation else { return }
        guard phase != .unconfigured else { return }

        isHandlingSessionInvalidation = true
        defer { isHandlingSessionInvalidation = false }

        SharedStore.shared.setAllNotesCloudSyncEnabled(false)
        await signOut()
        errorMessage = "Your sync account is no longer available. Sign in again to resume syncing."
    }

    private func verifyEmailToken(
        client: SupabaseClient,
        email: String,
        token: String,
        allowedTypes: [EmailOTPType]
    ) async throws -> AuthResponse {
        var lastError: Error?

        for type in allowedTypes {
            do {
                return try await client.auth.verifyOTP(email: email, token: token, type: type)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(
            domain: "CapacheAuth",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not verify the code."]
        )
    }
}
