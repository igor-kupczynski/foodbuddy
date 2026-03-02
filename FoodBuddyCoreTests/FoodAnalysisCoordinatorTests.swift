import SwiftData
import XCTest

@MainActor
final class FoodAnalysisCoordinatorTests: XCTestCase {
    func testCoordinatorHappyPathSetsCompletedDescriptionAndFoodItems() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        let recognitionSpy = FoodRecognitionSpy(
            behavior: .success(
                FoodAnalysisResult(
                    description: "Pasta with tomato sauce",
                    foodItems: [
                        AIFoodItem(name: "Pasta", category: "whole_grains", servings: 1),
                        AIFoodItem(name: "Sauce", category: "vegetables", servings: 1)
                    ]
                )
            )
        )

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
        XCTAssertNil(meal.aiAnalysisNextRetryAt)
        XCTAssertEqual(meal.foodItems.count, 2)
        XCTAssertEqual(Set(meal.foodItems.map(\.category)), [.wholeGrains, .vegetables])

        let callCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCoordinatorProcessesNoteOnlyPendingMeal() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingNoteOnlyMeal()
        let recognitionSpy = FoodRecognitionSpy(
            behavior: .success(
                FoodAnalysisResult(
                    description: "Oatmeal with berries",
                    foodItems: [AIFoodItem(name: "Oatmeal", category: "whole_grains", servings: 1)]
                )
            )
        )

        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: recognitionSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )

        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.aiAnalysisStatus, .completed)
        XCTAssertEqual(meal.aiDescription, "Oatmeal with berries")

        let calls = await recognitionSpy.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.imageCount, 0)
        XCTAssertEqual(calls.first?.notes, "Pending analysis")
    }

    func testCoordinatorReanalysisReplacesAIItemsAndPreservesManualItems() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        harness.modelContext.insert(
            FoodItem(
                mealId: meal.id,
                name: "Manual almonds",
                categoryRawValue: DQSCategory.nutsAndSeeds.rawValue,
                servings: 1,
                isManual: true,
                meal: meal
            )
        )
        try harness.modelContext.save()

        let firstRunSpy = FoodRecognitionSpy(
            behavior: .success(
                FoodAnalysisResult(
                    description: "Meal 1",
                    foodItems: [AIFoodItem(name: "Yogurt", category: "dairy", servings: 1)]
                )
            )
        )

        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: firstRunSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )
        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.foodItems.filter { !$0.isManual }.count, 1)
        XCTAssertEqual(meal.foodItems.filter { $0.isManual }.count, 1)

        meal.aiAnalysisStatus = .pending
        try harness.modelContext.save()

        let secondRunSpy = FoodRecognitionSpy(
            behavior: .success(
                FoodAnalysisResult(
                    description: "Meal 2",
                    foodItems: [AIFoodItem(name: "Donut", category: "fried_foods", servings: 1)]
                )
            )
        )

        let secondCoordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: secondRunSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )
        await secondCoordinator.processPendingMeals()

        XCTAssertEqual(meal.foodItems.filter { $0.isManual }.count, 1)
        let aiItems = meal.foodItems.filter { !$0.isManual }
        XCTAssertEqual(aiItems.count, 1)
        XCTAssertEqual(aiItems.first?.category, .friedFoods)
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
        XCTAssertNil(meal.aiAnalysisNextRetryAt)
        XCTAssertTrue(meal.aiAnalysisErrorDetails?.contains("Network error") == true)
        let callCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testCoordinatorRateLimitRequeuesMealAndPersistsTelemetry() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        let retryAt = Date().addingTimeInterval(600)
        let recognitionSpy = FoodRecognitionSpy(
            behavior: .failure(
                .rateLimited(
                    FoodRecognitionRateLimitTelemetry(
                        statusCode: 429,
                        responseBody: #"{"error":"rate limited"}"#,
                        responseTelemetry: HTTPResponseTelemetry(
                            headers: [
                                "retry-after": "120",
                                "x-ratelimit-remaining": "0",
                                "cf-ray": "abc123",
                            ]
                        ),
                        requestImageCount: 2,
                        requestImageBytes: [2_048, 2_048],
                        requestBodyBytes: 4_096,
                        model: "mistral-large-latest",
                        imageLongEdge: 1024,
                        imageQuality: 75,
                        attemptCount: 4,
                        maxAttempts: 4,
                        appliedRetryDelayMs: [2_000, 4_000, 8_000],
                        retryAfterRawValue: "120",
                        nextEligibleRetryAt: retryAt
                    )
                )
            )
        )
        let coordinator = FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: harness.modelContext),
            imageStore: harness.imageStore,
            foodRecognitionService: recognitionSpy,
            apiKeyStore: StaticCoordinatorAPIKeyStore(key: "configured")
        )

        await coordinator.processPendingMeals()

        XCTAssertEqual(meal.aiAnalysisStatus, .pending)
        XCTAssertEqual(meal.aiAnalysisNextRetryAt, retryAt)
        XCTAssertNotNil(meal.aiAnalysisErrorDetails)
        XCTAssertTrue(meal.aiAnalysisErrorDetails?.contains("HTTP Status: 429") == true)
        XCTAssertTrue(meal.aiAnalysisErrorDetails?.contains("Retry-After: 120") == true)
        XCTAssertTrue(meal.aiAnalysisErrorDetails?.contains("Request Body Bytes: 4096") == true)

        let firstCallCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(firstCallCount, 1)

        await coordinator.processPendingMeals()

        let secondCallCount = await recognitionSpy.recordedCallCount()
        XCTAssertEqual(secondCallCount, 1)
    }

    func testCoordinatorSkipsWhenNoAPIKeyConfigured() async throws {
        let harness = try AnalysisHarness.make()
        defer { harness.cleanup() }

        let meal = try harness.makePendingMeal()
        let recognitionSpy = FoodRecognitionSpy(
            behavior: .success(
                FoodAnalysisResult(description: "Unused", foodItems: [])
            )
        )
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

        let recognitionSpy = FoodRecognitionSpy(
            behavior: .success(FoodAnalysisResult(description: "Unused", foodItems: []))
        )
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
        let schema = Schema([Meal.self, MealEntry.self, EntryPhotoAsset.self, MealType.self, FoodItem.self])
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

    func makePendingNoteOnlyMeal() throws -> Meal {
        let service = MealEntryService(modelContext: modelContext, imageStore: imageStore)
        try service.bootstrapMealTypesIfNeeded()
        let mealType = try XCTUnwrap(try service.listMealTypes().first)

        return try service.ingestNoteOnlyMeal(
            mealTypeID: mealType.id,
            loggedAt: Date(timeIntervalSince1970: 100),
            userNotes: "Pending analysis",
            aiAnalysisStatus: .pending
        )
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
    struct RecordedCall: Equatable {
        let imageCount: Int
        let notes: String?
    }

    enum Behavior {
        case success(FoodAnalysisResult)
        case failure(FoodRecognitionServiceError)
    }

    private(set) var callCount = 0
    private(set) var calls: [RecordedCall] = []
    private let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult {
        callCount += 1
        calls.append(RecordedCall(imageCount: images.count, notes: notes))
        switch behavior {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }

    func recordedCallCount() -> Int {
        callCount
    }

    func recordedCalls() -> [RecordedCall] {
        calls
    }
}
