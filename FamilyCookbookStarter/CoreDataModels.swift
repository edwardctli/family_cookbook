import CoreData
import Foundation

@objc(CDCookbook)
final class CDCookbook: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDCookbook> {
        NSFetchRequest<CDCookbook>(entityName: "CDCookbook")
    }

    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var ownerName: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var recipes: Set<CDRecipe>?
    @NSManaged var shoppingItems: Set<CDShoppingListItem>?

    var sortedRecipes: [CDRecipe] {
        (recipes ?? []).sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var sortedShoppingItems: [CDShoppingListItem] {
        (shoppingItems ?? []).sorted {
            if $0.isChecked != $1.isChecked {
                return !$0.isChecked && $1.isChecked
            }

            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt > $1.createdAt
            }

            return $0.sortOrder < $1.sortOrder
        }
    }
}

@objc(CDRecipe)
final class CDRecipe: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDRecipe> {
        NSFetchRequest<CDRecipe>(entityName: "CDRecipe")
    }

    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var summaryText: String
    @NSManaged var familyOwner: String
    @NSManaged var isFavorite: Bool
    @NSManaged var tagsText: String
    @NSManaged var sortOrder: Int32
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var cookbook: CDCookbook?
    @NSManaged var ingredients: Set<CDIngredient>?
    @NSManaged var steps: Set<CDRecipeStep>?
    @NSManaged var logs: Set<CDCookLog>?

    var tags: [String] {
        get {
            tagsText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsText = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    var sortedIngredients: [CDIngredient] {
        (ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedSteps: [CDRecipeStep] {
        (steps ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedLogs: [CDCookLog] {
        (logs ?? []).sorted { $0.cookedOn > $1.cookedOn }
    }

    var latestLog: CDCookLog? {
        sortedLogs.first
    }
}

@objc(CDIngredient)
final class CDIngredient: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDIngredient> {
        NSFetchRequest<CDIngredient>(entityName: "CDIngredient")
    }

    @NSManaged var id: UUID
    @NSManaged var amount: String
    @NSManaged var name: String
    @NSManaged var sortOrder: Int32
    @NSManaged var recipe: CDRecipe?
}

@objc(CDRecipeStep)
final class CDRecipeStep: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDRecipeStep> {
        NSFetchRequest<CDRecipeStep>(entityName: "CDRecipeStep")
    }

    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var instructionText: String
    @NSManaged var sortOrder: Int32
    @NSManaged var recipe: CDRecipe?
}

@objc(CDCookLog)
final class CDCookLog: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDCookLog> {
        NSFetchRequest<CDCookLog>(entityName: "CDCookLog")
    }

    @NSManaged var id: UUID
    @NSManaged var cookedOn: Date
    @NSManaged var cookName: String
    @NSManaged var rating: Int16
    @NSManaged var mood: String
    @NSManaged var tweakSummary: String
    @NSManaged var notes: String
    @NSManaged var nextTimeNote: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var recipe: CDRecipe?
    @NSManaged var photos: Set<CDCookPhoto>?
    @NSManaged var observations: Set<CDStepObservation>?

    var sortedPhotos: [CDCookPhoto] {
        (photos ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedObservations: [CDStepObservation] {
        (observations ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

@objc(CDCookPhoto)
final class CDCookPhoto: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDCookPhoto> {
        NSFetchRequest<CDCookPhoto>(entityName: "CDCookPhoto")
    }

    @NSManaged var id: UUID
    @NSManaged var stage: String
    @NSManaged var caption: String
    @NSManaged var imageData: Data?
    @NSManaged var sortOrder: Int32
    @NSManaged var log: CDCookLog?
}

@objc(CDStepObservation)
final class CDStepObservation: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDStepObservation> {
        NSFetchRequest<CDStepObservation>(entityName: "CDStepObservation")
    }

    @NSManaged var id: UUID
    @NSManaged var stepTitle: String
    @NSManaged var note: String
    @NSManaged var sortOrder: Int32
    @NSManaged var log: CDCookLog?
}

@objc(CDShoppingListItem)
final class CDShoppingListItem: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDShoppingListItem> {
        NSFetchRequest<CDShoppingListItem>(entityName: "CDShoppingListItem")
    }

    @NSManaged var id: UUID
    @NSManaged var itemName: String
    @NSManaged var amountText: String
    @NSManaged var sourceRecipeTitle: String
    @NSManaged var note: String
    @NSManaged var isChecked: Bool
    @NSManaged var sortOrder: Int32
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var cookbook: CDCookbook?
}

extension CDCookbook {
    static func makeDefault(in context: NSManagedObjectContext) -> CDCookbook {
        let cookbook = CDCookbook(context: context)
        cookbook.id = UUID()
        cookbook.title = "Family Cookbook"
        cookbook.ownerName = ""
        cookbook.createdAt = .now
        cookbook.updatedAt = .now
        return cookbook
    }
}
