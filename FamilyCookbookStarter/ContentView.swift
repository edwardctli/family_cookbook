import CoreData
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SupabaseAuthManager.self) private var authManager
    @Environment(CookbookSyncCoordinator.self) private var syncCoordinator
    @State private var selectedRecipeID: NSManagedObjectID?
    @State private var recipeColumnVisibility = NavigationSplitViewVisibility.automatic
    @State private var isPresentingProfileSheet = false
    @State private var isPresentingAuthSheet = false
    @State private var isPresentingAccountSheet = false
    @State private var authSheetMode: SupabaseAuthSheet.Mode = .signIn

    var body: some View {
        TabView {
            recipesRootView
                .tabItem {
                    Label("Recipes", systemImage: "book.closed")
                }

            NavigationStack {
                ActivityFeedView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            accountButton
                        }
                    }
            }
                .tabItem {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }

            NavigationStack {
                ShoppingListView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            accountButton
                        }
                    }
            }
            .tabItem {
                Label("Shopping", systemImage: "cart")
            }

            #if os(macOS) || targetEnvironment(macCatalyst)
            NavigationStack {
                AccountContent(
                    showsDoneButton: false,
                    authSheetMode: $authSheetMode,
                    isPresentingAuthSheet: $isPresentingAuthSheet
                )
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            #endif
        }
        .tint(.orange)
        .alert("Sync Status", isPresented: syncMessageBinding) {
            Button("OK") {
                dismissAlert()
            }
        } message: {
            Text(syncMessageText)
        }
        .alert("Sync Conflict", isPresented: conflictBinding, presenting: syncCoordinator.pendingConflict) { _ in
            Button("Use Shared Version", role: .destructive) {
                Task {
                    await syncCoordinator.resolveConflictUsingRemote()
                }
            }
            Button("Keep Local Version") {
                Task {
                    await syncCoordinator.resolveConflictKeepingLocal()
                }
            }
            Button("Cancel", role: .cancel) {
                syncCoordinator.clearConflict()
            }
        } message: { conflict in
            Text(conflict.message)
        }
        .modifier(DesktopTabViewStyleModifier())
        .task(id: authManager.needsProfileSetup) {
            if authManager.needsProfileSetup {
                isPresentingProfileSheet = true
            }
        }
        .onChange(of: syncCoordinator.hasPendingLocalChanges) { _, hasPendingChanges in
            guard authManager.state.isAuthenticated else {
                syncCoordinator.cancelAutoPush()
                return
            }

            if hasPendingChanges {
                syncCoordinator.scheduleAutoPushIfNeeded()
            } else {
                syncCoordinator.cancelAutoPush()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, authManager.state.isAuthenticated else {
                return
            }

            Task {
                await syncCoordinator.autoPullIfNeeded()
                syncCoordinator.scheduleAutoPushIfNeeded()
            }
        }
        .sheet(isPresented: $isPresentingProfileSheet) {
            ProfileNameSheet()
        }
        .sheet(isPresented: $isPresentingAuthSheet) {
            SupabaseAuthSheet(mode: authSheetMode)
        }
        .sheet(isPresented: $isPresentingAccountSheet) {
            AccountSheet(
                authSheetMode: $authSheetMode,
                isPresentingAuthSheet: $isPresentingAuthSheet
            )
        }
    }

    @ViewBuilder
    private var recipesRootView: some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        NavigationSplitView(columnVisibility: $recipeColumnVisibility) {
            RecipeListView(selectedRecipeID: $selectedRecipeID, usesSplitViewLayout: true)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            RecipeSplitDetailView(selectedRecipeID: $selectedRecipeID)
        }
        .navigationSplitViewStyle(.balanced)
        #else
        NavigationStack {
            RecipeListView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        accountButton
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var accountButton: some View {
        switch authManager.state {
        case .signedIn:
            Button {
                isPresentingAccountSheet = true
            } label: {
                Label("Profile", systemImage: "person.crop.circle")
            }
        case .signedOut, .authenticating, .missingConfiguration:
            Button("Sign In") {
                authSheetMode = .signIn
                isPresentingAuthSheet = true
            }
        }
    }

    private var syncMessageBinding: Binding<Bool> {
        Binding(
            get: {
                if syncCoordinator.pendingConflict != nil {
                    return false
                }

                if authManager.message != nil {
                    return true
                }

                switch syncCoordinator.state {
                case .succeeded, .failed:
                    return true
                case .idle, .syncing:
                    return false
                }
            },
            set: { newValue in
                if !newValue {
                    dismissAlert()
                }
            }
        )
    }

    private var syncMessageText: String {
        if let message = authManager.message {
            return message
        }

        switch syncCoordinator.state {
        case .succeeded(_, let message), .failed(_, let message):
            return message
        case .idle:
            return ""
        case .syncing:
            return syncCoordinator.statusDetail
        }
    }

    private func dismissAlert() {
        authManager.clearMessage()
        syncCoordinator.clearMessage()
    }

    private var conflictBinding: Binding<Bool> {
        Binding(
            get: { syncCoordinator.pendingConflict != nil },
            set: { newValue in
                if !newValue {
                    syncCoordinator.clearConflict()
                }
            }
        )
    }
}

