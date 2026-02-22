import SwiftData
import XCTest

@MainActor
final class FoodAnalysisModelStoreTests: XCTestCase {
    func testMarkCompletedWithFoodItemsMapsSingleCategory() throws {
        let harness = try ModelStoreHarness.make()
        let meal = try harness.makeMeal()

        let store = FoodAnalysisModelStore(modelContext: harness.context)
        try store.markCompletedWithFoodItems(
            mealID: meal.id,
            description: "Sweetened yogurt and berries",
            foodItems: [
                AIFoodItem(name: "Sweetened yogurt", category: "dairy", servings: 1),
                AIFoodItem(name: "Yogurt sugar", category: "sweets", servings: 1),
                AIFoodItem(name: "Blueberries", category: "fruits", servings: 0.5)
            ]
        )

        let storedMeal = try XCTUnwrap(try harness.fetchMeal(id: meal.id))
        XCTAssertEqual(storedMeal.aiDescription, "Sweetened yogurt and berries")
        XCTAssertEqual(storedMeal.aiAnalysisStatus, .completed)
        XCTAssertEqual(storedMeal.foodItems.count, 3)
        XCTAssertEqual(Set(storedMeal.foodItems.map(\.category)), [.dairy, .sweets, .fruits])
    }

    func testMarkCompletedWithFoodItemsDropsUnknownCategoriesAndEmptyNames() throws {
        let harness = try ModelStoreHarness.make()
        let meal = try harness.makeMeal()

        let store = FoodAnalysisModelStore(modelContext: harness.context)
        try store.markCompletedWithFoodItems(
            mealID: meal.id,
            description: "Mixed snack",
            foodItems: [
                AIFoodItem(name: "Mystery", category: "unknown", servings: 1),
                AIFoodItem(name: "  ", category: "fruits", servings: 1),
                AIFoodItem(name: "Apple", category: "fruits", servings: 1)
            ]
        )

        let storedMeal = try XCTUnwrap(try harness.fetchMeal(id: meal.id))
        XCTAssertEqual(storedMeal.foodItems.count, 1)
        XCTAssertEqual(storedMeal.foodItems.first?.name, "Apple")
        XCTAssertEqual(storedMeal.foodItems.first?.category, .fruits)
    }

    func testMarkCompletedWithFoodItemsPreservesManualAndReplacesAIGeneratedItems() throws {
        let harness = try ModelStoreHarness.make()
        let meal = try harness.makeMeal()

        harness.context.insert(
            FoodItem(
                mealId: meal.id,
                name: "Manual almonds",
                categoryRawValue: DQSCategory.nutsAndSeeds.rawValue,
                servings: 1,
                isManual: true,
                meal: meal
            )
        )
        harness.context.insert(
            FoodItem(
                mealId: meal.id,
                name: "Old AI item",
                categoryRawValue: DQSCategory.refinedGrains.rawValue,
                servings: 1,
                isManual: false,
                meal: meal
            )
        )
        try harness.context.save()

        let store = FoodAnalysisModelStore(modelContext: harness.context)
        try store.markCompletedWithFoodItems(
            mealID: meal.id,
            description: "Re-analyzed",
            foodItems: [AIFoodItem(name: "Soup", category: "vegetables", servings: 1)]
        )

        let storedMeal = try XCTUnwrap(try harness.fetchMeal(id: meal.id))
        XCTAssertEqual(storedMeal.foodItems.count, 2)

        let manual = storedMeal.foodItems.filter { $0.isManual }
        let ai = storedMeal.foodItems.filter { !$0.isManual }

        XCTAssertEqual(manual.count, 1)
        XCTAssertEqual(manual.first?.name, "Manual almonds")
        XCTAssertEqual(ai.count, 1)
        XCTAssertEqual(ai.first?.name, "Soup")
        XCTAssertEqual(ai.first?.category, .vegetables)
    }
}

@MainActor
private struct ModelStoreHarness {
    let context: ModelContext

    static func make() throws -> ModelStoreHarness {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Meal.self, MealEntry.self, EntryPhotoAsset.self, MealType.self, FoodItem.self])
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelStoreHarness(context: ModelContext(container))
    }

    func makeMeal() throws -> Meal {
        let mealType = MealType(displayName: "Lunch", isSystem: true)
        context.insert(mealType)
        let meal = Meal(typeId: mealType.id, aiAnalysisStatusRawValue: AIAnalysisStatus.analyzing.rawValue)
        context.insert(meal)
        try context.save()
        return meal
    }

    func fetchMeal(id: UUID) throws -> Meal? {
        let targetID = id
        var descriptor = FetchDescriptor<Meal>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
