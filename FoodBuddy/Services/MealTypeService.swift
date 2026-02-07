import Foundation
import SwiftData

@MainActor
final class MealTypeService {
    static let defaultTypeNames: [String] = [
        "Breakfast",
        "Lunch",
        "Dinner",
        "Afternoon Snack",
        "Snack",
        "Workout Fuel",
        "Protein Shake"
    ]

    enum Error: Swift.Error {
        case invalidName
        case duplicateName
        case missingMealType
    }

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

    func bootstrapDefaultTypesIfNeeded() throws {
        if try !fetchAll().isEmpty {
            return
        }

        let now = nowProvider()
        for name in Self.defaultTypeNames {
            modelContext.insert(
                MealType(
                    id: uuidProvider(),
                    displayName: name,
                    isSystem: true,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try save()
    }

    func fetchAll() throws -> [MealType] {
        let descriptor = FetchDescriptor<MealType>(
            sortBy: [SortDescriptor(\MealType.displayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchType(id: UUID) throws -> MealType? {
        let targetID = id
        var descriptor = FetchDescriptor<MealType>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchFallbackSnackType() throws -> MealType? {
        if let snack = try fetchType(named: "Snack") {
            return snack
        }
        return try fetchAll().first
    }

    func suggestMealType(for date: Date) throws -> MealType? {
        let hour = calendar.component(.hour, from: date)

        let suggestedName: String
        if hour < 11 {
            suggestedName = "Breakfast"
        } else if hour < 15 {
            suggestedName = "Lunch"
        } else if hour < 18 {
            suggestedName = "Afternoon Snack"
        } else {
            suggestedName = "Dinner"
        }

        if let type = try fetchType(named: suggestedName) {
            return type
        }

        return try fetchFallbackSnackType()
    }

    @discardableResult
    func createCustomType(named rawName: String) throws -> MealType {
        let name = sanitizeName(rawName)
        guard !name.isEmpty else {
            throw Error.invalidName
        }

        if try fetchType(named: name) != nil {
            throw Error.duplicateName
        }

        let now = nowProvider()
        let type = MealType(
            id: uuidProvider(),
            displayName: name,
            isSystem: false,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(type)
        try save()
        return type
    }

    func rename(typeID: UUID, to rawName: String) throws {
        guard let type = try fetchType(id: typeID) else {
            throw Error.missingMealType
        }

        let name = sanitizeName(rawName)
        guard !name.isEmpty else {
            throw Error.invalidName
        }

        if let duplicate = try fetchType(named: name), duplicate.id != type.id {
            throw Error.duplicateName
        }

        if type.displayName == name {
            return
        }

        type.displayName = name
        type.updatedAt = nowProvider()
        try save()
    }

    private func fetchType(named rawName: String) throws -> MealType? {
        let normalized = sanitizeName(rawName).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return try fetchAll().first(where: {
            sanitizeName($0.displayName).lowercased() == normalized
        })
    }

    private func sanitizeName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
