import CoreData
import SwiftUI

struct ActivityFeedView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SupabaseAuthManager.self) private var authManager
    @Environment(CookbookSyncCoordinator.self) private var syncCoordinator
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDRecipe.title, ascending: true)], animation: .default)
    private var recipes: FetchedResults<CDRecipe>

    private var recentLogs: [(recipe: CDRecipe, log: CDCookLog)] {
        recipes
            .flatMap { recipe in
                recipe.sortedLogs.map { (recipe: recipe, log: $0) }
            }
            .sorted { $0.log.cookedOn > $1.log.cookedOn }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Family Cooking")
                        .font(.largeTitle.bold())
                    Text("A timeline of what people actually made, changed, and learned.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Recent Logs") {
                if recentLogs.isEmpty {
                    ContentUnavailableView("No Activity Yet", systemImage: "clock.arrow.circlepath", description: Text("Cook a recipe and log what changed to populate the activity feed."))
                } else {
                    ForEach(recentLogs, id: \.log.objectID) { item in
                        NavigationLink {
                            CDCookLogDetailView(recipeTitle: item.recipe.title, log: item.log)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.recipe.title)
                                    .font(.headline)
                                Text("\(item.log.cookName) cooked this on \(item.log.cookedOn.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.log.tweakSummary)
                                    .font(.subheadline)
                                Text(item.log.nextTimeNote)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteLog(item.log, from: item.recipe)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity")
        .refreshable {
            guard authManager.state.isAuthenticated else {
                return
            }

            await syncCoordinator.pullSilently()
        }
    }

    private func deleteLog(_ log: CDCookLog, from recipe: CDRecipe) {
        managedObjectContext.delete(log)
        recipe.updatedAt = .now
        try? managedObjectContext.save()
    }
}

#Preview {
    NavigationStack {
        ActivityFeedView()
    }
    .environment(\.managedObjectContext, FamilyCookbookCoreDataPreview.stack.viewContext)
}
