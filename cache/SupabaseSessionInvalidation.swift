import Foundation
import Supabase

enum SupabaseSessionInvalidation {
    static let didInvalidateSession = Notification.Name("CapacheSupabaseSessionInvalidated")

    @discardableResult
    static func postIfNeeded(for error: Error, notificationCenter: NotificationCenter = .default) -> Bool {
        guard isSessionInvalidation(error) else { return false }
        notificationCenter.post(name: didInvalidateSession, object: error)
        return true
    }

    static func isSessionInvalidation(_ error: Error) -> Bool {
        if let authError = error as? AuthError {
            return isSessionInvalidation(authError)
        }

        if let functionsError = error as? FunctionsError {
            return isSessionInvalidation(functionsError)
        }

        if let postgrestError = error as? PostgrestError {
            return isSessionInvalidation(postgrestError)
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("auth session missing")
            || message.contains("session missing")
            || message.contains("session not found")
            || message.contains("session expired")
            || message.contains("refresh token")
            || message.contains("user not found")
            || message.contains("invalid jwt")
            || message.contains("bad jwt")
            || message.contains("jwt expired")
            || message.contains("no authorization")
            || message.contains("unauthorized")
    }

    static func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let message = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return message == "cancelled" || message == "canceled"
    }

    private static func isSessionInvalidation(_ error: AuthError) -> Bool {
        switch error {
        case .sessionMissing, .jwtVerificationFailed:
            return true
        case let .api(_, errorCode, _, response):
            return [
                .badJWT,
                .invalidJWT,
                .noAuthorization,
                .sessionExpired,
                .sessionNotFound,
                .refreshTokenNotFound,
                .refreshTokenAlreadyUsed,
                .userNotFound
            ].contains(errorCode) || [401, 403, 404].contains(response.statusCode)
        default:
            return false
        }
    }

    private static func isSessionInvalidation(_ error: FunctionsError) -> Bool {
        guard case let .httpError(code, _) = error else { return false }
        return [401, 403, 404].contains(code)
    }

    private static func isSessionInvalidation(_ error: PostgrestError) -> Bool {
        let code = error.code?.lowercased()
        let message = error.message.lowercased()
        let detail = error.detail?.lowercased() ?? ""

        if code == "pgrst301" || code == "42501" {
            return true
        }

        if code == "23503" && (message.contains("user_id") || detail.contains("auth.users")) {
            return true
        }

        return message.contains("invalid jwt")
            || message.contains("bad jwt")
            || message.contains("jwt expired")
            || message.contains("permission denied")
            || message.contains("auth.users")
    }
}
