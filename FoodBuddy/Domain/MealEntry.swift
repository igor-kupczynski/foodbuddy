import Foundation
import SwiftData

@Model
final class MealEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var imageFilename: String

    init(id: UUID = UUID(), createdAt: Date = .now, imageFilename: String) {
        self.id = id
        self.createdAt = createdAt
        self.imageFilename = imageFilename
    }
}
