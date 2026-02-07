import Foundation
import SwiftData

@Model
final class MealEntry: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var mealId: UUID
    var photoAssetId: UUID?
    var imageFilename: String
    var capturedAt: Date
    var loggedAt: Date
    var updatedAt: Date

    @Relationship
    var meal: Meal?

    @Relationship(deleteRule: .cascade, inverse: \EntryPhotoAsset.entry)
    var photoAsset: EntryPhotoAsset?

    init(
        id: UUID = UUID(),
        mealId: UUID,
        photoAssetId: UUID? = nil,
        imageFilename: String,
        capturedAt: Date = .now,
        loggedAt: Date = .now,
        updatedAt: Date = .now,
        meal: Meal? = nil,
        photoAsset: EntryPhotoAsset? = nil
    ) {
        self.id = id
        self.mealId = mealId
        self.photoAssetId = photoAssetId
        self.imageFilename = imageFilename
        self.capturedAt = capturedAt
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
        self.meal = meal
        self.photoAsset = photoAsset
    }
}
