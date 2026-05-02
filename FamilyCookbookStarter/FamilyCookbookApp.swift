import CoreData
import SwiftUI

@main
struct FamilyCookbookApp: App {
    private let configuration: AppConfiguration
    @State private var supabaseReadiness: SupabaseReadiness
    @State private var authManager: SupabaseAuthManager
    @State private var syncCoordinator: CookbookSyncCoordinator
    private let coreDataStack: CoreDataStack
    private let syncService: CookbookSnapshotSyncing
    private let authClient: SupabaseAuthClient?

    init() {
        let configuration = AppConfiguration.fromBundle()
        self.configuration = configuration
        _supabaseReadiness = State(initialValue: SupabaseReadiness(configuration: configuration))
        authClient = Self.makeAuthClient(configuration: configuration)
        _authManager = State(initialValue: SupabaseAuthManager(configuration: configuration, client: authClient))
        syncService = SupabaseSyncFactory.makeSyncService(
            configuration: configuration,
            accessTokenProvider: authClient
        )

        do {
            coreDataStack = try Self.makeCoreDataStack()
        } catch {
            fatalError("Failed to set up app storage: \(error.localizedDescription)")
        }

        _syncCoordinator = State(initialValue: CookbookSyncCoordinator(coreDataStack: coreDataStack, syncService: syncService))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, coreDataStack.viewContext)
                .environment(supabaseReadiness)
                .environment(authManager)
                .environment(syncCoordinator)
                .task {
                    await authManager.restoreSessionIfNeeded()
                    if authManager.state.isAuthenticated {
                        await syncCoordinator.pullSilently()
                    }
                }
                .onOpenURL { url in
                    syncService.handleIncomingURL(url)
                }
        }
    }

    private static func makeCoreDataStack() throws -> CoreDataStack {
        let stack = try CoreDataStack()
        _ = try stack.ensureCookbook()
        try stack.importSampleDataIfNeeded(from: FamilyCookbookData.sampleRecipes)
        return stack
    }

    private static func makeAuthClient(configuration: AppConfiguration) -> SupabaseAuthClient? {
        guard
            let url = configuration.supabaseURL,
            let anonKey = configuration.supabaseAnonKey,
            !anonKey.isEmpty
        else {
            return nil
        }

        return SupabaseAuthClient(
            project: SupabaseProjectConfiguration(
                url: url,
                anonKey: anonKey,
                redirectURL: configuration.supabaseRedirectURL
            )
        )
    }
}
