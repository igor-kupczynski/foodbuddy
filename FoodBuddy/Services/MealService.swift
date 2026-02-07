import Foundation
import SwiftData

@MainActor
final class MealService {
    private let modelContext: ModelContext
    private let nowProvider: () -> Date
    private let uuidProvider: () -> UUID
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        nowProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.nowProvider = nowProvider
        self.uuidProvider = uuidProvider
        self.calendar = calendar
    }

    func fetchMeal(id: UUID) throws -> Meal? {
        let targetID = id
        var descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func meal(for typeID: UUID, loggedAt: Date) throws -> Meal {
        if let existing = try findMeal(typeID: typeID, sameDayAs: loggedAt) {
            return existing
        }

        let now = nowProvider()
        let meal = Meal(
            id: uuidProvider(),
            typeId: typeID,
            createdAt: calendar.startOfDay(for: loggedAt),
            updatedAt: now
        )
        modelContext.insert(meal)
        return meal
    }

    func requiresReassignment(currentMeal: Meal, newLoggedAt: Date) -> Bool {
        !calendar.isDate(currentMeal.createdAt, inSameDayAs: newLoggedAt)
    }

    func touch(_ meal: Meal) {
        meal.updatedAt = nowProvider()
    }

    func deleteMealIfEmpty(_ meal: Meal) {
        if meal.entries.isEmpty {
            modelContext.delete(meal)
        }
    }

    private func findMeal(typeID: UUID, sameDayAs date: Date) throws -> Meal? {
        let targetTypeID = typeID
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.typeId == targetTypeID }
        )
        return try modelContext.fetch(descriptor).first(where: { meal in
            calendar.isDate(meal.createdAt, inSameDayAs: date)
        })
    }
}