private struct DesktopTabViewStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if #available(iOS 18.0, macOS 15.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(FamilyCookbookPreview.container)
        .environment(\.managedObjectContext, FamilyCookbookCoreDataPreview.stack.viewContext)
        .environment(SupabaseReadiness(configuration: .fromBundle()))
        .environment(SupabaseAuthManager(configuration: .fromBundle(), client: nil))
        .environment(
            CookbookSyncCoordinator(
                coreDataStack: FamilyCookbookCoreDataPreview.stack,
                syncService: SupabaseSyncFactory.makeSyncService(configuration: .fromBundle())
            )
        )
}

private struct SupabaseAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseAuthManager.self) private var authManager
    @Environment(CookbookSyncCoordinator.self) private var syncCoordinator
    @State private var mode: Mode
    @State private var email = ""
    @State private var password = ""

    init(mode: Mode = .signIn) {
        _mode = State(initialValue: mode)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn:
                "Sign In"
            case .signUp:
                "Create Account"
            }
        }

        var buttonTitle: String {
            switch self {
            case .signIn:
                "Sign In"
            case .signUp:
                "Create Account"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
#if !os(macOS)
                    .keyboardType(.emailAddress)
#endif
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.buttonTitle) {
                        submit()
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            }
        }
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            switch mode {
            case .signIn:
                await authManager.signIn(email: trimmedEmail, password: password)
            case .signUp:
                await authManager.signUp(email: trimmedEmail, password: password)
            }

            if authManager.state.isAuthenticated {
                await syncCoordinator.pullSilently()
                dismiss()
            }
        }
    }
}

private struct ProfileNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseAuthManager.self) private var authManager
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Profile Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    Text("This is the name shown in the app instead of your email address.")
                }
            }
            .navigationTitle("Your Name")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !authManager.needsProfileSetup {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        submit()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                displayName = authManager.displayName ?? ""
            }
        }
    }

    private func submit() {
        Task {
            await authManager.saveProfile(displayName: displayName)
            if !authManager.needsProfileSetup {
                dismiss()
            }
        }
    }
}

private struct AccountSheet: View {
    @Binding var authSheetMode: SupabaseAuthSheet.Mode
    @Binding var isPresentingAuthSheet: Bool

    var body: some View {
        AccountContent(
            showsDoneButton: true,
            authSheetMode: $authSheetMode,
            isPresentingAuthSheet: $isPresentingAuthSheet
        )
    }
}

private struct AccountContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SupabaseAuthManager.self) private var authManager
    @Environment(CookbookSyncCoordinator.self) private var syncCoordinator
    @State private var displayName = ""
    @State private var isSavingProfile = false
    let showsDoneButton: Bool
    @Binding var authSheetMode: SupabaseAuthSheet.Mode
    @Binding var isPresentingAuthSheet: Bool

    var body: some View {
        Form {
            if authManager.state.isAuthenticated {
                Section("Profile") {
                    TextField("Display Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    if let email = authManager.emailAddress {
                        LabeledContent("Email", value: email)
                            .font(.subheadline)
                    }
                }

                Section("Sync") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(syncCoordinator.statusTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(syncCoordinator.statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Pull from Shared Cookbook") {
                        Task {
                            await syncCoordinator.pull()
                        }
                    }
                    .disabled(syncCoordinator.isSyncing)

                    Button("Push Local Changes") {
                        Task {
                            await syncCoordinator.push()
                        }
                    }
                    .disabled(syncCoordinator.isSyncing)
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authManager.signOut()
                            displayName = ""
                        }
                    }
                }
            } else {
                Section("Account") {
                    Text("Sign in or create an account to sync this cookbook across devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Sign In") {
                        authSheetMode = .signIn
                        presentAuthSheet()
                    }

                    Button("Create Account") {
                        authSheetMode = .signUp
                        presentAuthSheet()
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }

            if authManager.state.isAuthenticated {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(isSavingProfile || !hasProfileChanges)
                }
            }
        }
        .onAppear {
            displayName = authManager.displayName ?? ""
        }
    }

    private var hasProfileChanges: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines) != (authManager.displayName ?? "")
    }

    private func saveProfile() {
        isSavingProfile = true
        Task {
            await authManager.saveProfile(displayName: displayName)
            await MainActor.run {
                isSavingProfile = false
            }
        }
    }

    private func presentAuthSheet() {
        if showsDoneButton {
            dismiss()
        }
        isPresentingAuthSheet = true
    }
}

private struct RecipeSplitDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Binding var selectedRecipeID: NSManagedObjectID?

    var body: some View {
        Group {
            if let selectedRecipe = selectedRecipe {
                NavigationStack {
                    CDRecipeDetailView(recipe: selectedRecipe)
                }
            } else {
                ContentUnavailableView(
                    "Select a Recipe",
                    systemImage: "book.closed",
                    description: Text("Choose a recipe from the sidebar to see ingredients, steps, and cook history.")
                )
            }
        }
    }

    private var selectedRecipe: CDRecipe? {
        guard let selectedRecipeID else {
            return nil
        }

        return try? managedObjectContext.existingObject(with: selectedRecipeID) as? CDRecipe
    }
}
