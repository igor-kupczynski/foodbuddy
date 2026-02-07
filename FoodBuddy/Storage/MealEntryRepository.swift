import Foundation
import SwiftData

@MainActor
protocol MealEntryRepository {
    func insert(_ entry: MealEntry) throws
    func fetchByID(_ id: UUID) throws -> MealEntry?
    func fetchAllNewestFirst() throws -> [MealEntry]
    func delete(_ entry: MealEntry) throws
    func save() throws
}

@MainActor
struct SwiftDataMealEntryRepository: MealEntryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func insert(_ entry: MealEntry) throws {
        modelContext.insert(entry)
    }

    func fetchByID(_ id: UUID) throws -> MealEntry? {
        let targetID = id
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchAllNewestFirst() throws -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\MealEntry.loggedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func delete(_ entry: MealEntry) throws {
        modelContext.delete(entry)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
