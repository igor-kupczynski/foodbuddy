import Foundation
import SwiftData

enum DQSFixtureSeeder {
    static func seedIfRequested(in container: ModelContainer) {
        guard let fixture = AppRuntimeFlags.dqsFixture, !fixture.isEmpty else {
            return
        }

        guard fixture == "baseline" else {
            return
        }

        do {
            let context = ModelContext(container)
            try clearExistingData(context: context)
            try seedBaselineFixture(context: context)
        } catch {
            assertionFailure("Failed seeding DQS fixture: \(error)")
        }
    }

    private static func clearExistingData(context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<FoodItem>()) {
            context.delete(item)
        }
        for entry in try context.fetch(FetchDescriptor<MealEntry>()) {
            context.delete(entry)
        }
        for asset in try context.fetch(FetchDescriptor<EntryPhotoAsset>()) {
            context.delete(asset)
        }
        for meal in try context.fetch(FetchDescriptor<Meal>()) {
            context.delete(meal)
        }
        for mealType in try context.fetch(FetchDescriptor<MealType>()) {
            context.delete(mealType)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private static func seedBaselineFixture(context: ModelContext) throws {
        let calendar = Calendar.current
        let now = Date.now
        let mealTypeNames = [
            "Breakfast",
            "Lunch",
            "Dinner",
            "Afternoon Snack",
            "Snack",
            "Workout Fuel",
            "Protein Shake"
        ]
        var createdMealTypes: [String: MealType] = [:]
        for name in mealTypeNames {
            let mealType = MealType(
                displayName: name,
                isSystem: true,
                createdAt: now,
                updatedAt: now
            )
            context.insert(mealType)
            createdMealTypes[name] = mealType
        }

        guard let breakfastType = createdMealTypes["Breakfast"],
              let lunchType = createdMealTypes["Lunch"] else {
            return
        }

        let day = calendar.startOfDay(for: now)

        let breakfastMeal = Meal(
            typeId: breakfastType.id,
            createdAt: day,
            updatedAt: day.addingTimeInterval(60 * 60),
            aiDescription: "Fixture breakfast",
            aiAnalysisStatusRawValue: AIAnalysisStatus.completed.rawValue
        )
        let lunchMeal = Meal(
            typeId: lunchType.id,
            createdAt: day,
            updatedAt: day.addingTimeInterval(2 * 60 * 60),
            aiDescription: "Fixture lunch",
            aiAnalysisStatusRawValue: AIAnalysisStatus.completed.rawValue
        )

        context.insert(breakfastMeal)
        context.insert(lunchMeal)

        let items: [(Meal, String, DQSCategory, Double)] = [
            (breakfastMeal, "Apple", .fruits, 1),
            (breakfastMeal, "Sweetened yogurt", .dairy, 1),
            (breakfastMeal, "Sweetened yogurt", .sweets, 1),
            (breakfastMeal, "Oatmeal", .wholeGrains, 1),
            (lunchMeal, "Salad", .vegetables, 1),
            (lunchMeal, "Chicken breast", .leanMeatsAndFish, 1),
            (lunchMeal, "Beans", .legumesAndPlantProteins, 1),
            (lunchMeal, "Almonds", .nutsAndSeeds, 1)
        ]

        for (meal, name, category, servings) in items {
            context.insert(
                FoodItem(
                    mealId: meal.id,
                    name: name,
                    categoryRawValue: category.rawValue,
                    servings: servings,
                    isManual: false,
                    createdAt: now,
                    updatedAt: now,
                    meal: meal
                )
            )
        }

        if context.hasChanges {
            try context.save()
        }
    }
}
