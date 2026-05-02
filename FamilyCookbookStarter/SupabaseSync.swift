import Foundation

struct SupabaseProjectConfiguration: Sendable {
    let url: URL
    let anonKey: String
    let redirectURL: URL?
}

enum SupabaseSyncError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Supabase project settings are missing from the app configuration."
        }
    }
}

protocol CookbookSnapshotSyncing: Sendable {
    func fetchRemoteCookbookSnapshot() async throws -> RemoteCookbookSnapshot?
    func pullCookbookSnapshot() async throws -> CookbookSnapshot?
    func pushCookbookSnapshot(_ snapshot: CookbookSnapshot) async throws
    func handleIncomingURL(_ url: URL)
}

struct RemoteCookbookSnapshot: Sendable {
    let snapshot: CookbookSnapshot
    let updatedAt: Date
}

enum SupabaseSyncFactory {
    static func makeSyncService(configuration: AppConfiguration) -> CookbookSnapshotSyncing {
        makeSyncService(configuration: configuration, accessTokenProvider: nil)
    }

    static func makeSyncService(
        configuration: AppConfiguration,
        accessTokenProvider: SupabaseAccessTokenProviding?
    ) -> CookbookSnapshotSyncing {
        guard
            let url = configuration.supabaseURL,
            let anonKey = configuration.supabaseAnonKey,
            !anonKey.isEmpty
        else {
            return UnconfiguredSupabaseSyncService()
        }

        return makeConfiguredService(
            project: SupabaseProjectConfiguration(
                url: url,
                anonKey: anonKey,
                redirectURL: configuration.supabaseRedirectURL
            ),
            accessTokenProvider: accessTokenProvider
        )
    }

    private static func makeConfiguredService(
        project: SupabaseProjectConfiguration,
        accessTokenProvider: SupabaseAccessTokenProviding?
    ) -> CookbookSnapshotSyncing {
        SupabaseSyncService(project: project, accessTokenProvider: accessTokenProvider)
    }
}

private struct UnconfiguredSupabaseSyncService: CookbookSnapshotSyncing {
    let reason: SupabaseSyncError

    init(reason: SupabaseSyncError = .missingConfiguration) {
        self.reason = reason
    }

    func pullCookbookSnapshot() async throws -> CookbookSnapshot? {
        throw reason
    }

    func fetchRemoteCookbookSnapshot() async throws -> RemoteCookbookSnapshot? {
        throw reason
    }

    func pushCookbookSnapshot(_ snapshot: CookbookSnapshot) async throws {
        throw reason
    }

    func handleIncomingURL(_ url: URL) {}
}
private struct SharedCookbookRecord: Codable {
    let slug: String
    let title: String
    let payload: CookbookSnapshot
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case slug
        case title
        case payload
        case updatedAt = "updated_at"
    }
}

