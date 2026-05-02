import CoreData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SupabaseAuthManager.self) private var authManager
    @Environment(CookbookSyncCoordinator.self) private var syncCoordinator
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDCookbook.createdAt, ascending: true)], animation: .default)
    private var cookbooks: FetchedResults<CDCookbook>
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CDShoppingListItem.isChecked, ascending: true),
            NSSortDescriptor(keyPath: \CDShoppingListItem.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \CDShoppingListItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var shoppingItems: FetchedResults<CDShoppingListItem>

    @State private var newItemName = ""
    @State private var newAmountText = ""

    private var cookbook: CDCookbook? {
        cookbooks.first
    }

    private var items: [CDShoppingListItem] {
        Array(shoppingItems)
    }

    var body: some View {
        List {
            Section("Add Item") {
                TextField("Item", text: $newItemName)
                    .submitLabel(.done)
                    .onSubmit {
                        addManualItem()
                    }

                TextField("Amount (optional)", text: $newAmountText)
                    .submitLabel(.done)
                    .onSubmit {
                        addManualItem()
                    }

                Button("Add to Shopping List") {
                    addManualItem()
                }
                .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Shopping List") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Shopping Items",
                        systemImage: "cart",
                        description: Text("Add ingredients from a recipe or jot down a manual item here.")
                    )
                } else {
                    ForEach(items, id: \.objectID) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                toggleChecked(item)
                            } label: {
                                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isChecked ? .green : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    if !item.amountText.isEmpty {
                                        Text(item.amountText)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(item.itemName)
                                        .strikethrough(item.isChecked)
                                }
                                .font(.body)

                                if !item.sourceRecipeTitle.isEmpty {
                                    Text("From \(item.sourceRecipeTitle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Shopping List")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if items.contains(where: \.isChecked) {
                    Button("Clear Checked") {
                        clearCheckedItems()
                    }
                }
            }
        }
        .refreshable {
            guard authManager.state.isAuthenticated else {
                return
            }

            await syncCoordinator.pullSilently()
        }
    }

    private func addManualItem() {
        guard let cookbook else {
            return
        }

        let trimmedItemName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedItemName.isEmpty else {
            return
        }

        let item = CDShoppingListItem(context: managedObjectContext)
        item.id = UUID()
        item.itemName = trimmedItemName
        item.amountText = newAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        item.sourceRecipeTitle = ""
        item.note = ""
        item.isChecked = false
        item.sortOrder = Int32(items.count + 1)
        item.createdAt = .now
        item.updatedAt = .now
        item.cookbook = cookbook
        cookbook.updatedAt = .now

        try? managedObjectContext.save()
        newItemName = ""
        newAmountText = ""
    }

    private func toggleChecked(_ item: CDShoppingListItem) {
        item.isChecked.toggle()
        item.updatedAt = .now
        cookbook?.updatedAt = .now
        try? managedObjectContext.save()
    }

    private func deleteItem(_ item: CDShoppingListItem) {
        managedObjectContext.delete(item)
        cookbook?.updatedAt = .now
        try? managedObjectContext.save()
    }

    private func clearCheckedItems() {
        for item in items where item.isChecked {
            managedObjectContext.delete(item)
        }
        cookbook?.updatedAt = .now
        try? managedObjectContext.save()
    }
}

#Preview {
    NavigationStack {
        ShoppingListView()
    }
    .environment(\.managedObjectContext, FamilyCookbookCoreDataPreview.stack.viewContext)
    .environment(SupabaseAuthManager(configuration: .fromBundle(), client: nil))
    .environment(
        CookbookSyncCoordinator(
            coreDataStack: FamilyCookbookCoreDataPreview.stack,
            syncService: SupabaseSyncFactory.makeSyncService(configuration: .fromBundle())
        )
    )
}
