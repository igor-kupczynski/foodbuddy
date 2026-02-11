import SwiftData
import XCTest

@MainActor
final class MealAIAnalysisStatusTests: XCTestCase {
    func testMealAIFieldsRoundTripThroughSwiftData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let mealType = MealType(displayName: "Lunch", isSystem: true)
        context.insert(mealType)

        let meal = Meal(
            typeId: mealType.id,
            aiDescription: "Grilled salmon with rice",
            userNotes: "Restaurant special",
            aiAnalysisStatusRawValue: AIAnalysisStatus.completed.rawValue
        )
        context.insert(meal)
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<Meal>()).first)
        XCTAssertEqual(stored.aiDescription, "Grilled salmon with rice")
        XCTAssertEqual(stored.userNotes, "Restaurant special")
        XCTAssertEqual(stored.aiAnalysisStatus, .completed)
        XCTAssertEqual(stored.aiAnalysisStatusRawValue, AIAnalysisStatus.completed.rawValue)
    }

    func testAIAnalysisStatusRoundTripAndUnknownFallback() {
        for status in AIAnalysisStatus.allCases {
            XCTAssertEqual(AIAnalysisStatus(rawValue: status.rawValue), status)
        }

        let meal = Meal(typeId: UUID(), aiAnalysisStatusRawValue: "unexpected-value")
        XCTAssertEqual(meal.aiAnalysisStatus, .none)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Meal.self, MealEntry.self, EntryPhotoAsset.self, MealType.self])
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
