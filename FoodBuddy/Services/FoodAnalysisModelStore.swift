import Foundation
import SwiftData

struct PendingMealAnalysis: Sendable {
    let mealID: UUID
    let imageFilenames: [String]
    let notes: String?
}

@MainActor
final class FoodAnalysisModelStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func claimNextPendingMeal() throws -> PendingMealAnalysis? {
        let pendingRawValue = AIAnalysisStatus.pending.rawValue
        var descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.aiAnalysisStatusRawValue == pendingRawValue },
            sortBy: [SortDescriptor(\Meal.updatedAt)]
        )
        descriptor.fetchLimit = 1

        guard let meal = try modelContext.fetch(descriptor).first else {
            return nil
        }

        // Idempotent guard for duplicate runs triggered by repeated foreground events.
        guard meal.aiAnalysisStatus == .pending else {
            return nil
        }

        meal.aiAnalysisStatus = .analyzing
        meal.aiAnalysisErrorDetails = nil
        try save()

        let filenames = meal.entries
            .sorted(by: { $0.loggedAt < $1.loggedAt })
            .compactMap { $0.photoAsset?.fullImageFilename ?? $0.imageFilename }

        return PendingMealAnalysis(
            mealID: meal.id,
            imageFilenames: filenames,
            notes: meal.userNotes
        )
    }

    func markCompleted(mealID: UUID, description: String) throws {
        try markCompletedWithFoodItems(mealID: mealID, description: description, foodItems: [])
    }

    func markCompletedWithFoodItems(
        mealID: UUID,
        description: String,
        foodItems: [AIFoodItem]
    ) throws {
        guard let meal = try fetchMeal(id: mealID) else {
            return
        }

        let now = Date.now
        let aiManagedItems = meal.foodItems.filter { !$0.isManual }
        for existing in aiManagedItems {
            modelContext.delete(existing)
        }

        for analyzedItem in foodItems {
            let name = analyzedItem.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, analyzedItem.servings > 0 else {
                continue
            }

            var insertedCategories = Set<DQSCategory>()
            for rawCategory in analyzedItem.categories {
                guard let category = DQSCategory(apiIdentifier: rawCategory) else {
                    continue
                }
                if !insertedCategories.insert(category).inserted {
                    continue
                }

                modelContext.insert(
                    FoodItem(
                        mealId: meal.id,
                        name: name,
                        categoryRawValue: category.rawValue,
                        servings: analyzedItem.servings,
                        isManual: false,
                        createdAt: now,
                        updatedAt: now,
                        meal: meal
                    )
                )
            }
        }

        meal.aiDescription = description
        meal.aiAnalysisErrorDetails = nil
        meal.aiAnalysisStatus = .completed
        meal.updatedAt = now
        try save()
    }

    func markFailed(mealID: UUID, errorDetails: String?) throws {
        guard let meal = try fetchMeal(id: mealID) else {
            return
        }

        meal.aiAnalysisStatus = .failed
        meal.aiAnalysisErrorDetails = errorDetails
        meal.updatedAt = .now
        try save()
    }

    private func fetchMeal(id: UUID) throws -> Meal? {
        let targetID = id
        var descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
