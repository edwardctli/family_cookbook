import Foundation
import Observation

struct SupabaseUser: Codable, Sendable {
    let id: String
    let email: String?
}

struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int?
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }

    var emailAddress: String {
        user.email ?? "Signed In"
    }
}

private struct SupabaseProfileRecord: Codable {
    let id: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Int?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }

    var session: SupabaseSession? {
        guard
            let accessToken,
            let refreshToken,
            let user
        else {
            return nil
        }

        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            user: user
        )
    }
}

enum SupabaseAuthError: LocalizedError {
    case missingConfiguration
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Supabase auth is not configured in this app."
        case .emailConfirmationRequired:
            "Account created. Check your email to confirm the account, then sign in."
        }
    }
}

protocol SupabaseAccessTokenProviding: Sendable {
    func currentAccessToken() async throws -> String?
}

actor SupabaseSessionStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "FamilyCookbook.supabase.session") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> SupabaseSession? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    func save(_ session: SupabaseSession) throws {
        let data = try JSONEncoder().encode(session)
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

actor SupabaseAuthClient: SupabaseAccessTokenProviding {
    private let project: SupabaseProjectConfiguration
    private let sessionStore: SupabaseSessionStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(project: SupabaseProjectConfiguration, sessionStore: SupabaseSessionStore = SupabaseSessionStore()) {
        self.project = project
        self.sessionStore = sessionStore
    }

    func restoreSession() async -> SupabaseSession? {
        await sessionStore.load()
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let session = try await authenticate(
            path: "token",
            queryItems: [
                URLQueryItem(name: "grant_type", value: "password")
            ],
            body: [
                "email": email,
                "password": password
            ]
        )
        try await sessionStore.save(session)
        return session
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        let response = try await sendAuthRequest(
            path: "signup",
            body: [
                "email": email,
                "password": password
            ]
        )

        guard let session = response.session else {
            throw SupabaseAuthError.emailConfirmationRequired
        }

        try await sessionStore.save(session)
        return session
    }

    func signOut() async throws {
        let accessToken = try await currentAccessToken()

        guard let accessToken else {
            await sessionStore.clear()
            return
        }

        var request = URLRequest(url: authURL(path: "logout"))
        request.httpMethod = "POST"
        applyHeaders(to: &request, accessToken: accessToken)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
        } catch {
            // Always clear the local session so the app can cleanly re-authenticate.
            await sessionStore.clear()
            throw error
        }

        await sessionStore.clear()
    }

    func currentSession() async -> SupabaseSession? {
        await sessionStore.load()
    }

    func currentAccessToken() async throws -> String? {
        guard let session = await sessionStore.load() else {
            return nil
        }

        if sessionNeedsRefresh(session) {
            let refreshedSession = try await refreshSession(refreshToken: session.refreshToken)
            try await sessionStore.save(refreshedSession)
            return refreshedSession.accessToken
        }

        return session.accessToken
    }

    func fetchProfile() async throws -> String? {
        guard
            let session = await sessionStore.load(),
            let accessToken = try await currentAccessToken()
        else {
            return nil
        }

        var components = URLComponents(url: restURL(path: "profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
            URLQueryItem(name: "select", value: "id,display_name"),
            URLQueryItem(name: "limit", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyHeaders(to: &request, accessToken: accessToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let records = try decoder.decode([SupabaseProfileRecord].self, from: data)
        return records.first?.displayName
    }

    func saveProfile(displayName: String) async throws -> String {
        guard
            let session = await sessionStore.load(),
            let accessToken = try await currentAccessToken()
        else {
            throw SupabaseAuthError.missingConfiguration
        }

        let payload = [SupabaseProfileRecord(id: session.user.id, displayName: displayName)]
        var components = URLComponents(url: restURL(path: "profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "id")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        applyHeaders(to: &request, accessToken: accessToken)
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let records = try decoder.decode([SupabaseProfileRecord].self, from: data)
        return records.first?.displayName ?? displayName
    }

    private func authenticate(path: String, body: [String: String]) async throws -> SupabaseSession {
        try await authenticate(path: path, queryItems: [], body: body)
    }

    private func authenticate(
        path: String,
        queryItems: [URLQueryItem],
        body: [String: String]
    ) async throws -> SupabaseSession {
        let response = try await sendAuthRequest(path: path, queryItems: queryItems, body: body)

        guard let session = response.session else {
            throw SupabaseAuthError.missingConfiguration
        }

        return session
    }

    private func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let response = try await sendAuthRequest(
            path: "token",
            queryItems: [
                URLQueryItem(name: "grant_type", value: "refresh_token")
            ],
            body: [
                "refresh_token": refreshToken
            ]
        )

        guard let session = response.session else {
            throw SupabaseAuthError.missingConfiguration
        }

        return session
    }

    private func sendAuthRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: String]
    ) async throws -> SupabaseAuthResponse {
        var request = URLRequest(url: authURL(path: path, queryItems: queryItems))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request, accessToken: nil)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(SupabaseAuthResponse.self, from: data)
    }

    private func authURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: project.url.appending(path: "/auth/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func restURL(path: String) -> URL {
        project.url.appending(path: "/rest/v1/\(path)")
    }

    private func applyHeaders(to request: inout URLRequest, accessToken: String?) {
        request.setValue(project.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? project.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func sessionNeedsRefresh(_ session: SupabaseSession) -> Bool {
        guard let expiresAt = session.expiresAt else {
            return false
        }

        let refreshThreshold = Int(Date().timeIntervalSince1970) + 60
        return expiresAt <= refreshThreshold
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Supabase auth request failed."
            throw SupabaseHTTPError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

@MainActor
@Observable
final class SupabaseAuthManager {
    enum State: Equatable {
        case missingConfiguration
        case signedOut
        case authenticating
        case signedIn(email: String, displayName: String?)

        var isAuthenticated: Bool {
            if case .signedIn = self {
                return true
            }

            return false
        }

        var statusText: String {
            switch self {
            case .missingConfiguration:
                "Supabase auth needs configuration."
            case .signedOut:
                "Sign in to sync this cookbook with your wife."
            case .authenticating:
                "Contacting Supabase..."
            case .signedIn(let email, let displayName):
                if let displayName, !displayName.isEmpty {
                    "Signed in as \(displayName)"
                } else {
                    "Signed in as \(email)"
                }
            }
        }
    }

    private let client: SupabaseAuthClient?
    private(set) var state: State
    private(set) var message: String?

    init(configuration: AppConfiguration, client: SupabaseAuthClient?) {
        self.client = client
        self.state = configuration.isSupabaseConfigured ? .signedOut : .missingConfiguration
    }

    var displayName: String? {
        guard case .signedIn(_, let displayName) = state else {
            return nil
        }

        return displayName
    }

    var emailAddress: String? {
        guard case .signedIn(let email, _) = state else {
            return nil
        }

        return email
    }

    var needsProfileSetup: Bool {
        guard case .signedIn(_, let displayName) = state else {
            return false
        }

        return displayName?.isEmpty != false
    }

    func restoreSessionIfNeeded() async {
        guard case .signedOut = state, let client else {
            return
        }

        guard let session = await client.restoreSession() else {
            return
        }

        let displayName = try? await client.fetchProfile()
        state = .signedIn(email: session.emailAddress, displayName: displayName)
    }

    func signIn(email: String, password: String) async {
        guard let client else {
            state = .missingConfiguration
            return
        }

        state = .authenticating

        do {
            let session = try await client.signIn(email: email, password: password)
            let displayName = try? await client.fetchProfile()
            state = .signedIn(email: session.emailAddress, displayName: displayName)
            message = "Signed in and ready to sync."
        } catch {
            state = .signedOut
            message = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard let client else {
            state = .missingConfiguration
            return
        }

        state = .authenticating

        do {
            let session = try await client.signUp(email: email, password: password)
            let displayName = try? await client.fetchProfile()
            state = .signedIn(email: session.emailAddress, displayName: displayName)
            message = "Account created and signed in."
        } catch {
            state = .signedOut
            message = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else {
            state = .missingConfiguration
            return
        }

        do {
            try await client.signOut()
            state = .signedOut
            message = "Signed out."
        } catch {
            state = .signedOut
            message = error.localizedDescription
        }
    }

    func saveProfile(displayName: String) async {
        guard let client else {
            state = .missingConfiguration
            return
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            message = "Profile name cannot be empty."
            return
        }

        do {
            let storedName = try await client.saveProfile(displayName: trimmedName)
            if case .signedIn(let email, _) = state {
                state = .signedIn(email: email, displayName: storedName)
            }
            message = "Profile updated."
        } catch {
            message = error.localizedDescription
        }
    }

    func clearMessage() {
        message = nil
    }
}
