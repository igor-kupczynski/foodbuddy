import Foundation
import SwiftData

@Model
final class Meal: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var typeId: UUID
    var createdAt: Date
    var updatedAt: Date
    var aiDescription: String?
    var userNotes: String?
    var aiAnalysisStatusRawValue: String = AIAnalysisStatus.none.rawValue

    @Relationship(deleteRule: .cascade, inverse: \MealEntry.meal)
    var entries: [MealEntry] = []

    var aiAnalysisStatus: AIAnalysisStatus {
        get {
            AIAnalysisStatus(rawValue: aiAnalysisStatusRawValue) ?? .none
        }
        set {
            aiAnalysisStatusRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        typeId: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        aiDescription: String? = nil,
        userNotes: String? = nil,
        aiAnalysisStatusRawValue: String = AIAnalysisStatus.none.rawValue,
        entries: [MealEntry] = []
    ) {
        self.id = id
        self.typeId = typeId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.aiDescription = aiDescription
        self.userNotes = userNotes
        self.aiAnalysisStatusRawValue = aiAnalysisStatusRawValue
        self.entries = entries
    }
}
