import CoreData
import Foundation

struct CoreDataStack {
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(
        inMemory: Bool = false
    ) throws {
        let managedObjectModel = Self.makeManagedObjectModel()
        container = NSPersistentContainer(
            name: "FamilyCookbookCoreData",
            managedObjectModel: managedObjectModel
        )

        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            inMemory: inMemory
        )

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.transactionAuthor = "FamilyCookbookApp"
    }

    func ensureCookbook() throws -> CDCookbook {
        let request = CDCookbook.fetchRequest()
        request.fetchLimit = 1

        if let existing = try viewContext.fetch(request).first {
            return existing
        }

        let cookbook = CDCookbook.makeDefault(in: viewContext)
        try saveIfNeeded()
        return cookbook
    }

    func importSampleDataIfNeeded(from recipes: [Recipe]) throws {
        let cookbook = try ensureCookbook()

        guard cookbook.sortedRecipes.isEmpty else {
            return
        }

        for (recipeIndex, sampleRecipe) in recipes.enumerated() {
            let recipe = CDRecipe(context: viewContext)
            recipe.id = UUID()
            recipe.title = sampleRecipe.title
            recipe.summaryText = sampleRecipe.summary
            recipe.familyOwner = sampleRecipe.familyOwner
            recipe.isFavorite = sampleRecipe.isFavorite
            recipe.tags = sampleRecipe.tags
            recipe.sortOrder = Int32(recipeIndex)
            recipe.createdAt = .now
            recipe.updatedAt = .now
            recipe.cookbook = cookbook

            for (ingredientIndex, sampleIngredient) in sampleRecipe.ingredients.enumerated() {
                let ingredient = CDIngredient(context: viewContext)
                ingredient.id = UUID()
                ingredient.amount = sampleIngredient.amount
                ingredient.name = sampleIngredient.name
                ingredient.sortOrder = Int32(ingredientIndex)
                ingredient.recipe = recipe
            }

            for (stepIndex, sampleStep) in sampleRecipe.steps.enumerated() {
                let step = CDRecipeStep(context: viewContext)
                step.id = UUID()
                step.title = sampleStep.title
                step.instructionText = sampleStep.instruction
                step.sortOrder = Int32(stepIndex)
                step.recipe = recipe
            }

            for (logIndex, sampleLog) in sampleRecipe.logs.enumerated() {
                let log = CDCookLog(context: viewContext)
                log.id = UUID()
                log.cookedOn = sampleLog.cookedOn
                log.cookName = sampleLog.cookName
                log.rating = Int16(sampleLog.rating)
                log.mood = sampleLog.mood
                log.tweakSummary = sampleLog.tweakSummary
                log.notes = sampleLog.notes
                log.nextTimeNote = sampleLog.nextTimeNote
                log.createdAt = .now
                log.updatedAt = .now
                log.recipe = recipe

                for (photoIndex, samplePhoto) in sampleLog.photos.enumerated() {
                    let photo = CDCookPhoto(context: viewContext)
                    photo.id = UUID()
                    photo.stage = samplePhoto.stage
                    photo.caption = samplePhoto.caption
                    photo.imageData = samplePhoto.imageData
                    photo.sortOrder = Int32(photoIndex)
                    photo.log = log
                }

                for (observationIndex, sampleObservation) in sampleLog.observations.enumerated() {
                    let observation = CDStepObservation(context: viewContext)
                    observation.id = UUID()
                    observation.stepTitle = sampleObservation.stepTitle
                    observation.note = sampleObservation.note
                    observation.sortOrder = Int32(observationIndex)
                    observation.log = log
                }

                log.updatedAt = sampleLog.cookedOn
                recipe.updatedAt = max(recipe.updatedAt, sampleLog.cookedOn)
                recipe.sortOrder = Int32(recipeIndex)
                _ = logIndex
            }
        }

        cookbook.updatedAt = .now
        try saveIfNeeded()
    }

    func saveIfNeeded() throws {
        guard viewContext.hasChanges else {
            return
        }

        try viewContext.save()
    }

    func makeSnapshot() throws -> CookbookSnapshot {
        let cookbook = try ensureCookbook()

        return CookbookSnapshot(
            title: cookbook.title,
            ownerName: cookbook.ownerName,
            updatedAt: cookbook.updatedAt,
            recipes: cookbook.sortedRecipes.map { recipe in
                RecipeSnapshot(
                    id: recipe.id,
                    title: recipe.title,
                    summary: recipe.summaryText,
                    familyOwner: recipe.familyOwner,
                    isFavorite: recipe.isFavorite,
                    tags: recipe.tags,
                    sortOrder: recipe.sortOrder,
                    createdAt: recipe.createdAt,
                    updatedAt: recipe.updatedAt,
                    ingredients: recipe.sortedIngredients.map { ingredient in
                        IngredientSnapshot(
                            id: ingredient.id,
                            amount: ingredient.amount,
                            name: ingredient.name,
                            sortOrder: ingredient.sortOrder
                        )
                    },
                    steps: recipe.sortedSteps.map { step in
                        RecipeStepSnapshot(
                            id: step.id,
                            title: step.title,
                            instruction: step.instructionText,
                            sortOrder: step.sortOrder
                        )
                    },
                    logs: recipe.sortedLogs.map { log in
                        CookLogSnapshot(
                            id: log.id,
                            cookedOn: log.cookedOn,
                            cookName: log.cookName,
                            rating: log.rating,
                            mood: log.mood,
                            tweakSummary: log.tweakSummary,
                            notes: log.notes,
                            nextTimeNote: log.nextTimeNote,
                            createdAt: log.createdAt,
                            updatedAt: log.updatedAt,
                            photos: log.sortedPhotos.map { photo in
                                CookPhotoSnapshot(
                                    id: photo.id,
                                    stage: photo.stage,
                                    caption: photo.caption,
                                    imageData: photo.imageData,
                                    sortOrder: photo.sortOrder
                                )
                            },
                            observations: log.sortedObservations.map { observation in
                                StepObservationSnapshot(
                                    id: observation.id,
                                    stepTitle: observation.stepTitle,
                                    note: observation.note,
                                    sortOrder: observation.sortOrder
                                )
                            }
                        )
                    }
                )
            },
            shoppingItems: cookbook.sortedShoppingItems.map { item in
                ShoppingListItemSnapshot(
                    id: item.id,
                    itemName: item.itemName,
                    amountText: item.amountText,
                    sourceRecipeTitle: item.sourceRecipeTitle,
                    note: item.note,
                    isChecked: item.isChecked,
                    sortOrder: item.sortOrder,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            }
        )
    }

    func replaceCookbook(with snapshot: CookbookSnapshot) throws {
        let cookbook = try ensureCookbook()

        for recipe in cookbook.sortedRecipes {
            viewContext.delete(recipe)
        }

        for shoppingItem in cookbook.sortedShoppingItems {
            viewContext.delete(shoppingItem)
        }

        cookbook.title = snapshot.title
        cookbook.ownerName = snapshot.ownerName
        cookbook.updatedAt = snapshot.updatedAt

        for recipeSnapshot in snapshot.recipes {
            let recipe = CDRecipe(context: viewContext)
            recipe.id = recipeSnapshot.id
            recipe.title = recipeSnapshot.title
            recipe.summaryText = recipeSnapshot.summary
            recipe.familyOwner = recipeSnapshot.familyOwner
            recipe.isFavorite = recipeSnapshot.isFavorite
            recipe.tags = recipeSnapshot.tags
            recipe.sortOrder = recipeSnapshot.sortOrder
            recipe.createdAt = recipeSnapshot.createdAt
            recipe.updatedAt = recipeSnapshot.updatedAt
            recipe.cookbook = cookbook

            for ingredientSnapshot in recipeSnapshot.ingredients {
                let ingredient = CDIngredient(context: viewContext)
                ingredient.id = ingredientSnapshot.id
                ingredient.amount = ingredientSnapshot.amount
                ingredient.name = ingredientSnapshot.name
                ingredient.sortOrder = ingredientSnapshot.sortOrder
                ingredient.recipe = recipe
            }

            for stepSnapshot in recipeSnapshot.steps {
                let step = CDRecipeStep(context: viewContext)
                step.id = stepSnapshot.id
                step.title = stepSnapshot.title
                step.instructionText = stepSnapshot.instruction
                step.sortOrder = stepSnapshot.sortOrder
                step.recipe = recipe
            }

            for logSnapshot in recipeSnapshot.logs {
                let log = CDCookLog(context: viewContext)
                log.id = logSnapshot.id
                log.cookedOn = logSnapshot.cookedOn
                log.cookName = logSnapshot.cookName
                log.rating = logSnapshot.rating
                log.mood = logSnapshot.mood
                log.tweakSummary = logSnapshot.tweakSummary
                log.notes = logSnapshot.notes
                log.nextTimeNote = logSnapshot.nextTimeNote
                log.createdAt = logSnapshot.createdAt
                log.updatedAt = logSnapshot.updatedAt
                log.recipe = recipe

                for photoSnapshot in logSnapshot.photos {
                    let photo = CDCookPhoto(context: viewContext)
                    photo.id = photoSnapshot.id
                    photo.stage = photoSnapshot.stage
                    photo.caption = photoSnapshot.caption
                    photo.imageData = photoSnapshot.imageData
                    photo.sortOrder = photoSnapshot.sortOrder
                    photo.log = log
                }

                for observationSnapshot in logSnapshot.observations {
                    let observation = CDStepObservation(context: viewContext)
                    observation.id = observationSnapshot.id
                    observation.stepTitle = observationSnapshot.stepTitle
                    observation.note = observationSnapshot.note
                    observation.sortOrder = observationSnapshot.sortOrder
                    observation.log = log
                }
            }
        }

        for itemSnapshot in snapshot.shoppingItems {
            let item = CDShoppingListItem(context: viewContext)
            item.id = itemSnapshot.id
            item.itemName = itemSnapshot.itemName
            item.amountText = itemSnapshot.amountText
            item.sourceRecipeTitle = itemSnapshot.sourceRecipeTitle
            item.note = itemSnapshot.note
            item.isChecked = itemSnapshot.isChecked
            item.sortOrder = itemSnapshot.sortOrder
            item.createdAt = itemSnapshot.createdAt
            item.updatedAt = itemSnapshot.updatedAt
            item.cookbook = cookbook
        }

        try saveIfNeeded()
    }

    private static func makeStoreDescriptions(
        inMemory: Bool
    ) -> [NSPersistentStoreDescription] {
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            return [description]
        }

        let baseURL = URL.applicationSupportDirectory
        let privateStoreURL = baseURL.appending(path: "FamilyCookbook.sqlite")
        let sharedStoreURL = baseURL.appending(path: "FamilyCookbook-shared.sqlite")

        let privateStore = NSPersistentStoreDescription(url: privateStoreURL)
        privateStore.configuration = "Private"
        privateStore.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStore.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let sharedStore = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedStore.configuration = "Shared"
        sharedStore.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedStore.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        return [privateStore, sharedStore]
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let cookbook = NSEntityDescription()
        cookbook.name = "CDCookbook"
        cookbook.managedObjectClassName = NSStringFromClass(CDCookbook.self)

        let recipe = NSEntityDescription()
        recipe.name = "CDRecipe"
        recipe.managedObjectClassName = NSStringFromClass(CDRecipe.self)

        let ingredient = NSEntityDescription()
        ingredient.name = "CDIngredient"
        ingredient.managedObjectClassName = NSStringFromClass(CDIngredient.self)

        let recipeStep = NSEntityDescription()
        recipeStep.name = "CDRecipeStep"
        recipeStep.managedObjectClassName = NSStringFromClass(CDRecipeStep.self)

        let cookLog = NSEntityDescription()
        cookLog.name = "CDCookLog"
        cookLog.managedObjectClassName = NSStringFromClass(CDCookLog.self)

        let cookPhoto = NSEntityDescription()
        cookPhoto.name = "CDCookPhoto"
        cookPhoto.managedObjectClassName = NSStringFromClass(CDCookPhoto.self)

        let stepObservation = NSEntityDescription()
        stepObservation.name = "CDStepObservation"
        stepObservation.managedObjectClassName = NSStringFromClass(CDStepObservation.self)

        let shoppingListItem = NSEntityDescription()
        shoppingListItem.name = "CDShoppingListItem"
        shoppingListItem.managedObjectClassName = NSStringFromClass(CDShoppingListItem.self)

        let cookbookRecipes = relationship(
            name: "recipes",
            destination: recipe,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let recipeCookbook = relationship(
            name: "cookbook",
            destination: cookbook,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        cookbookRecipes.inverseRelationship = recipeCookbook
        recipeCookbook.inverseRelationship = cookbookRecipes

        let cookbookShoppingItems = relationship(
            name: "shoppingItems",
            destination: shoppingListItem,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let shoppingItemCookbook = relationship(
            name: "cookbook",
            destination: cookbook,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        cookbookShoppingItems.inverseRelationship = shoppingItemCookbook
        shoppingItemCookbook.inverseRelationship = cookbookShoppingItems

        let recipeIngredients = relationship(
            name: "ingredients",
            destination: ingredient,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let ingredientRecipe = relationship(
            name: "recipe",
            destination: recipe,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        recipeIngredients.inverseRelationship = ingredientRecipe
        ingredientRecipe.inverseRelationship = recipeIngredients

        let recipeSteps = relationship(
            name: "steps",
            destination: recipeStep,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let stepRecipe = relationship(
            name: "recipe",
            destination: recipe,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        recipeSteps.inverseRelationship = stepRecipe
        stepRecipe.inverseRelationship = recipeSteps

        let recipeLogs = relationship(
            name: "logs",
            destination: cookLog,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let logRecipe = relationship(
            name: "recipe",
            destination: recipe,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        recipeLogs.inverseRelationship = logRecipe
        logRecipe.inverseRelationship = recipeLogs

        let logPhotos = relationship(
            name: "photos",
            destination: cookPhoto,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let photoLog = relationship(
            name: "log",
            destination: cookLog,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        logPhotos.inverseRelationship = photoLog
        photoLog.inverseRelationship = logPhotos

        let logObservations = relationship(
            name: "observations",
            destination: stepObservation,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule,
            isOrdered: false
        )
        let observationLog = relationship(
            name: "log",
            destination: cookLog,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule,
            isOrdered: false
        )
        logObservations.inverseRelationship = observationLog
        observationLog.inverseRelationship = logObservations

        cookbook.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "title", type: .stringAttributeType),
            attribute(name: "ownerName", type: .stringAttributeType),
            attribute(name: "createdAt", type: .dateAttributeType),
            attribute(name: "updatedAt", type: .dateAttributeType),
            cookbookRecipes,
            cookbookShoppingItems
        ]

        recipe.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "title", type: .stringAttributeType),
            attribute(name: "summaryText", type: .stringAttributeType),
            attribute(name: "familyOwner", type: .stringAttributeType),
            attribute(name: "isFavorite", type: .booleanAttributeType, defaultValue: false),
            attribute(name: "tagsText", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: 0),
            attribute(name: "createdAt", type: .dateAttributeType),
            attribute(name: "updatedAt", type: .dateAttributeType),
            recipeCookbook,
            recipeIngredients,
            recipeSteps,
            recipeLogs
        ]

        ingredient.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "amount", type: .stringAttributeType),
            attribute(name: "name", type: .stringAttributeType),
            attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: 0),
            ingredientRecipe
        ]

        recipeStep.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "title", type: .stringAttributeType),
            attribute(name: "instructionText", type: .stringAttributeType),
            attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: 0),
            stepRecipe
        ]

        cookLog.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "cookedOn", type: .dateAttributeType),
            attribute(name: "cookName", type: .stringAttributeType),
            attribute(name: "rating", type: .integer16AttributeType, defaultValue: 0),
            attribute(name: "mood", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "tweakSummary", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "notes", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "nextTimeNote", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "createdAt", type: .dateAttributeType),
            attribute(name: "updatedAt", type: .dateAttributeType),
            logRecipe,
            logPhotos,
            logObservations
        ]

        cookPhoto.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "stage", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "caption", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "imageData", type: .binaryDataAttributeType, isOptional: true),
            attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: 0),
            photoLog
        ]

        stepObservation.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "stepTitle", type: .stringAttributeType),
            attribute(name: "note", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: 0),
            observationLog
        ]

        shoppingListItem.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "itemName", type: .stringAttributeType),
            attribute(name: "amountText", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "sourceRecipeTitle", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "note", type: .stringAttributeType, defaultValue: ""),
            attribute(name: "isChecked", type: .booleanAttributeType, defaultValue: false),
            attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: 0),
            attribute(name: "createdAt", type: .dateAttributeType),
            attribute(name: "updatedAt", type: .dateAttributeType),
            shoppingItemCookbook
        ]

        let entities = [cookbook, recipe, ingredient, recipeStep, cookLog, cookPhoto, stepObservation, shoppingListItem]
        model.entities = entities
        model.setEntities(entities, forConfigurationName: "Private")
        model.setEntities(entities, forConfigurationName: "Shared")
        return model
    }

    private static func attribute(
        name: String,
        type: NSAttributeType,
        isOptional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }

    private static func relationship(
        name: String,
        destination: NSEntityDescription,
        minCount: Int,
        maxCount: Int,
        deleteRule: NSDeleteRule,
        isOrdered: Bool
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = minCount
        relationship.maxCount = maxCount
        relationship.deleteRule = deleteRule
        relationship.isOptional = true
        relationship.isOrdered = isOrdered
        return relationship
    }
}

@MainActor
enum FamilyCookbookCoreDataPreview {
    static let stack: CoreDataStack = {
        let stack = try! CoreDataStack(inMemory: true)
        try! stack.importSampleDataIfNeeded(from: FamilyCookbookData.sampleRecipes)
        return stack
    }()
}
