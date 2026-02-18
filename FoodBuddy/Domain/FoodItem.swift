import Foundation
import SwiftData

@Model
final class FoodItem: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var mealId: UUID
    var name: String
    var categoryRawValue: String = DQSCategory.vegetables.rawValue
    var servings: Double = 1.0
    var isManual: Bool = false
    var createdAt: Date
    var updatedAt: Date

    @Relationship var meal: Meal?

    var category: DQSCategory {
        get {
            DQSCategory(rawValue: categoryRawValue) ?? .vegetables
        }
        set {
            categoryRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        mealId: UUID,
        name: String,
        categoryRawValue: String = DQSCategory.vegetables.rawValue,
        servings: Double = 1.0,
        isManual: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        meal: Meal? = nil
    ) {
        self.id = id
        self.mealId = mealId
        self.name = name
        self.categoryRawValue = categoryRawValue
        self.servings = servings
        self.isManual = isManual
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.meal = meal
    }
}
