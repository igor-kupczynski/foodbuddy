import Foundation
import SwiftData

@Model
final class MealType: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var isSystem: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        isSystem: Bool,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
