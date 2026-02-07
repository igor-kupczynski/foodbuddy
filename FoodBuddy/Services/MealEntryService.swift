import Foundation
import SwiftData

@MainActor
protocol MealEntryIngesting {
    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry
}

enum LoggedAtUpdateResult: Equatable {
    case updatedWithoutReassignment
    case requiresMealReassignmentConfirmation
    case updatedWithReassignment
}

@MainActor
final class MealEntryService: MealEntryIngesting {
    enum Error: Swift.Error {
        case missingMealType
        case missingMeal
    }

    private let modelContext: ModelContext
    private let imageStore: ImageStore
    private let mealService: MealService
    private let mealTypeService: MealTypeService
    private let nowProvider: () -> Date
    private let uuidProvider: () -> UUID

    init(
        modelContext: ModelContext,
        imageStore: ImageStore,
        mealService: MealService? = nil,
        mealTypeService: MealTypeService? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.modelContext = modelContext
        self.imageStore = imageStore
        self.nowProvider = nowProvider
        self.uuidProvider = uuidProvider
        self.mealService = mealService ?? MealService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
        self.mealTypeService = mealTypeService ?? MealTypeService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
    }

    func bootstrapMealTypesIfNeeded() throws {
        try mealTypeService.bootstrapDefaultTypesIfNeeded()
    }

    func listEntriesNewestFirst() throws -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\MealEntry.loggedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func listMealTypes() throws -> [MealType] {
        try mealTypeService.fetchAll()
    }

    func suggestedMealType(for date: Date) throws -> MealType? {
        try mealTypeService.suggestMealType(for: date)
    }

    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry {
        let loggedAt = nowProvider()
        guard let mealType = try mealTypeService.suggestMealType(for: loggedAt)
            ?? mealTypeService.fetchFallbackSnackType() else {
            throw Error.missingMealType
        }

        return try ingest(image: image, mealTypeID: mealType.id, loggedAt: loggedAt)
    }

    @discardableResult
    func ingest(image: PlatformImage, mealTypeID: UUID, loggedAt: Date) throws -> MealEntry {
        let now = nowProvider()
        let capturedAt = now
        let imageFilename = try imageStore.saveJPEG(image)

        do {
            guard let mealType = try mealTypeService.fetchType(id: mealTypeID) else {
                throw Error.missingMealType
            }

            let meal = try mealService.meal(for: mealType.id, loggedAt: loggedAt)
            mealService.touch(meal)

            let entry = MealEntry(
                id: uuidProvider(),
                mealId: meal.id,
                imageFilename: imageFilename,
                capturedAt: capturedAt,
                loggedAt: loggedAt,
                updatedAt: now,
                meal: meal
            )
            modelContext.insert(entry)
            try save()
            return entry
        } catch {
            try? imageStore.deleteImage(filename: imageFilename)
            throw error
        }
    }

    func delete(entry: MealEntry) throws {
        let meal: Meal?
        if let existingMeal = entry.meal {
            meal = existingMeal
        } else {
            meal = try mealService.fetchMeal(id: entry.mealId)
        }
        try imageStore.deleteImage(filename: entry.imageFilename)
        modelContext.delete(entry)

        if let meal {
            mealService.touch(meal)
            mealService.deleteMealIfEmpty(meal)
        }

        try save()
    }

    func delete(entryID: UUID) throws {
        guard let entry = try fetchEntry(id: entryID) else {
            return
        }
        try delete(entry: entry)
    }

    func updateLoggedAt(
        entry: MealEntry,
        newLoggedAt: Date,
        allowMealReassignment: Bool
    ) throws -> LoggedAtUpdateResult {
        let resolvedMeal: Meal?
        if let existingMeal = entry.meal {
            resolvedMeal = existingMeal
        } else {
            resolvedMeal = try mealService.fetchMeal(id: entry.mealId)
        }

        guard let currentMeal = resolvedMeal else {
            throw Error.missingMeal
        }

        let needsReassignment = mealService.requiresReassignment(
            currentMeal: currentMeal,
            newLoggedAt: newLoggedAt
        )

        if needsReassignment, !allowMealReassignment {
            return .requiresMealReassignmentConfirmation
        }

        let now = nowProvider()
        entry.loggedAt = newLoggedAt
        entry.updatedAt = now

        if needsReassignment {
            let destination = try mealService.meal(for: currentMeal.typeId, loggedAt: newLoggedAt)
            if destination.id != currentMeal.id {
                entry.meal = destination
                entry.mealId = destination.id
                mealService.touch(destination)
            }
            mealService.touch(currentMeal)
            mealService.deleteMealIfEmpty(currentMeal)
            try save()
            return .updatedWithReassignment
        }

        mealService.touch(currentMeal)
        try save()
        return .updatedWithoutReassignment
    }

    @discardableResult
    func createCustomMealType(named name: String) throws -> MealType {
        try mealTypeService.createCustomType(named: name)
    }

    func renameMealType(id: UUID, to name: String) throws {
        try mealTypeService.rename(typeID: id, to: name)
    }

    private func fetchEntry(id: UUID) throws -> MealEntry? {
        let targetID = id
        var descriptor = FetchDescriptor<MealEntry>(
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
