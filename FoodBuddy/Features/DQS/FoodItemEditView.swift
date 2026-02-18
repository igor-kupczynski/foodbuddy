import SwiftUI

struct FoodItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let foodItem: FoodItem

    @State private var name: String
    @State private var category: DQSCategory
    @State private var servings: Double
    @State private var isShowingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(foodItem: FoodItem) {
        self.foodItem = foodItem
        _name = State(initialValue: foodItem.name)
        _category = State(initialValue: foodItem.category)
        _servings = State(initialValue: max(0.5, foodItem.servings))
    }

    private var foodItemService: FoodItemService {
        Dependencies.makeFoodItemService(modelContext: modelContext)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Food Item") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("dqs-food-item-edit-name")

                Picker("Category", selection: $category) {
                    ForEach(DQSCategory.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .accessibilityIdentifier("dqs-food-item-edit-category")

                Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                    Text("Servings: \(servings.formatted(.number.precision(.fractionLength(0...1))))")
                }
                .accessibilityIdentifier("dqs-food-item-edit-servings")
            }

            Section {
                Button("Delete Food Item", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .accessibilityIdentifier("dqs-food-item-edit-delete")
            }
        }
        .navigationTitle("Edit Food Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("dqs-food-item-edit-save")
            }
        }
        .confirmationDialog(
            "Delete this food item?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteItem()
            }
            .accessibilityIdentifier("dqs-food-item-edit-confirm-delete")

            Button("Cancel", role: .cancel) {}
        }
        .alert("Could Not Save Food Item", isPresented: isShowingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    private func save() {
        do {
            try foodItemService.updateFoodItem(
                foodItem,
                name: name,
                category: category,
                servings: servings
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem() {
        do {
            try foodItemService.deleteFoodItem(foodItem)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
