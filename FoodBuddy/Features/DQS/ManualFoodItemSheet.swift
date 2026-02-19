import SwiftUI

struct ManualFoodItemSheet: View {
    enum Source {
        case meal(mealID: UUID)
        case day(date: Date)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let source: Source

    @State private var name = ""
    @State private var category: DQSCategory = .vegetables
    @State private var servings: Double = 1
    @State private var mealTypes: [MealType] = []
    @State private var selectedMealTypeID: UUID?
    @State private var isShowingCategoryGuide = false
    @State private var errorMessage: String?

    private var mealTypeService: MealTypeService {
        MealTypeService(modelContext: modelContext)
    }

    private var mealService: MealService {
        MealService(modelContext: modelContext)
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
        NavigationStack {
            Form {
                Section("Food Item") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("dqs-manual-food-item-name")

                    Picker("Category", selection: $category) {
                        ForEach(DQSCategory.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .accessibilityIdentifier("dqs-manual-food-item-category")

                    Button {
                        isShowingCategoryGuide = true
                    } label: {
                        Label("Category & Serving Help", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("dqs-manual-food-item-help")

                    Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                        Text("Servings: \(servings.formatted(.number.precision(.fractionLength(0...1))))")
                    }
                    .accessibilityIdentifier("dqs-manual-food-item-servings")
                }

                if case .day = source {
                    Section("Meal Type") {
                        if mealTypes.isEmpty {
                            Text("No meal types available")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Meal Type", selection: $selectedMealTypeID) {
                                ForEach(mealTypes) { mealType in
                                    Text(mealType.displayName)
                                        .tag(Optional(mealType.id))
                                }
                            }
                            .accessibilityIdentifier("dqs-manual-food-item-meal-type")
                        }
                    }
                }
            }
            .navigationTitle("Add Food Item")
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
                    .accessibilityIdentifier("dqs-manual-food-item-save")
                }
            }
            .task {
                await loadMealTypesIfNeeded()
            }
            .sheet(isPresented: $isShowingCategoryGuide) {
                DQSCategoryGuideView()
            }
            .alert("Could Not Save Food Item", isPresented: isShowingError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(errorMessage ?? "Unknown error")
            })
        }
    }

    private func loadMealTypesIfNeeded() async {
        guard case .day(let date) = source else {
            return
        }

        do {
            try mealTypeService.bootstrapDefaultTypesIfNeeded()
            mealTypes = try mealTypeService.fetchAll()
            if selectedMealTypeID == nil {
                selectedMealTypeID = try mealTypeService.suggestMealType(for: date)?.id ?? mealTypes.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let targetMealID: UUID

            switch source {
            case .meal(let mealID):
                targetMealID = mealID
            case .day(let date):
                if selectedMealTypeID == nil {
                    try mealTypeService.bootstrapDefaultTypesIfNeeded()
                    let fallbackTypes = try mealTypeService.fetchAll()
                    selectedMealTypeID = try mealTypeService.suggestMealType(for: date)?.id ?? fallbackTypes.first?.id
                }
                guard let mealTypeID = selectedMealTypeID else {
                    throw FoodItemService.Error.missingMeal
                }
                let meal = try mealService.meal(for: mealTypeID, loggedAt: date)
                targetMealID = meal.id
            }

            _ = try foodItemService.createFoodItem(
                mealID: targetMealID,
                name: name,
                category: category,
                servings: servings,
                isManual: true
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
