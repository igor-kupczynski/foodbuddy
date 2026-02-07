import SwiftData
import XCTest

@MainActor
final class MealEntryServiceTests: XCTestCase {
    func testIngestCreatesFileAndDatabaseRow() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [Date(timeIntervalSince1970: 100)])

        let entry = try service.ingest(image: TestImageFactory.make(color: .systemBlue))
        let rows = try harness.repository.fetchAllNewestFirst()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.imageStore.url(for: entry.imageFilename).path))
    }

    func testHistoryReturnsNewestFirst() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let now = Date(timeIntervalSince1970: 200)
        let later = Date(timeIntervalSince1970: 300)
        let service = harness.makeService(nowDates: [now, later])

        _ = try service.ingest(image: TestImageFactory.make(color: .systemRed))
        _ = try service.ingest(image: TestImageFactory.make(color: .systemGreen))

        let entries = try service.listEntriesNewestFirst()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].createdAt, later)
        XCTAssertEqual(entries[1].createdAt, now)
    }

    func testDeleteRemovesDatabaseRowAndImageFile() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [Date(timeIntervalSince1970: 100)])

        let entry = try service.ingest(image: TestImageFactory.make(color: .systemTeal))
        try service.delete(entry: entry)

        let rows = try service.listEntriesNewestFirst()

        XCTAssertTrue(rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.imageStore.url(for: entry.imageFilename).path))
    }

    func testDeleteSucceedsWhenImageFileAlreadyMissing() throws {
        let harness = try TestHarness.make()
        defer { harness.cleanup() }

        let service = harness.makeService(nowDates: [Date(timeIntervalSince1970: 100)])

        let entry = try service.ingest(image: TestImageFactory.make(color: .systemYellow))
        try FileManager.default.removeItem(at: harness.imageStore.url(for: entry.imageFilename))

        XCTAssertNoThrow(try service.delete(entry: entry))
        XCTAssertTrue(try service.listEntriesNewestFirst().isEmpty)
    }

    func testCameraAndLibraryIngestUseSharedIngestMethod() throws {
        let spy = IngestSpy()
        let coordinator = CaptureIngestCoordinator(ingestService: spy)
        let image = TestImageFactory.make(color: .purple)

        _ = try coordinator.ingestFromCamera(image)
        _ = try coordinator.ingestFromLibrary(image)

        XCTAssertEqual(spy.callCount, 2)
    }
}

@MainActor
private final class TestHarness {
    let repository: SwiftDataMealEntryRepository
    let imageStore: ImageStore

    private let tempDirectory: URL

    static func make() throws -> TestHarness {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MealEntry.self, configurations: config)
        let context = ModelContext(container)
        let repository = SwiftDataMealEntryRepository(modelContext: context)

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

        return TestHarness(repository: repository, imageStore: imageStore, tempDirectory: directory)
    }

    init(repository: SwiftDataMealEntryRepository, imageStore: ImageStore, tempDirectory: URL) {
        self.repository = repository
        self.imageStore = imageStore
        self.tempDirectory = tempDirectory
    }

    func makeService(nowDates: [Date]) -> MealEntryService {
        var nowIndex = 0
        var entryCounter = 1000

        return MealEntryService(
            repository: repository,
            imageStore: imageStore,
            nowProvider: {
                defer { nowIndex += 1 }
                if nowIndex < nowDates.count {
                    return nowDates[nowIndex]
                }
                return nowDates.last ?? Date(timeIntervalSince1970: 0)
            },
            uuidProvider: {
                entryCounter += 1
                return UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", entryCounter)) ?? UUID()
            }
        )
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
        return MealEntry(imageFilename: "spy-\(callCount).jpg")
    }
}
