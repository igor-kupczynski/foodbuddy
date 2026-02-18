import SwiftData
import XCTest

@MainActor
final class MealServiceTests: XCTestCase {
    func testDeleteMealIfEmptyDeletesWhenNoEntriesAndNoFoodItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = Meal(typeId: UUID())
        context.insert(meal)
        try context.save()

        let service = MealService(modelContext: context)
        service.deleteMealIfEmpty(meal)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<Meal>()).isEmpty)
    }

    func testDeleteMealIfEmptyKeepsMealWhenFoodItemsExist() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = Meal(typeId: UUID())
        context.insert(meal)
        context.insert(
            FoodItem(
                mealId: meal.id,
                name: "Apple",
                categoryRawValue: DQSCategory.fruits.rawValue,
                meal: meal
            )
        )
        try context.save()

        let service = MealService(modelContext: context)
        service.deleteMealIfEmpty(meal)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Meal>()).count, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Meal.self, MealEntry.self, EntryPhotoAsset.self, MealType.self, FoodItem.self])
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
