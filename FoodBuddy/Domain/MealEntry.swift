import Foundation
import SwiftData

@Model
final class MealEntry: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var mealId: UUID
    var imageFilename: String
    var capturedAt: Date
    var loggedAt: Date
    var updatedAt: Date

    @Relationship
    var meal: Meal?

    init(
        id: UUID = UUID(),
        mealId: UUID,
        imageFilename: String,
        capturedAt: Date = .now,
        loggedAt: Date = .now,
        updatedAt: Date = .now,
        meal: Meal? = nil
    ) {
        self.id = id
        self.mealId = mealId
        self.imageFilename = imageFilename
        self.capturedAt = capturedAt
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
        self.meal = meal
    }
}
