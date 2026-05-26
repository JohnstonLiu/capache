import Foundation
import Supabase

enum SupabaseConfigurationError: LocalizedError {
    case missingURL
    case missingPublishableKey
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Set SUPABASE_URL in the app target build settings."
        case .missingPublishableKey:
            return "Set SUPABASE_PUBLISHABLE_KEY in the app target build settings."
        case .invalidURL(let value):
            return "SUPABASE_URL is not a valid URL: \(value)"
        }
    }
}

enum SupabaseConfig {
    static var urlString: String {
        stringValue(for: "SupabaseURL")
    }

    static var publishableKey: String {
        stringValue(for: "SupabasePublishableKey")
    }

    static var isConfigured: Bool {
        !isPlaceholder(urlString) && !isPlaceholder(publishableKey) && URL(string: urlString) != nil
    }

    static func makeClient() throws -> SupabaseClient {
        guard !isPlaceholder(urlString) else {
            throw SupabaseConfigurationError.missingURL
        }
        guard !isPlaceholder(publishableKey) else {
            throw SupabaseConfigurationError.missingPublishableKey
        }
        guard let url = URL(string: urlString) else {
            throw SupabaseConfigurationError.invalidURL(urlString)
        }

        return SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    private static func stringValue(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        value.isEmpty || value.contains("$(") || value.contains("YOUR_")
    }
}

enum SupabaseService {
    static let client: SupabaseClient? = try? SupabaseConfig.makeClient()
}
