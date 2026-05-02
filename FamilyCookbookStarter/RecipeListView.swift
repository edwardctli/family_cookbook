import CoreData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SupabaseAuthManager.self) private var authManager
    @Environment(CookbookSyncCoordinator.self) private var syncCoordinator
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDRecipe.title, ascending: true)], animation: .default)
    private var recipes: FetchedResults<CDRecipe>

    @State private var showingNewRecipe = false
    @State private var showingImportRecipe = false
    @State private var searchText = ""
    @State private var selectedFilter: RecipeFilter = .all
    @State private var selectedSort: RecipeSort = .title
    @Binding private var selectedRecipeID: NSManagedObjectID?

    private let usesSplitViewLayout: Bool

    init(selectedRecipeID: Binding<NSManagedObjectID?> = .constant(nil), usesSplitViewLayout: Bool = false) {
        _selectedRecipeID = selectedRecipeID
        self.usesSplitViewLayout = usesSplitViewLayout
    }

    private var visibleRecipes: [CDRecipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = recipes.filter { recipe in
            let matchesSearch =
                query.isEmpty ||
                recipe.title.localizedStandardContains(query) ||
                recipe.summaryText.localizedStandardContains(query) ||
                recipe.familyOwner.localizedStandardContains(query) ||
                recipe.tags.contains(where: { $0.localizedStandardContains(query) })

            let matchesFilter = switch selectedFilter {
            case .all:
                true
            case .favorites:
                recipe.isFavorite
            case .recentlyCooked:
                recipe.latestLog != nil
            }

            return matchesSearch && matchesFilter
        }

        return filtered.sorted(by: selectedSort.comparator)
    }

    var body: some View {
        Group {
            if usesSplitViewLayout {
                recipeList
                    .listStyle(.sidebar)
                    .refreshable {
                        await refreshFromSync()
                    }
            } else {
                recipeList
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await refreshFromSync()
                    }
            }
        }
        .navigationTitle("Recipes")
        .searchable(text: $searchText, prompt: "Search recipes, owners, or tags")
        .toolbar {
            ToolbarItem(placement: usesSplitViewLayout ? .automatic : .topBarLeading) {
                Menu {
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(RecipeSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: usesSplitViewLayout ? .primaryAction : .topBarTrailing) {
                Menu {
                    Button("New Recipe", systemImage: "square.and.pencil") {
                        showingNewRecipe = true
                    }

                    Button("Import from URL", systemImage: "square.and.arrow.down") {
                        showingImportRecipe = true
                    }
                } label: {
                    Label("Add Recipe", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewRecipe) {
            CDRecipeEditorView()
        }
        .sheet(isPresented: $showingImportRecipe) {
            RecipeImportSheet()
        }
    }

    private var recipeList: some View {
        List(selection: $selectedRecipeID) {
            Section {
                filterPicker
            }

            Section("Recipes") {
                if visibleRecipes.isEmpty {
                    ContentUnavailableView("No Recipes Yet", systemImage: "fork.knife", description: Text("Create the first family recipe to start building the cookbook."))
                } else {
                    ForEach(visibleRecipes, id: \.objectID) { recipe in
                        Group {
                            if usesSplitViewLayout {
                                CDRecipeRow(recipe: recipe)
                                    .tag(recipe.objectID)
                            } else {
                                NavigationLink {
                                    CDRecipeDetailView(recipe: recipe)
                                } label: {
                                    CDRecipeRow(recipe: recipe)
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                toggleFavorite(for: recipe)
                            } label: {
                                Label(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteRecipe(recipe)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func refreshFromSync() async {
        guard authManager.state.isAuthenticated else {
            return
        }

        await syncCoordinator.pullSilently()
    }

    @ViewBuilder
    private var filterPicker: some View {
        if usesSplitViewLayout {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(RecipeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(RecipeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func toggleFavorite(for recipe: CDRecipe) {
        recipe.isFavorite.toggle()
        recipe.updatedAt = .now
        try? managedObjectContext.save()
    }

    private func deleteRecipe(_ recipe: CDRecipe) {
        if selectedRecipeID == recipe.objectID {
            selectedRecipeID = nil
        }

        managedObjectContext.delete(recipe)
        try? managedObjectContext.save()
    }
}

#Preview {
    NavigationStack {
        RecipeListView()
    }
    .modelContainer(FamilyCookbookPreview.container)
    .environment(\.managedObjectContext, FamilyCookbookCoreDataPreview.stack.viewContext)
}

struct CDRecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCookbook.createdAt, ascending: true)])
    private var cookbooks: FetchedResults<CDCookbook>
    @State private var showingAddLog = false
    @State private var showingEditRecipe = false
    @State private var showingScaleRecipe = false
    @State private var ingredientScaleMultiplier = 1.0

    let recipe: CDRecipe

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.title)
                        .font(.largeTitle.bold())

                    Text(recipe.summaryText)
                        .foregroundStyle(.secondary)

                    Text("Originally from \(recipe.familyOwner)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 8)
            }

            Section {
                if recipe.sortedIngredients.isEmpty {
                    Text("No ingredients yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.sortedIngredients, id: \.objectID) { ingredient in
                        HStack {
                            Text(displayAmount(for: ingredient))
                                .foregroundStyle(.secondary)
                            Text(ingredient.name)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    if ingredientScaleMultiplier != 1 {
                        Text(scaleSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Steps") {
                if recipe.sortedSteps.isEmpty {
                    Text("No steps yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recipe.sortedSteps.enumerated()), id: \.element.objectID) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Step \(index + 1): \(step.title)")
                                .font(.headline)
                            Text(step.instructionText)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Cook History") {
                if recipe.sortedLogs.isEmpty {
                    Text("No cook sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.sortedLogs, id: \.objectID) { log in
                        NavigationLink {
                            CDCookLogDetailView(recipeTitle: recipe.title, log: log)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(log.cookName)
                                    .font(.headline)
                                Text(log.cookedOn.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(log.tweakSummary)
                                    .font(.subheadline)
                                if !log.nextTimeNote.isEmpty {
                                    Text("Next time: \(log.nextTimeNote)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
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
                    recipe.updatedAt = .now
                    try? managedObjectContext.save()
                } label: {
                    Image(systemName: recipe.isFavorite ? "star.fill" : "star")
                }

                Button("Edit") {
                    showingEditRecipe = true
                }

                Button("Scale") {
                    showingScaleRecipe = true
                }

                Button("Add to List") {
                    addIngredientsToShoppingList()
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
        .sheet(isPresented: $showingEditRecipe) {
            CDRecipeEditorView(recipe: recipe)
        }
        .sheet(isPresented: $showingScaleRecipe) {
            RecipeScalingSheet(
                recipe: recipe,
                currentMultiplier: ingredientScaleMultiplier
            ) { multiplier in
                ingredientScaleMultiplier = multiplier
            }
        }
        .sheet(isPresented: $showingAddLog) {
            CDNewCookLogView(recipe: recipe)
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteLog(_ log: CDCookLog) {
        managedObjectContext.delete(log)
        recipe.updatedAt = .now
        try? managedObjectContext.save()
    }

    private func deleteRecipe() {
        managedObjectContext.delete(recipe)
        try? managedObjectContext.save()
        dismiss()
    }

    private func addIngredientsToShoppingList() {
        guard let cookbook = cookbooks.first else {
            return
        }

        let nextSortOrder = Int32((cookbook.sortedShoppingItems.last?.sortOrder ?? -1) + 1)

        for (index, ingredient) in recipe.sortedIngredients.enumerated() {
            let item = CDShoppingListItem(context: managedObjectContext)
            item.id = UUID()
            item.itemName = ingredient.name
            item.amountText = ingredient.amount
            item.sourceRecipeTitle = recipe.title
            item.note = ""
            item.isChecked = false
            item.sortOrder = nextSortOrder + Int32(index)
            item.createdAt = .now
            item.updatedAt = .now
            item.cookbook = cookbook
        }

        recipe.updatedAt = .now
        cookbook.updatedAt = .now
        try? managedObjectContext.save()
    }

    private var scaleSummary: String {
        if ingredientScaleMultiplier == 1 {
            return "Original"
        }

        return String(format: "%.2gx", ingredientScaleMultiplier)
    }

    private func displayAmount(for ingredient: CDIngredient) -> String {
        guard ingredientScaleMultiplier != 1 else {
            return ingredient.amount
        }

        let parts = IngredientComponents.parse(amountText: ingredient.amount)
        guard let parsedAmount = IngredientAmountParser.parse(parts.amount) else {
            return ingredient.amount
        }

        let scaledAmount = parsedAmount * ingredientScaleMultiplier
        let formattedAmount = IngredientAmountFormatter.format(scaledAmount)
        return [formattedAmount, parts.unit]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct CDRecipeRow: View {
    let recipe: CDRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(recipe.title)
                    .font(.headline)

                if recipe.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Text(recipe.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(recipe.tags, id: \.self) { tag in
                        TagChip(title: tag)
                    }
                }
            }

            if let latestLog = recipe.latestLog {
                Label(
                    "\(latestLog.cookName) last cooked this and rated it \(latestLog.rating)/5",
                    systemImage: "sparkles"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.12))
            .clipShape(Capsule())
    }
}

private enum RecipeFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recentlyCooked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .favorites:
            "Favorites"
        case .recentlyCooked:
            "Cooked"
        }
    }
}

private enum RecipeSort: String, CaseIterable, Identifiable {
    case title
    case familyOwner
    case recentlyUpdated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            "Title"
        case .familyOwner:
            "Owner"
        case .recentlyUpdated:
            "Recent Activity"
        }
    }

    var comparator: (CDRecipe, CDRecipe) -> Bool {
        switch self {
        case .title:
            {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .familyOwner:
            {
                let order = $0.familyOwner.localizedCaseInsensitiveCompare($1.familyOwner)
                if order == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return order == .orderedAscending
            }
        case .recentlyUpdated:
            {
                let lhs = $0.latestLog?.cookedOn ?? $0.updatedAt
                let rhs = $1.latestLog?.cookedOn ?? $1.updatedAt
                if lhs == rhs {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return lhs > rhs
            }
        }
    }
}

struct CDRecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCookbook.createdAt, ascending: true)])
    private var cookbooks: FetchedResults<CDCookbook>

    private let recipe: CDRecipe?

    @State private var title: String
    @State private var summary: String
    @State private var familyOwner: String
    @State private var isFavorite: Bool
    @State private var tagsText: String
    @State private var ingredients: [DraftIngredient]
    @State private var steps: [DraftStep]

    init(recipe: CDRecipe? = nil) {
        self.recipe = recipe
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summaryText ?? "")
        _familyOwner = State(initialValue: recipe?.familyOwner ?? "")
        _isFavorite = State(initialValue: recipe?.isFavorite ?? false)
        _tagsText = State(initialValue: recipe?.tags.joined(separator: ", ") ?? "")
        _ingredients = State(initialValue: recipe?.sortedIngredients.map {
            DraftIngredient(components: IngredientComponents.parse(amountText: $0.amount), name: $0.name)
        } ?? [DraftIngredient()])
        _steps = State(initialValue: recipe?.sortedSteps.map { DraftStep(title: $0.title, instruction: $0.instructionText) } ?? [DraftStep()])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...5)
                    TextField("Family owner", text: $familyOwner)
                    Toggle("Favorite", isOn: $isFavorite)
                    TextField("Tags, separated by commas", text: $tagsText, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Ingredients") {
                    ForEach($ingredients) { $ingredient in
                        HStack {
                            TextField("Amount", text: $ingredient.amount)
                                .frame(maxWidth: 70)
                            TextField("Unit", text: $ingredient.unit)
                                .frame(maxWidth: 90)
                            TextField("Ingredient", text: $ingredient.name)
                        }
                    }
                    .onDelete { offsets in
                        ingredients.remove(atOffsets: offsets)
                    }

                    Button("Add Ingredient") {
                        ingredients.append(DraftIngredient())
                    }
                }

                Section("Steps") {
                    ForEach(Array($steps.enumerated()), id: \.element.id) { index, $step in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Step \(index + 1)")
                                .font(.headline)
                            TextField("Title", text: $step.title)
                            TextField("Instruction", text: $step.instruction, axis: .vertical)
                                .lineLimit(3...6)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        steps.remove(atOffsets: offsets)
                    }

                    Button("Add Step") {
                        steps.append(DraftStep())
                    }
                }
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveRecipe()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveRecipe() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let recipe = recipe ?? makeRecipe()
        recipe.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summaryText = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.familyOwner = familyOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.isFavorite = isFavorite
        recipe.tags = tags
        recipe.updatedAt = .now

        replaceIngredients(on: recipe)
        replaceSteps(on: recipe)

        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            return
        }
    }

    private func makeRecipe() -> CDRecipe {
        let recipe = CDRecipe(context: managedObjectContext)
        recipe.id = UUID()
        recipe.createdAt = .now
        recipe.updatedAt = .now
        recipe.sortOrder = Int32((cookbooks.first?.sortedRecipes.count ?? 0) + 1)
        recipe.cookbook = cookbooks.first
        return recipe
    }

    private func replaceIngredients(on recipe: CDRecipe) {
        for ingredient in recipe.sortedIngredients {
            managedObjectContext.delete(ingredient)
        }

        for (index, draft) in ingredients.enumerated() {
            guard !draft.amountText.isEmpty || !draft.nameText.isEmpty else {
                continue
            }

            let ingredient = CDIngredient(context: managedObjectContext)
            ingredient.id = UUID()
            ingredient.amount = draft.combinedAmountText
            ingredient.name = draft.nameText
            ingredient.sortOrder = Int32(index)
            ingredient.recipe = recipe
        }
    }

    private func replaceSteps(on recipe: CDRecipe) {
        for step in recipe.sortedSteps {
            managedObjectContext.delete(step)
        }

        for (index, draft) in steps.enumerated() {
            guard !draft.titleText.isEmpty || !draft.instructionText.isEmpty else {
                continue
            }

            let step = CDRecipeStep(context: managedObjectContext)
            step.id = UUID()
            step.title = draft.titleText
            step.instructionText = draft.instructionText
            step.sortOrder = Int32(index)
            step.recipe = recipe
        }
    }
}

private struct DraftIngredient: Identifiable {
    let id = UUID()
    var amount = ""
    var unit = ""
    var name = ""

    init(amount: String = "", unit: String = "", name: String = "") {
        self.amount = amount
        self.unit = unit
        self.name = name
    }

    init(components: IngredientComponents, name: String) {
        self.amount = components.amount
        self.unit = components.unit
        self.name = name
    }

    var amountText: String {
        amount.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var unitText: String {
        unit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nameText: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var combinedAmountText: String {
        [amountText, unitText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct IngredientComponents {
    let amount: String
    let unit: String

    static func parse(amountText: String) -> IngredientComponents {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return IngredientComponents(amount: "", unit: "")
        }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        let amountTokens = tokens.prefix { token in
            token.first?.isNumber == true || token.contains("/") || containsFractionCharacter(String(token))
        }

        guard !amountTokens.isEmpty else {
            return IngredientComponents(amount: "", unit: trimmed)
        }

        let amount = amountTokens.joined(separator: " ")
        let unit = tokens.dropFirst(amountTokens.count).joined(separator: " ")
        return IngredientComponents(amount: amount, unit: unit)
    }

    private static func containsFractionCharacter(_ value: String) -> Bool {
        value.rangeOfCharacter(from: CharacterSet(charactersIn: "¼½¾⅓⅔⅛⅜⅝⅞")) != nil
    }
}

private enum IngredientAmountParser {
    private static let unicodeFractions: [Character: Double] = [
        "¼": 0.25,
        "½": 0.5,
        "¾": 0.75,
        "⅓": 1.0 / 3.0,
        "⅔": 2.0 / 3.0,
        "⅛": 0.125,
        "⅜": 0.375,
        "⅝": 0.625,
        "⅞": 0.875
    ]

    static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        var total = 0.0

        for token in tokens {
            let tokenString = String(token)
            if let numericValue = Double(tokenString) {
                total += numericValue
                continue
            }

            if let unicodeValue = parseUnicodeFraction(tokenString) {
                total += unicodeValue
                continue
            }

            if let slashValue = parseSlashFraction(tokenString) {
                total += slashValue
                continue
            }

            return nil
        }

        return total > 0 ? total : nil
    }

    private static func parseUnicodeFraction(_ token: String) -> Double? {
        if token.count == 1, let first = token.first {
            return unicodeFractions[first]
        }

        return nil
    }

    private static func parseSlashFraction(_ token: String) -> Double? {
        let components = token.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2,
              let numerator = Double(components[0]),
              let denominator = Double(components[1]),
              denominator != 0
        else {
            return nil
        }

        return numerator / denominator
    }
}

private enum IngredientAmountFormatter {
    private static let fractions: [(value: Double, label: String)] = [
        (0.125, "1/8"),
        (0.25, "1/4"),
        (1.0 / 3.0, "1/3"),
        (0.375, "3/8"),
        (0.5, "1/2"),
        (0.625, "5/8"),
        (2.0 / 3.0, "2/3"),
        (0.75, "3/4"),
        (0.875, "7/8")
    ]

    static func format(_ value: Double) -> String {
        guard value.isFinite, value > 0 else {
            return ""
        }

        let whole = Int(value.rounded(.down))
        let fractional = value - Double(whole)

        if let fraction = nearestFraction(to: fractional) {
            if whole == 0 {
                return fraction
            }

            return "\(whole) \(fraction)"
        }

        if abs(value.rounded() - value) < 0.01 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static func nearestFraction(to value: Double) -> String? {
        guard value >= 0.01 else {
            return nil
        }

        let nearest = fractions.min { abs($0.value - value) < abs($1.value - value) }
        guard let nearest, abs(nearest.value - value) < 0.06 else {
            return nil
        }

        return nearest.label
    }
}

private struct RecipeScalingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: CDRecipe
    let currentMultiplier: Double
    let onApply: (Double) -> Void

    @State private var mode: ScalingMode = .multiplier
    @State private var multiplierText: String
    @State private var selectedIngredientID: NSManagedObjectID?
    @State private var targetAmountText = ""

    init(recipe: CDRecipe, currentMultiplier: Double, onApply: @escaping (Double) -> Void) {
        self.recipe = recipe
        self.currentMultiplier = currentMultiplier
        self.onApply = onApply
        _multiplierText = State(initialValue: currentMultiplier == 1 ? "1" : String(format: "%.2f", currentMultiplier))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scale Method") {
                    Picker("Mode", selection: $mode) {
                        ForEach(ScalingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .multiplier:
                    Section("Multiplier") {
                        TextField("e.g. 0.5, 2, 3", text: $multiplierText)
#if !os(macOS)
                            .keyboardType(.decimalPad)
#endif
                        Text("Use values below 1 to scale down and above 1 to scale up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .ingredientTarget:
                    Section("Reference Ingredient") {
                        Picker("Ingredient", selection: $selectedIngredientID) {
                            ForEach(scalableIngredients, id: \.ingredient.objectID) { item in
                                Text(item.ingredient.name).tag(Optional(item.ingredient.objectID))
                            }
                        }

                        TextField("New amount", text: $targetAmountText)
                            .textInputAutocapitalization(.never)
#if !os(macOS)
                            .keyboardType(.decimalPad)
#endif

                        if let preview = derivedMultiplier {
                            Text("This will scale the recipe by \(String(format: "%.2gx", preview)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Choose an ingredient with a numeric amount and enter the new amount.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if currentMultiplier != 1 {
                    Section {
                        Button("Reset to Original", role: .destructive) {
                            onApply(1)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Scale Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply()
                    }
                    .disabled(activeMultiplier == nil)
                }
            }
            .onAppear {
                if let first = scalableIngredients.first?.ingredient.objectID {
                    selectedIngredientID = selectedIngredientID ?? first
                }
            }
        }
    }

    private var scalableIngredients: [(ingredient: CDIngredient, amount: Double)] {
        recipe.sortedIngredients.compactMap { ingredient in
            let parts = IngredientComponents.parse(amountText: ingredient.amount)
            guard let amount = IngredientAmountParser.parse(parts.amount) else {
                return nil
            }

            return (ingredient: ingredient, amount: amount)
        }
    }

    private var activeMultiplier: Double? {
        switch mode {
        case .multiplier:
            guard let value = Double(multiplierText.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
                return nil
            }
            return value
        case .ingredientTarget:
            return derivedMultiplier
        }
    }

    private var derivedMultiplier: Double? {
        guard
            let selectedIngredientID,
            let currentAmount = scalableIngredients.first(where: { $0.ingredient.objectID == selectedIngredientID })?.amount,
            let targetAmount = IngredientAmountParser.parse(targetAmountText),
            currentAmount > 0,
            targetAmount > 0
        else {
            return nil
        }

        return targetAmount / currentAmount
    }

    private func apply() {
        guard let multiplier = activeMultiplier else {
            return
        }

        onApply(multiplier)
        dismiss()
    }
}

private enum ScalingMode: String, CaseIterable, Identifiable {
    case multiplier
    case ingredientTarget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multiplier:
            "Multiply"
        case .ingredientTarget:
            "Match Ingredient"
        }
    }
}

private struct DraftStep: Identifiable {
    let id = UUID()
    var title = ""
    var instruction = ""

    var titleText: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var instructionText: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImportedRecipeData {
    let sourceURL: URL
    let sourceName: String
    let title: String
    let summary: String
    let tags: [String]
    let ingredients: [ImportedIngredient]
    let steps: [ImportedStep]
}

private struct ImportedIngredient: Identifiable {
    let id = UUID()
    let amount: String
    let unit: String
    let name: String
}

private struct ImportedStep: Identifiable {
    let id = UUID()
    let title: String
    let instruction: String
}

private enum RecipeImportError: LocalizedError {
    case invalidURL
    case noRecipeFound
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid recipe URL."
        case .noRecipeFound:
            "No recipe data was found at that URL."
        case .unsupportedFormat:
            "This page does not expose recipe data in a format the importer can read yet."
        }
    }
}

private enum RecipeImportService {
    static func importRecipe(from url: URL) async throws -> ImportedRecipeData {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 FamilyCookbook/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw RecipeImportError.unsupportedFormat
        }

        let parser = RecipeStructuredDataParser(html: html, sourceURL: url)
        return try parser.parse()
    }
}

private struct RecipeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCookbook.createdAt, ascending: true)])
    private var cookbooks: FetchedResults<CDCookbook>

    @State private var urlText = ""
    @State private var importedRecipe: ImportedRecipeData?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe URL") {
                    TextField("https://example.com/recipe", text: $urlText)
                        .textInputAutocapitalization(.never)
#if !os(macOS)
                        .keyboardType(.URL)
#endif
                        .autocorrectionDisabled()

                    Button("Fetch Recipe") {
                        fetchRecipe()
                    }
                    .disabled(isImporting || normalizedURL == nil)
                }

                if let importedRecipe {
                    Section("Preview") {
                        LabeledContent("Source", value: importedRecipe.sourceName)
                        LabeledContent("Title", value: importedRecipe.title)

                        if !importedRecipe.summary.isEmpty {
                            Text(importedRecipe.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Ingredients", value: "\(importedRecipe.ingredients.count)")
                        LabeledContent("Steps", value: "\(importedRecipe.steps.count)")
                    }

                    if !importedRecipe.tags.isEmpty {
                        Section("Imported Tags") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(importedRecipe.tags, id: \.self) { tag in
                                        TagChip(title: tag)
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        saveImportedRecipe()
                    }
                    .disabled(importedRecipe == nil || isSaving)
                }
            }
        }
    }

    private var normalizedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let directURL = URL(string: trimmed), directURL.scheme != nil {
            return directURL
        }

        return URL(string: "https://\(trimmed)")
    }

    private func fetchRecipe() {
        guard let normalizedURL else {
            errorMessage = RecipeImportError.invalidURL.localizedDescription
            return
        }

        isImporting = true
        errorMessage = nil

        Task {
            do {
                let recipe = try await RecipeImportService.importRecipe(from: normalizedURL)
                await MainActor.run {
                    importedRecipe = recipe
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importedRecipe = nil
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func saveImportedRecipe() {
        guard let importedRecipe else {
            return
        }

        isSaving = true

        let recipe = CDRecipe(context: managedObjectContext)
        recipe.id = UUID()
        recipe.title = importedRecipe.title
        recipe.summaryText = importedRecipe.summary
        recipe.familyOwner = importedRecipe.sourceName
        recipe.isFavorite = false
        recipe.tags = importedRecipe.tags
        recipe.createdAt = .now
        recipe.updatedAt = .now
        recipe.sortOrder = Int32((cookbooks.first?.sortedRecipes.count ?? 0) + 1)
        recipe.cookbook = cookbooks.first

        for (index, ingredientData) in importedRecipe.ingredients.enumerated() {
            let ingredient = CDIngredient(context: managedObjectContext)
            ingredient.id = UUID()
            ingredient.amount = [ingredientData.amount, ingredientData.unit]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            ingredient.name = ingredientData.name
            ingredient.sortOrder = Int32(index)
            ingredient.recipe = recipe
        }

        for (index, stepData) in importedRecipe.steps.enumerated() {
            let step = CDRecipeStep(context: managedObjectContext)
            step.id = UUID()
            step.title = stepData.title
            step.instructionText = stepData.instruction
            step.sortOrder = Int32(index)
            step.recipe = recipe
        }

        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

private struct RecipeStructuredDataParser {
    let html: String
    let sourceURL: URL

    func parse() throws -> ImportedRecipeData {
        let nodes = extractJSONLDNodes()
        for node in nodes {
            if let recipeNode = findRecipeNode(in: node),
               let importedRecipe = importedRecipeData(from: recipeNode) {
                return importedRecipe
            }
        }

        throw RecipeImportError.noRecipeFound
    }

    private func extractJSONLDNodes() -> [Any] {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            guard
                match.numberOfRanges > 1,
                let scriptRange = Range(match.range(at: 1), in: html)
            else {
                return nil
            }

            let raw = html[scriptRange]
                .replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = raw.data(using: .utf8) else {
                return nil
            }

            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private func findRecipeNode(in node: Any) -> [String: Any]? {
        if let dictionary = node as? [String: Any] {
            if isRecipeType(dictionary["@type"]) {
                return dictionary
            }

            if let graph = dictionary["@graph"] as? [Any] {
                for child in graph {
                    if let recipe = findRecipeNode(in: child) {
                        return recipe
                    }
                }
            }

            for value in dictionary.values {
                if let recipe = findRecipeNode(in: value) {
                    return recipe
                }
            }
        } else if let array = node as? [Any] {
            for item in array {
                if let recipe = findRecipeNode(in: item) {
                    return recipe
                }
            }
        }

        return nil
    }

    private func importedRecipeData(from node: [String: Any]) -> ImportedRecipeData? {
        let title = stringValue(node["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return nil
        }

        let summary = stringValue(node["description"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourceName = siteDisplayName(for: sourceURL)

        let rawIngredients = stringArrayValue(node["recipeIngredient"])
        let ingredients = rawIngredients.map(parseIngredient)

        let instructions = parseInstructions(node["recipeInstructions"])
        let steps = instructions.enumerated().map { index, instruction in
            ImportedStep(
                title: "Step \(index + 1)",
                instruction: instruction
            )
        }

        var tags = Set<String>()
        tags.insert("Imported")
        tags.insert(sourceName)

        for keyword in parseKeywords(node["keywords"]) {
            tags.insert(keyword)
        }

        return ImportedRecipeData(
            sourceURL: sourceURL,
            sourceName: sourceName,
            title: title,
            summary: summary,
            tags: Array(tags).sorted(),
            ingredients: ingredients,
            steps: steps
        )
    }

    private func parseIngredient(_ rawIngredient: String) -> ImportedIngredient {
        let trimmed = rawIngredient.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)

        guard tokens.count >= 2 else {
            return ImportedIngredient(amount: "", unit: "", name: trimmed)
        }

        let prefixTokens = tokens.prefix { token in
            token.first?.isNumber == true || token.contains("/") || containsFractionCharacter(String(token))
        }

        guard !prefixTokens.isEmpty else {
            return ImportedIngredient(amount: "", unit: "", name: trimmed)
        }

        let amount = prefixTokens.joined(separator: " ")
        let remainingTokens = Array(tokens.dropFirst(prefixTokens.count))
        guard !remainingTokens.isEmpty else {
            return ImportedIngredient(amount: "", unit: "", name: trimmed)
        }

        let unitCandidates: Set<String> = [
            "tsp", "teaspoon", "teaspoons",
            "tbsp", "tablespoon", "tablespoons",
            "cup", "cups",
            "oz", "ounce", "ounces",
            "lb", "lbs", "pound", "pounds",
            "g", "gram", "grams",
            "kg", "kilogram", "kilograms",
            "ml", "milliliter", "milliliters",
            "l", "liter", "liters",
            "pinch", "pinches",
            "clove", "cloves",
            "can", "cans",
            "package", "packages",
            "slice", "slices",
            "stick", "sticks"
        ]

        let firstRemaining = remainingTokens[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if unitCandidates.contains(firstRemaining) {
            let unit = String(remainingTokens[0])
            let ingredientName = remainingTokens.dropFirst().joined(separator: " ")
            return ImportedIngredient(amount: amount, unit: unit, name: ingredientName.isEmpty ? trimmed : ingredientName)
        }

        return ImportedIngredient(amount: amount, unit: "", name: remainingTokens.joined(separator: " "))
    }

    private func containsFractionCharacter(_ value: String) -> Bool {
        value.rangeOfCharacter(from: CharacterSet(charactersIn: "¼½¾⅓⅔⅛⅜⅝⅞")) != nil
    }

    private func parseInstructions(_ value: Any?) -> [String] {
        let directSteps = stringArrayValue(value)
        if !directSteps.isEmpty {
            return directSteps
        }

        if let dictionary = value as? [String: Any] {
            if let text = stringValue(dictionary["text"]) {
                return [text]
            }

            if let nested = dictionary["itemListElement"] {
                return parseInstructions(nested)
            }
        }

        if let array = value as? [Any] {
            return array.flatMap { item in
                if let text = stringValue(item) {
                    return [text]
                }

                if let dictionary = item as? [String: Any] {
                    if let nested = dictionary["itemListElement"] {
                        return parseInstructions(nested)
                    }

                    let title = stringValue(dictionary["name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = stringValue(dictionary["text"])?.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let title, let text, !title.isEmpty, !text.isEmpty, title != text {
                        return ["\(title): \(text)"]
                    }

                    if let text, !text.isEmpty {
                        return [text]
                    }
                }

                return []
            }
        }

        return []
    }

    private func parseKeywords(_ value: Any?) -> [String] {
        if let raw = stringValue(value) {
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if let array = value as? [Any] {
            return array.compactMap(stringValue)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return []
    }

    private func stringArrayValue(_ value: Any?) -> [String] {
        if let string = stringValue(value) {
            return [string]
        }

        if let array = value as? [Any] {
            return array.compactMap { item in
                if let text = stringValue(item) {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if let dictionary = item as? [String: Any],
                   let text = stringValue(dictionary["text"]) {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                return nil
            }
            .filter { !$0.isEmpty }
        }

        return []
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let dictionary = value as? [String: Any] {
            if let name = dictionary["@value"] as? String {
                return name
            }
        }

        return nil
    }

    private func isRecipeType(_ value: Any?) -> Bool {
        if let type = value as? String {
            return type.localizedCaseInsensitiveContains("Recipe")
        }

        if let types = value as? [Any] {
            return types.compactMap { $0 as? String }.contains { $0.localizedCaseInsensitiveContains("Recipe") }
        }

        return false
    }

    private func siteDisplayName(for url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""

        if host.contains("allrecipes.com") { return "Allrecipes" }
        if host.contains("foodnetwork.com") { return "Food Network" }
        if host.contains("bbcgoodfood.com") { return "BBC Good Food" }
        if host.contains("epicurious.com") { return "Epicurious" }
        if host.contains("seriouseats.com") { return "Serious Eats" }
        if host.contains("nytimes.com") || host.contains("cooking.nytimes.com") { return "NYT Cooking" }
        if host.contains("bonappetit.com") { return "Bon Appetit" }

        return host.replacingOccurrences(of: "www.", with: "")
    }
}
