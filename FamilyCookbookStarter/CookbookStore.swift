import Foundation
import SwiftData

@MainActor
enum FamilyCookbookData {
    static func seedIfNeeded(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<Recipe>()
        descriptor.fetchLimit = 1

        guard try context.fetch(descriptor).isEmpty else {
            return
        }

        for recipe in sampleRecipes {
            context.insert(recipe)
        }

        try context.save()
    }

    static var sampleRecipes: [Recipe] {
        [
        Recipe(
            title: "Sunday Red Sauce",
            summary: "A slow-simmered family tomato sauce with meatballs and room for iteration.",
            familyOwner: "Dad",
            isFavorite: true,
            tags: ["Family Classic", "Weekend", "Freezer Friendly"],
            ingredients: [
                Ingredient(amount: "2 tbsp", name: "olive oil"),
                Ingredient(amount: "1", name: "yellow onion, diced"),
                Ingredient(amount: "4 cloves", name: "garlic"),
                Ingredient(amount: "2 cans", name: "crushed tomatoes"),
                Ingredient(amount: "12", name: "meatballs")
            ],
            steps: [
                RecipeStep(title: "Build the base", instruction: "Saute onion in olive oil until soft, then stir in garlic."),
                RecipeStep(title: "Simmer", instruction: "Add tomatoes and simmer gently for 45 to 60 minutes."),
                RecipeStep(title: "Finish", instruction: "Add meatballs and cook until warmed through.")
            ],
            logs: [
                CookLog(
                    cookedOn: .now.addingTimeInterval(-86_400 * 6),
                    cookName: "Edward",
                    rating: 5,
                    mood: "Comforting",
                    tweakSummary: "Added chili flakes and simmered 15 minutes longer.",
                    notes: "Sauce tasted deeper after the longer simmer. Next time I would use a little less salt in the meatballs.",
                    nextTimeNote: "Try fresh basil right before serving.",
                    photos: [
                        CookPhoto(stage: "Prep", caption: "Aromatics ready to go.", imageData: Data()),
                        CookPhoto(stage: "Simmer", caption: "Color looked right at the 50-minute mark.", imageData: Data())
                    ],
                    observations: [
                        StepObservation(stepTitle: "Build the base", note: "Needed a wider pot so the onions browned less."),
                        StepObservation(stepTitle: "Simmer", note: "Best texture showed up after about 55 minutes.")
                    ]
                )
            ]
        ),
        Recipe(
            title: "Crispy Salmon Rice Bowls",
            summary: "Weeknight bowls with salmon, cucumber, rice, and spicy mayo.",
            familyOwner: "You",
            isFavorite: false,
            tags: ["Weeknight", "High Protein", "Fast"],
            ingredients: [
                Ingredient(amount: "2 fillets", name: "salmon"),
                Ingredient(amount: "2 cups", name: "cooked rice"),
                Ingredient(amount: "1", name: "cucumber"),
                Ingredient(amount: "2 tbsp", name: "mayo"),
                Ingredient(amount: "1 tsp", name: "sriracha")
            ],
            steps: [
                RecipeStep(title: "Cook the salmon", instruction: "Roast or pan-sear until crisp on the outside."),
                RecipeStep(title: "Mix the sauce", instruction: "Combine mayo and sriracha."),
                RecipeStep(title: "Assemble bowls", instruction: "Layer rice, salmon, cucumber, and sauce.")
            ],
            logs: [
                CookLog(
                    cookedOn: .now.addingTimeInterval(-86_400 * 2),
                    cookName: "Mom",
                    rating: 4,
                    mood: "Fresh",
                    tweakSummary: "Used air fryer instead of skillet.",
                    notes: "Texture was better and cleanup was easier. Rice needed more seasoning.",
                    nextTimeNote: "Add avocado and furikake.",
                    photos: [
                        CookPhoto(stage: "Plated", caption: "This version looked the most balanced so far.", imageData: Data())
                    ],
                    observations: [
                        StepObservation(stepTitle: "Cook the salmon", note: "Air fryer made the edges extra crisp in 8 minutes.")
                    ]
                )
            ]
        )
        ]
    }
}

enum FamilyCookbookPreview {
    @MainActor
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Recipe.self, configurations: configuration)
        try! FamilyCookbookData.seedIfNeeded(in: container.mainContext)
        return container
    }()
}
