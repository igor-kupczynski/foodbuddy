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
        guard let meal = try fetchMeal(id: mealID) else {
            return
        }

        meal.aiDescription = description
        meal.aiAnalysisStatus = .completed
        meal.updatedAt = .now
        try save()
    }

    func markFailed(mealID: UUID) throws {
        guard let meal = try fetchMeal(id: mealID) else {
            return
        }

        meal.aiAnalysisStatus = .failed
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
