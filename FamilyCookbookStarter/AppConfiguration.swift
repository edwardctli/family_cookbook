import Foundation
import Observation

struct AppConfiguration {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let supabaseRedirectURL: URL?

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        let rawSupabaseURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String
        let rawSupabaseAnonKey = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String
        let rawSupabaseRedirectURL = bundle.object(forInfoDictionaryKey: "SupabaseRedirectURL") as? String

        return AppConfiguration(
            supabaseURL: rawSupabaseURL.flatMap(URL.init(string:)),
            supabaseAnonKey: rawSupabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            supabaseRedirectURL: rawSupabaseRedirectURL.flatMap(URL.init(string:))
        )
    }

    var isSupabaseConfigured: Bool {
        supabaseURL != nil && !(supabaseAnonKey?.isEmpty ?? true)
    }
}

@MainActor
@Observable
final class SupabaseReadiness {
    enum State: Equatable {
        case missingConfiguration
        case ready

        var title: String {
            switch self {
            case .missingConfiguration:
                "Supabase Config Needed"
            case .ready:
                "Supabase Configured"
            }
        }

        var detail: String {
            switch self {
            case .missingConfiguration:
                "Add SupabaseURL, SupabaseAnonKey, and SupabaseRedirectURL to the app configuration."
            case .ready:
                "Supabase settings are present. Finish the database table setup, then you can sync this cookbook."
            }
        }
    }

    let configuration: AppConfiguration
    private(set) var state: State

    init(configuration: AppConfiguration) {
        self.configuration = configuration

        if !configuration.isSupabaseConfigured {
            state = .missingConfiguration
        } else {
            state = .ready
        }
    }
}
