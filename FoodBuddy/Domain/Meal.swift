import Foundation
import SwiftData

@Model
final class Meal: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var typeId: UUID
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MealEntry.meal)
    var entries: [MealEntry]

    init(
        id: UUID = UUID(),
        typeId: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        entries: [MealEntry] = []
    ) {
        self.id = id
        self.typeId = typeId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
    }
}
