import Foundation
import SwiftData
import XCTest

@MainActor
final class MealEntryServiceTests: XCTestCase {
    func testIngestCreatesFileAndDatabaseRow() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [Date(timeIntervalSince1970: 100)])
        try service.bootstrapMealTypesIfNeeded()

        let breakfast = try XCTUnwrap(try mealType(named: "Breakfast", service: service))
        let entry = try service.ingest(
            image: TestImageFactory.make(color: .systemBlue),
            mealTypeID: breakfast.id,
            loggedAt: Date(timeIntervalSince1970: 100)
        )
        let rows = try service.listEntriesNewestFirst()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, entry.id)
        XCTAssertEqual(rows[0].mealId, entry.mealId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.imageStore.url(for: entry.imageFilename).path))
    }

    func testMealSuggestionBoundaries() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService()
        try service.bootstrapMealTypesIfNeeded()

        XCTAssertEqual(try service.suggestedMealType(for: makeDate(hour: 10, minute: 59))?.displayName, "Breakfast")
        XCTAssertEqual(try service.suggestedMealType(for: makeDate(hour: 11, minute: 0))?.displayName, "Lunch")
        XCTAssertEqual(try service.suggestedMealType(for: makeDate(hour: 14, minute: 59))?.displayName, "Lunch")
        XCTAssertEqual(try service.suggestedMealType(for: makeDate(hour: 15, minute: 0))?.displayName, "Afternoon Snack")
        XCTAssertEqual(try service.suggestedMealType(for: makeDate(hour: 17, minute: 59))?.displayName, "Afternoon Snack")
        XCTAssertEqual(try service.suggestedMealType(for: makeDate(hour: 18, minute: 0))?.displayName, "Dinner")
    }

    func testIngestAssociatesEntriesToExistingMealForSameDayAndType() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [makeDate(dayOffset: 0, hour: 8, minute: 0)])
        try service.bootstrapMealTypesIfNeeded()
        let breakfast = try XCTUnwrap(try mealType(named: "Breakfast", service: service))

        _ = try service.ingest(
            image: TestImageFactory.make(color: .systemRed),
            mealTypeID: breakfast.id,
            loggedAt: makeDate(dayOffset: 0, hour: 8, minute: 0)
        )
        _ = try service.ingest(
            image: TestImageFactory.make(color: .systemGreen),
            mealTypeID: breakfast.id,
            loggedAt: makeDate(dayOffset: 0, hour: 9, minute: 30)
        )

        let meals = try harness.fetchMeals()

        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].entries.count, 2)
    }

    func testIngestCreatesNewMealForDifferentDay() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService()
        try service.bootstrapMealTypesIfNeeded()
        let breakfast = try XCTUnwrap(try mealType(named: "Breakfast", service: service))

        _ = try service.ingest(
            image: TestImageFactory.make(color: .systemOrange),
            mealTypeID: breakfast.id,
            loggedAt: makeDate(dayOffset: 0, hour: 8, minute: 0)
        )
        _ = try service.ingest(
            image: TestImageFactory.make(color: .systemTeal),
            mealTypeID: breakfast.id,
            loggedAt: makeDate(dayOffset: 1, hour: 8, minute: 0)
        )

        let meals = try harness.fetchMeals()

        XCTAssertEqual(meals.count, 2)
    }

    func testLoggedAtEditRequiresConfirmationForMealReassignment() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)])
        try service.bootstrapMealTypesIfNeeded()
        let breakfast = try XCTUnwrap(try mealType(named: "Breakfast", service: service))

        let entry = try service.ingest(
            image: TestImageFactory.make(color: .systemPurple),
            mealTypeID: breakfast.id,
            loggedAt: makeDate(dayOffset: 0, hour: 8, minute: 0)
        )
        let originalMealID = entry.mealId

        let pending = try service.updateLoggedAt(
            entry: entry,
            newLoggedAt: makeDate(dayOffset: 1, hour: 8, minute: 0),
            allowMealReassignment: false
        )

        XCTAssertEqual(pending, .requiresMealReassignmentConfirmation)
        XCTAssertEqual(entry.mealId, originalMealID)

        let applied = try service.updateLoggedAt(
            entry: entry,
            newLoggedAt: makeDate(dayOffset: 1, hour: 8, minute: 0),
            allowMealReassignment: true
        )

        XCTAssertEqual(applied, .updatedWithReassignment)
        XCTAssertNotEqual(entry.mealId, originalMealID)
    }

    func testMealTypeRenameAndAdd() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)])
        try service.bootstrapMealTypesIfNeeded()

        _ = try service.createCustomMealType(named: "Brunch")

        let breakfast = try XCTUnwrap(try mealType(named: "Breakfast", service: service))
        try service.renameMealType(id: breakfast.id, to: "Early Breakfast")

        let names = try service.listMealTypes().map(\.displayName)

        XCTAssertTrue(names.contains("Brunch"))
        XCTAssertTrue(names.contains("Early Breakfast"))
        XCTAssertFalse(names.contains("Breakfast"))
    }

    func testCameraAndLibraryIngestUseSharedIngestMethod() throws {
        let spy = IngestSpy()
        let coordinator = CaptureIngestCoordinator(ingestService: spy)
        let image = TestImageFactory.make(color: .purple)

        _ = try coordinator.ingestFromCamera(image)
        _ = try coordinator.ingestFromLibrary(image)

        XCTAssertEqual(spy.callCount, 2)
    }

    private func mealType(named name: String, service: MealEntryService) throws -> MealType? {
        try service.listMealTypes().first(where: { $0.displayName == name })
    }

    private func makeDate(dayOffset: Int = 0, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay) ?? targetDay
    }
}

@MainActor
private final class TestHarness {
    let modelContext: ModelContext
    let imageStore: ImageStore

    private let tempDirectory: URL

    static func make() throws -> TestHarness {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Meal.self, MealEntry.self, MealType.self])
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodBuddy-ServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var filenameCounter = 0
        let imageStore = ImageStore(
            baseDirectory: directory,
            uuidProvider: {
                filenameCounter += 1
                return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", filenameCounter)) ?? UUID()
            }
        )

        return TestHarness(modelContext: context, imageStore: imageStore, tempDirectory: directory)
    }

    init(modelContext: ModelContext, imageStore: ImageStore, tempDirectory: URL) {
        self.modelContext = modelContext
        self.imageStore = imageStore
        self.tempDirectory = tempDirectory
    }

    func makeService(nowDates: [Date] = []) -> MealEntryService {
        var nowIndex = 0
        var entryCounter = 1000

        let nowProvider: () -> Date = {
            defer { nowIndex += 1 }
            if nowIndex < nowDates.count {
                return nowDates[nowIndex]
            }
            return Date(timeIntervalSince1970: 0)
        }

        let uuidProvider: () -> UUID = {
            entryCounter += 1
            return UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", entryCounter)) ?? UUID()
        }

        let mealService = MealService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
        let mealTypeService = MealTypeService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )

        return MealEntryService(
            modelContext: modelContext,
            imageStore: imageStore,
            mealService: mealService,
            mealTypeService: mealTypeService,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
    }

    func fetchMeals() throws -> [Meal] {
        try modelContext.fetch(FetchDescriptor<Meal>())
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

@MainActor
private final class IngestSpy: MealEntryIngesting {
    private(set) var callCount = 0

    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry {
        callCount += 1
        return MealEntry(mealId: UUID(), imageFilename: "spy-\(callCount).jpg")
    }
}
