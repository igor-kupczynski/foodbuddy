import SwiftData
import XCTest

@MainActor
final class FoodAnalysisCoordinatorTests: XCTestCase {
    func testCoordinatorHappyPathSetsCompletedAndDescription() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        let recognitionSpy = FoodRecognitionSpy(behavior: .success("Pasta with tomato sauce"))
        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: recognitionSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )

        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.aiAnalysisStatus, .completed)
        XCTAssertEqual(meal.aiDescription, "Pasta with tomato sauce")
        XCTAssertNil(meal.aiAnalysisErrorDetails)
        let callCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCoordinatorFailurePathSetsFailedAndKeepsDescriptionNil() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        let recognitionSpy = FoodRecognitionSpy(behavior: .failure(.networkError))
        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: recognitionSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )

        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.aiAnalysisStatus, .failed)
        XCTAssertNil(meal.aiDescription)
        XCTAssertNotNil(meal.aiAnalysisErrorDetails)
        XCTAssertTrue(meal.aiAnalysisErrorDetails?.contains("Network error") == true)
        let callCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCoordinatorSkipsWhenNoAPIKeyConfigured() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        let recognitionSpy = FoodRecognitionSpy(behavior: .success("Unused"))
        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: recognitionSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: nil)
        )

        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.aiAnalysisStatus, .pending)
        let callCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(callCount, 0)
    }

    func testCoordinatorIdempotentGuardSkipsAnalyzingMeals() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        meal.aiAnalysisStatus = .analyzing
        try harness.modelContext.save()

        let recognitionSpy = FoodRecognitionSpy(behavior: .success("Unused"))
        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: recognitionSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )

        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.aiAnalysisStatus, .analyzing)
        let callCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(callCount, 0)
    }
}

@MainActor
private final class AnalysisHarness {
    let modelContext: ModelContext
    let imageStore: ImageStore

    private let tempDirectory: URL

    static func make() throws -> AnalysisHarness {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Meal.self, MealEntry.self, EntryPhotoAsset.self, MealType.self])
        let container = try ModelContainer(for: schema, configurations: configuration)
        let modelContext = ModelContext(container)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodBuddy-AIAnalysisTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let imageStore = ImageStore(baseDirectory: tempDirectory)
        return AnalysisHarness(modelContext: modelContext, imageStore: imageStore, tempDirectory: tempDirectory)
    }

    init(modelContext: ModelContext, imageStore: ImageStore, tempDirectory: URL) {
        self.modelContext = modelContext
        self.imageStore = imageStore
        self.tempDirectory = tempDirectory
    }

    func makePendingMeal() throws -> Meal {
        let service = MealEntryService(modelContext: modelContext, imageStore: imageStore)
        try service.bootstrapMealTypesIfNeeded()
        let mealType = try XCTUnwrap(try service.listMealTypes().first)

        let entries = try service.ingest(
            images: [TestImageFactory.make(color: .systemRed)],
            mealTypeID: mealType.id,
            loggedAt: Date(timeIntervalSince1970: 100),
            userNotes: "Pending analysis",
            aiAnalysisStatus: .pending
        )
        let entry = try XCTUnwrap(entries.first)
        return try XCTUnwrap(entry.meal)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

private struct StaticCoordinatorAPIKeyStore: MistralAPIKeyStoring {
    let key: String?

    func apiKey() throws -> String? {
        key
    }

    func setAPIKey(_ key: String?) throws {}
}

private actor FoodRecognitionSpy: FoodRecognitionService {
    enum Behavior {
        case success(String)
        case failure(FoodRecognitionServiceError)
    }

    private(set) var callCount = 0
    private let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        callCount += 1
        switch behavior {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func recordedCallCount() -> Int {
        callCount
    }
}
