import Foundation
import SwiftData

@MainActor
final class FoodItemService {
    enum Error: Swift.Error {
        case missingMeal
        case invalidName
        case invalidServings
    }

    private let modelContext: ModelContext
    private let mealService: MealService
    private let nowProvider: () -> Date
    private let uuidProvider: () -> UUID

    init(
        modelContext: ModelContext,
        mealService: MealService? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.modelContext = modelContext
        self.nowProvider = nowProvider
        self.uuidProvider = uuidProvider
        self.mealService = mealService ?? MealService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
    }

    @discardableResult
    func createFoodItem(
        mealID: UUID,
        name: String,
        category: DQSCategory,
        servings: Double,
        isManual: Bool
    ) throws -> FoodItem {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw Error.invalidName
        }
        guard servings > 0 else {
            throw Error.invalidServings
        }

        guard let meal = try mealService.fetchMeal(id: mealID) else {
            throw Error.missingMeal
        }

        let now = nowProvider()
        let item = FoodItem(
            id: uuidProvider(),
            mealId: meal.id,
            name: normalizedName,
            categoryRawValue: category.rawValue,
            servings: servings,
            isManual: isManual,
            createdAt: now,
            updatedAt: now,
            meal: meal
        )

        modelContext.insert(item)
        mealService.touch(meal)
        try save()
        return item
    }

    func updateFoodItem(
        _ foodItem: FoodItem,
        name: String,
        category: DQSCategory,
        servings: Double
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw Error.invalidName
        }
        guard servings > 0 else {
            throw Error.invalidServings
        }

        foodItem.name = normalizedName
        foodItem.category = category
        foodItem.servings = servings
        foodItem.isManual = true
        foodItem.updatedAt = nowProvider()

        let meal: Meal?
        if let attachedMeal = foodItem.meal {
            meal = attachedMeal
        } else {
            meal = try mealService.fetchMeal(id: foodItem.mealId)
        }
        if let meal {
            mealService.touch(meal)
        }

        try save()
    }

    func deleteFoodItem(_ foodItem: FoodItem) throws {
        let meal: Meal?
        if let attachedMeal = foodItem.meal {
            meal = attachedMeal
        } else {
            meal = try mealService.fetchMeal(id: foodItem.mealId)
        }
        modelContext.delete(foodItem)

        if let meal {
            mealService.touch(meal)
            mealService.deleteMealIfEmpty(meal)
        }

        try save()
    }

    func foodItems(forMealIDs mealIDs: [UUID]) throws -> [FoodItem] {
        guard !mealIDs.isEmpty else {
            return []
        }

        let idSet = Set(mealIDs)
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { idSet.contains($0.mealId) },
            sortBy: [
                SortDescriptor(\FoodItem.updatedAt, order: .reverse),
                SortDescriptor(\FoodItem.name)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
