import Foundation
import SwiftData

@Model
final class Recipe {
    var title: String
    var summary: String
    var familyOwner: String
    var isFavorite: Bool
    var tags: [String]
    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]
    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]
    @Relationship(deleteRule: .cascade, inverse: \CookLog.recipe)
    var logs: [CookLog]

    init(
        title: String,
        summary: String,
        familyOwner: String,
        isFavorite: Bool = false,
        tags: [String] = [],
        ingredients: [Ingredient] = [],
        steps: [RecipeStep] = [],
        logs: [CookLog] = []
    ) {
        self.title = title
        self.summary = summary
        self.familyOwner = familyOwner
        self.isFavorite = isFavorite
        self.tags = tags
        self.ingredients = ingredients
        self.steps = steps
        self.logs = logs
    }

    var latestLog: CookLog? {
        logs.sorted(by: { $0.cookedOn > $1.cookedOn }).first
    }
}

@Model
final class Ingredient {
    var amount: String
    var name: String
    var recipe: Recipe?

    init(amount: String, name: String) {
        self.amount = amount
        self.name = name
    }
}

@Model
final class RecipeStep {
    var title: String
    var instruction: String
    var recipe: Recipe?

    init(title: String, instruction: String) {
        self.title = title
        self.instruction = instruction
    }
}

@Model
final class CookLog {
    var cookedOn: Date
    var cookName: String
    var rating: Int
    var mood: String
    var tweakSummary: String
    var notes: String
    var nextTimeNote: String
    var recipe: Recipe?
    @Relationship(deleteRule: .cascade, inverse: \CookPhoto.log)
    var photos: [CookPhoto]
    @Relationship(deleteRule: .cascade, inverse: \StepObservation.log)
    var observations: [StepObservation]

    init(
        cookedOn: Date,
        cookName: String,
        rating: Int,
        mood: String,
        tweakSummary: String,
        notes: String,
        nextTimeNote: String,
        photos: [CookPhoto] = [],
        observations: [StepObservation] = []
    ) {
        self.cookedOn = cookedOn
        self.cookName = cookName
        self.rating = rating
        self.mood = mood
        self.tweakSummary = tweakSummary
        self.notes = notes
        self.nextTimeNote = nextTimeNote
        self.photos = photos
        self.observations = observations
    }
}

@Model
final class CookPhoto {
    var stage: String
    var caption: String
    var imageData: Data
    var log: CookLog?

    init(stage: String, caption: String, imageData: Data) {
        self.stage = stage
        self.caption = caption
        self.imageData = imageData
    }
}

@Model
final class StepObservation {
    var stepTitle: String
    var note: String
    var log: CookLog?

    init(stepTitle: String, note: String) {
        self.stepTitle = stepTitle
        self.note = note
    }
}
