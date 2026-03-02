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
    private let nowProvider: () -> Date

    init(
        modelContext: ModelContext,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.nowProvider = nowProvider
    }

    func claimNextPendingMeal() throws -> PendingMealAnalysis? {
        let pendingRawValue = AIAnalysisStatus.pending.rawValue
        let now = nowProvider()
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.aiAnalysisStatusRawValue == pendingRawValue },
            sortBy: [SortDescriptor(\Meal.updatedAt)]
        )

        guard let meal = try modelContext.fetch(descriptor).first(where: { meal in
            guard let nextRetryAt = meal.aiAnalysisNextRetryAt else {
                return true
            }
            return nextRetryAt <= now
        }) else {
            return nil
        }

        // Idempotent guard for duplicate runs triggered by repeated foreground events.
        guard meal.aiAnalysisStatus == .pending else {
            return nil
        }

        meal.aiAnalysisStatus = .analyzing
        meal.aiAnalysisErrorDetails = nil
        meal.aiAnalysisNextRetryAt = nil
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

            guard let category = DQSCategory(apiIdentifier: analyzedItem.category) else {
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

        meal.aiDescription = description
        meal.aiAnalysisErrorDetails = nil
        meal.aiAnalysisNextRetryAt = nil
        meal.aiAnalysisStatus = .completed
        meal.updatedAt = now
        try save()
    }

    func markPendingRetry(mealID: UUID, errorDetails: String?, nextRetryAt: Date) throws {
        guard let meal = try fetchMeal(id: mealID) else {
            return
        }

        meal.aiAnalysisStatus = .pending
        meal.aiAnalysisErrorDetails = errorDetails
        meal.aiAnalysisNextRetryAt = nextRetryAt
        meal.updatedAt = nowProvider()
        try save()
    }

    func markFailed(mealID: UUID, errorDetails: String?) throws {
        guard let meal = try fetchMeal(id: mealID) else {
            return
        }

        meal.aiAnalysisStatus = .failed
        meal.aiAnalysisErrorDetails = errorDetails
        meal.aiAnalysisNextRetryAt = nil
        meal.updatedAt = nowProvider()
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
