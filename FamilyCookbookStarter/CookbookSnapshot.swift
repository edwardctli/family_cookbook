import Foundation

struct CookbookSnapshot: Codable {
    let title: String
    let ownerName: String
    let updatedAt: Date
    let recipes: [RecipeSnapshot]
    let shoppingItems: [ShoppingListItemSnapshot]

    enum CodingKeys: String, CodingKey {
        case title
        case ownerName
        case updatedAt
        case recipes
        case shoppingItems
    }

    init(
        title: String,
        ownerName: String,
        updatedAt: Date,
        recipes: [RecipeSnapshot],
        shoppingItems: [ShoppingListItemSnapshot]
    ) {
        self.title = title
        self.ownerName = ownerName
        self.updatedAt = updatedAt
        self.recipes = recipes
        self.shoppingItems = shoppingItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        recipes = try container.decode([RecipeSnapshot].self, forKey: .recipes)
        shoppingItems = try container.decodeIfPresent([ShoppingListItemSnapshot].self, forKey: .shoppingItems) ?? []
    }
}

struct RecipeSnapshot: Codable, Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let familyOwner: String
    let isFavorite: Bool
    let tags: [String]
    let sortOrder: Int32
    let createdAt: Date
    let updatedAt: Date
    let ingredients: [IngredientSnapshot]
    let steps: [RecipeStepSnapshot]
    let logs: [CookLogSnapshot]
}

struct IngredientSnapshot: Codable, Identifiable {
    let id: UUID
    let amount: String
    let name: String
    let sortOrder: Int32
}

struct RecipeStepSnapshot: Codable, Identifiable {
    let id: UUID
    let title: String
    let instruction: String
    let sortOrder: Int32
}

struct CookLogSnapshot: Codable, Identifiable {
    let id: UUID
    let cookedOn: Date
    let cookName: String
    let rating: Int16
    let mood: String
    let tweakSummary: String
    let notes: String
    let nextTimeNote: String
    let createdAt: Date
    let updatedAt: Date
    let photos: [CookPhotoSnapshot]
    let observations: [StepObservationSnapshot]
}

struct CookPhotoSnapshot: Codable, Identifiable {
    let id: UUID
    let stage: String
    let caption: String
    let imageData: Data?
    let sortOrder: Int32
}

struct StepObservationSnapshot: Codable, Identifiable {
    let id: UUID
    let stepTitle: String
    let note: String
    let sortOrder: Int32
}

struct ShoppingListItemSnapshot: Codable, Identifiable {
    let id: UUID
    let itemName: String
    let amountText: String
    let sourceRecipeTitle: String
    let note: String
    let isChecked: Bool
    let sortOrder: Int32
    let createdAt: Date
    let updatedAt: Date
}