private final class SupabaseSyncService: CookbookSnapshotSyncing, @unchecked Sendable {
    private let project: SupabaseProjectConfiguration
    private let accessTokenProvider: SupabaseAccessTokenProviding?
    private let cookbookSlug = "family-cookbook"
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(project: SupabaseProjectConfiguration, accessTokenProvider: SupabaseAccessTokenProviding?) {
        self.project = project
        self.accessTokenProvider = accessTokenProvider

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func fetchRemoteCookbookSnapshot() async throws -> RemoteCookbookSnapshot? {
        let records = try await fetchSharedCookbookRecords()
        guard let record = records.first else {
            return nil
        }

        return RemoteCookbookSnapshot(snapshot: record.payload, updatedAt: record.updatedAt)
    }

    func pullCookbookSnapshot() async throws -> CookbookSnapshot? {
        let records = try await fetchSharedCookbookRecords()
        return records.first?.payload
    }

    func pushCookbookSnapshot(_ snapshot: CookbookSnapshot) async throws {
        let record = SharedCookbookRecord(
            slug: cookbookSlug,
            title: snapshot.title,
            payload: snapshot,
            updatedAt: snapshot.updatedAt
        )

        var components = URLComponents(url: restURL(path: "shared_cookbooks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "slug")
        ]

        var request = URLRequest(url: components.url!)
        try await applyCommonHeaders(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode([record])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    func handleIncomingURL(_ url: URL) {}

    private func fetchSharedCookbookRecords() async throws -> [SharedCookbookRecord] {
        var components = URLComponents(url: restURL(path: "shared_cookbooks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "slug", value: "eq.\(cookbookSlug)"),
            URLQueryItem(name: "select", value: "*")
        ]

        var request = URLRequest(url: components.url!)
        try await applyCommonHeaders(to: &request)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode([SharedCookbookRecord].self, from: data)
    }

    private func restURL(path: String) -> URL {
        project.url.appending(path: "/rest/v1/\(path)")
    }

    private func applyCommonHeaders(to request: inout URLRequest) async throws {
        request.setValue(project.anonKey, forHTTPHeaderField: "apikey")
        let accessToken = try await accessTokenProvider?.currentAccessToken()
        request.setValue("Bearer \(accessToken ?? project.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Supabase request failed."
            throw SupabaseHTTPError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

struct SupabaseHTTPError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? {
        "Supabase request failed (\(statusCode)): \(message)"
    }
}

@MainActor
@Observable
final class CookbookSyncCoordinator {
    struct SyncConflict: Identifiable {
        let id = UUID()
        let operation: SyncOperation
        let message: String
        let remoteSnapshot: CookbookSnapshot
        let localUpdatedAt: Date
        let remoteUpdatedAt: Date
    }

    enum SyncOperation: Equatable {
        case pull
        case push

        var presentParticiple: String {
            switch self {
            case .pull:
                "Pulling"
            case .push:
                "Pushing"
            }
        }

        var pastTense: String {
            switch self {
            case .pull:
                "Pulled"
            case .push:
                "Pushed"
            }
        }
    }

    enum SyncState: Equatable {
        case idle
        case syncing(SyncOperation)
        case succeeded(SyncOperation, String)
        case failed(SyncOperation, String)
    }

    private let coreDataStack: CoreDataStack
    private let syncService: CookbookSnapshotSyncing
    private var saveObserver: NSObjectProtocol?
    private var suppressNextDirtyMark = false
    private var autoPushTask: Task<Void, Never>?

    private(set) var state: SyncState = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncDirection: SyncOperation?
    private(set) var hasPendingLocalChanges = false
    private(set) var lastAutoPullAt: Date?
    private(set) var pendingConflict: SyncConflict?

    init(coreDataStack: CoreDataStack, syncService: CookbookSnapshotSyncing) {
        self.coreDataStack = coreDataStack
        self.syncService = syncService
        self.saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: coreDataStack.viewContext,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleContextSave()
            }
        }
    }

    func push() async {
        autoPushTask?.cancel()
        autoPushTask = nil
        state = .syncing(.push)

        do {
            let snapshot = try coreDataStack.makeSnapshot()
            if let conflict = try await detectPushConflict(localSnapshot: snapshot) {
                pendingConflict = conflict
                state = .idle
                return
            }
            try await syncService.pushCookbookSnapshot(snapshot)
            lastSyncedAt = Date()
            lastSyncDirection = .push
            hasPendingLocalChanges = false
            state = .succeeded(.push, "Uploaded the latest cookbook to Supabase.")
        } catch {
            state = .failed(.push, userFacingError(for: error, operation: .push))
        }
    }

    func pull() async {
        autoPushTask?.cancel()
        autoPushTask = nil
        state = .syncing(.pull)

        do {
            guard let remote = try await syncService.fetchRemoteCookbookSnapshot() else {
                state = .failed(.pull, "No shared cookbook was found in Supabase yet.")
                return
            }

            if let conflict = try detectPullConflict(remote: remote) {
                pendingConflict = conflict
                state = .idle
                return
            }

            suppressNextDirtyMark = true
            try coreDataStack.replaceCookbook(with: remote.snapshot)
            lastSyncedAt = Date()
            lastSyncDirection = .pull
            hasPendingLocalChanges = false
            state = .succeeded(.pull, "Downloaded the shared cookbook from Supabase.")
        } catch {
            state = .failed(.pull, userFacingError(for: error, operation: .pull))
        }
    }

    func clearMessage() {
        state = .idle
    }

    func clearConflict() {
        pendingConflict = nil
    }

    func pullSilently() async {
        guard !isSyncing else {
            return
        }

        do {
            guard let snapshot = try await syncService.pullCookbookSnapshot() else {
                return
            }

            suppressNextDirtyMark = true
            try coreDataStack.replaceCookbook(with: snapshot)
            lastSyncedAt = Date()
            lastSyncDirection = .pull
            lastAutoPullAt = Date()
            hasPendingLocalChanges = false
        } catch {
            // Silent sync failures should not interrupt app launch or sign-in.
        }
    }

    func autoPullIfNeeded() async {
        guard !isSyncing else {
            return
        }

        if let lastAutoPullAt, Date().timeIntervalSince(lastAutoPullAt) < 30 {
            return
        }

        await pullSilently()
    }

    func scheduleAutoPushIfNeeded() {
        guard hasPendingLocalChanges, !isSyncing else {
            return
        }

        autoPushTask?.cancel()
        autoPushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }

            guard let self, self.hasPendingLocalChanges, !self.isSyncing else {
                return
            }

            await self.pushSilently()
        }
    }

    func cancelAutoPush() {
        autoPushTask?.cancel()
        autoPushTask = nil
    }

    func resolveConflictKeepingLocal() async {
        guard pendingConflict != nil else {
            return
        }

        pendingConflict = nil
        await push()
    }

    func resolveConflictUsingRemote() async {
        guard let conflict = pendingConflict else {
            return
        }

        pendingConflict = nil
        state = .syncing(.pull)

        do {
            suppressNextDirtyMark = true
            try coreDataStack.replaceCookbook(with: conflict.remoteSnapshot)
            lastSyncedAt = Date()
            lastSyncDirection = .pull
            hasPendingLocalChanges = false
            state = .succeeded(.pull, "Replaced local changes with the newer shared cookbook.")
        } catch {
            state = .failed(.pull, userFacingError(for: error, operation: .pull))
        }
    }

    var isSyncing: Bool {
        if case .syncing = state {
            return true
        }

        return false
    }

    var statusTitle: String {
        switch state {
        case .idle:
            return hasPendingLocalChanges ? "Changes Waiting to Sync" : "Shared Cookbook Ready"
        case .syncing(let operation):
            return "\(operation.presentParticiple) Changes"
        case .succeeded(let operation, _):
            return "\(operation.pastTense) Successfully"
        case .failed(let operation, _):
            return "\(operation.pastTense) Failed"
        }
    }

    var statusDetail: String {
        switch state {
        case .idle:
            if hasPendingLocalChanges {
                return lastSyncSummary(prefix: "Local changes are waiting to be pushed.")
            }
            return lastSyncSummary(prefix: "Your cookbook is ready across devices.")
        case .syncing(let operation):
            switch operation {
            case .pull:
                return "Downloading the shared cookbook from Supabase..."
            case .push:
                return "Uploading your latest cookbook changes to Supabase..."
            }
        case .succeeded(_, let message), .failed(_, let message):
            return message
        }
    }

    private func handleContextSave() {
        if suppressNextDirtyMark {
            suppressNextDirtyMark = false
            return
        }

        hasPendingLocalChanges = true
    }

    private func pushSilently() async {
        guard !isSyncing else {
            return
        }

        do {
            let snapshot = try coreDataStack.makeSnapshot()
            if let conflict = try await detectPushConflict(localSnapshot: snapshot) {
                pendingConflict = conflict
                autoPushTask = nil
                return
            }
            try await syncService.pushCookbookSnapshot(snapshot)
            lastSyncedAt = Date()
            lastSyncDirection = .push
            hasPendingLocalChanges = false
            autoPushTask = nil
        } catch {
            autoPushTask = nil
        }
    }

    private func detectPushConflict(localSnapshot: CookbookSnapshot) async throws -> SyncConflict? {
        guard let remote = try await syncService.fetchRemoteCookbookSnapshot() else {
            return nil
        }

        guard remote.updatedAt.timeIntervalSince(localSnapshot.updatedAt) > 1 else {
            return nil
        }

        return SyncConflict(
            operation: .push,
            message: "Another device has newer cookbook changes. Keep your local version or use the newer shared version instead.",
            remoteSnapshot: remote.snapshot,
            localUpdatedAt: localSnapshot.updatedAt,
            remoteUpdatedAt: remote.updatedAt
        )
    }

    private func detectPullConflict(remote: RemoteCookbookSnapshot) throws -> SyncConflict? {
        guard hasPendingLocalChanges else {
            return nil
        }

        let localSnapshot = try coreDataStack.makeSnapshot()
        guard abs(remote.updatedAt.timeIntervalSince(localSnapshot.updatedAt)) > 1 else {
            return nil
        }

        return SyncConflict(
            operation: .pull,
            message: "You have unsynced local edits and the shared cookbook is different. Choose which version to keep.",
            remoteSnapshot: remote.snapshot,
            localUpdatedAt: localSnapshot.updatedAt,
            remoteUpdatedAt: remote.updatedAt
        )
    }

    private func lastSyncSummary(prefix: String) -> String {
        guard let lastSyncedAt else {
            return prefix
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeTime = formatter.localizedString(for: lastSyncedAt, relativeTo: Date())

        if let lastSyncDirection {
            return "\(prefix) Last \(lastSyncDirection.pastTense.lowercased()) \(relativeTime)."
        }

        return "\(prefix) Last synced \(relativeTime)."
    }

    private func userFacingError(for error: Error, operation: SyncOperation) -> String {
        if let httpError = error as? SupabaseHTTPError {
            switch httpError.statusCode {
            case 401:
                return "Your session expired. Sign in again and try to \(operation == .pull ? "pull" : "push")."
            case 403:
                return "This account does not have permission to \(operation == .pull ? "read" : "write") the shared cookbook yet."
            case 404:
                return operation == .pull
                    ? "The shared cookbook could not be found in Supabase."
                    : "Supabase could not find the shared cookbook endpoint."
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
