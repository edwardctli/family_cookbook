import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddLog = false

    let recipe: Recipe

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.title)
                        .font(.largeTitle.bold())

                    Text(recipe.summary)
                        .foregroundStyle(.secondary)

                    Text("Originally from \(recipe.familyOwner)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 8)
            }

            Section("Ingredients") {
                if recipe.ingredients.isEmpty {
                    Text("No ingredients yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.ingredients) { ingredient in
                        HStack {
                            Text(ingredient.amount)
                                .foregroundStyle(.secondary)
                            Text(ingredient.name)
                        }
                    }
                }
            }

            Section("Steps") {
                if recipe.steps.isEmpty {
                    Text("No steps yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recipe.steps.enumerated()), id: \.element.persistentModelID) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Step \(index + 1): \(step.title)")
                                .font(.headline)
                            Text(step.instruction)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Cook History") {
                if recipe.logs.isEmpty {
                    Text("No cook sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.logs.sorted(by: { $0.cookedOn > $1.cookedOn })) { log in
                        NavigationLink {
                            CookLogDetailView(recipeTitle: recipe.title, log: log)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(log.cookName)
                                    .font(.headline)
                                Text(log.cookedOn.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(log.tweakSummary)
                                    .font(.subheadline)
                                Text("Next time: \(log.nextTimeNote)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteLog(log)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    recipe.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: recipe.isFavorite ? "star.fill" : "star")
                }

                Button("Log Cook") {
                    showingAddLog = true
                }
            }

            ToolbarItem(placement: .bottomBar) {
                Button("Delete Recipe", role: .destructive) {
                    deleteRecipe()
                }
            }
        }
        .sheet(isPresented: $showingAddLog) {
            NewCookLogView(recipe: recipe)
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteLog(_ log: CookLog) {
        modelContext.delete(log)
        try? modelContext.save()
    }

    private func deleteRecipe() {
        modelContext.delete(recipe)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: FamilyCookbookData.sampleRecipes[0])
    }
    .modelContainer(FamilyCookbookPreview.container)
}
