import Foundation
import SwiftData
import XCTest

@MainActor
final class PhotoSyncServiceTests: XCTestCase {
    func testIngestCreatesPendingPhotoAssetQueueItem() throws {
        let harness = try SyncTestHarness.make()
        defer { harness.cleanup() }

        let mealService = harness.makeMealEntryService(now: Date(timeIntervalSince1970: 100))
        try mealService.bootstrapMealTypesIfNeeded()
        let breakfast = try XCTUnwrap(try mealService.listMealTypes().first(where: { $0.displayName == "Breakfast" }))

        _ = try mealService.ingest(
            image: TestImageFactory.make(color: .systemOrange, width: 2000, height: 1500),
            mealTypeID: breakfast.id,
            loggedAt: Date(timeIntervalSince1970: 100)
        )

        let assets = try harness.fetchPhotoAssets()
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].state, .pending)
        XCTAssertNotNil(assets[0].thumbnailFilename)
    }

    func testUploadSuccessTransitionsAssetToUploaded() async throws {
        let harness = try SyncTestHarness.make()
        defer { harness.cleanup() }

        let mealService = harness.makeMealEntryService(now: Date(timeIntervalSince1970: 100))
        try mealService.bootstrapMealTypesIfNeeded()
        let breakfast = try XCTUnwrap(try mealService.listMealTypes().first(where: { $0.displayName == "Breakfast" }))

        let entry = try mealService.ingest(
            image: TestImageFactory.make(color: .systemBlue, width: 1800, height: 1200),
            mealTypeID: breakfast.id,
            loggedAt: Date(timeIntervalSince1970: 100)
        )

        let cloudStore = MockCloudPhotoStore()
        let syncService = harness.makePhotoSyncService(cloudStore: cloudStore)

        await syncService.runSyncCycle()

        let asset = try XCTUnwrap(try harness.fetchPhotoAsset(entryID: entry.id))
        XCTAssertEqual(asset.state, .uploaded)
        XCTAssertNotNil(asset.fullAssetRef)
        XCTAssertNotNil(asset.thumbAssetRef)
        XCTAssertNil(asset.lastError)
    }

    func testTransientFailureRetriesAfterBackoff() async throws {
        let harness = try SyncTestHarness.make()
        defer { harness.cleanup() }

        var now = Date(timeIntervalSince1970: 100)
        let mealService = harness.makeMealEntryService(now: now)
        try mealService.bootstrapMealTypesIfNeeded()
        let breakfast = try XCTUnwrap(try mealService.listMealTypes().first(where: { $0.displayName == "Breakfast" }))

        let entry = try mealService.ingest(
            image: TestImageFactory.make(color: .systemPurple, width: 2000, height: 1400),
            mealTypeID: breakfast.id,
            loggedAt: now
        )

        let cloudStore = MockCloudPhotoStore(remainingUploadFailures: 1)
        let syncService = harness.makePhotoSyncService(cloudStore: cloudStore, nowProvider: { now })

        await syncService.runSyncCycle()

        let failed = try XCTUnwrap(try harness.fetchPhotoAsset(entryID: entry.id))
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.retryCount, 1)
        XCTAssertNotNil(failed.nextRetryAt)

        now = now.addingTimeInterval(10)
        await syncService.runSyncCycle()

        let uploaded = try XCTUnwrap(try harness.fetchPhotoAsset(entryID: entry.id))
        XCTAssertEqual(uploaded.state, .uploaded)
        XCTAssertEqual(uploaded.retryCount, 0)
        XCTAssertNil(uploaded.nextRetryAt)
    }

    func testMetadataOnlyEntryHydratesMissingLocalFiles() async throws {
        let harness = try SyncTestHarness.make()
        defer { harness.cleanup() }

        let mealType = MealType(
            id: UUID(),
            displayName: "Dinner",
            isSystem: true,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        harness.modelContext.insert(mealType)

        let meal = Meal(
            id: UUID(),
            typeId: mealType.id,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        harness.modelContext.insert(meal)

        let entry = MealEntry(
            id: UUID(),
            mealId: meal.id,
            imageFilename: "missing-full.jpg",
            capturedAt: Date(timeIntervalSince1970: 10),
            loggedAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            meal: meal
        )
        harness.modelContext.insert(entry)

        let sourceImage = TestImageFactory.make(color: .systemTeal, width: 1200, height: 800)
        let preprocessor = ImagePreprocessor()
        let processed = try preprocessor.preprocess(sourceImage)

        let fullRef = "\(entry.id.uuidString)|full"
        let thumbRef = "\(entry.id.uuidString)|thumb"

        let asset = EntryPhotoAsset(
            id: entry.id,
            entryId: entry.id,
            fullAssetRef: fullRef,
            thumbAssetRef: thumbRef,
            state: .uploaded,
            updatedAt: Date(timeIntervalSince1970: 10),
            entry: entry
        )
        entry.photoAsset = asset
        entry.photoAssetId = asset.id
        harness.modelContext.insert(asset)
        try harness.modelContext.save()

        let cloudStore = MockCloudPhotoStore()
        await cloudStore.seed(assetRef: fullRef, data: processed.fullJPEGData)
        await cloudStore.seed(assetRef: thumbRef, data: processed.thumbnailJPEGData)

        let syncService = harness.makePhotoSyncService(cloudStore: cloudStore)
        await syncService.runSyncCycle()

        let hydrated = try XCTUnwrap(try harness.fetchPhotoAsset(entryID: entry.id))
        XCTAssertNotNil(hydrated.fullImageFilename)
        XCTAssertNotNil(hydrated.thumbnailFilename)

        if let full = hydrated.fullImageFilename {
            XCTAssertTrue(harness.imageStore.fileExists(filename: full))
        }
        if let thumb = hydrated.thumbnailFilename {
            XCTAssertTrue(harness.imageStore.fileExists(filename: thumb))
        }
    }
}

@MainActor
private final class SyncTestHarness {
    let modelContext: ModelContext
    let imageStore: ImageStore

    private let tempDirectory: URL

    static func make() throws -> SyncTestHarness {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Meal.self, MealEntry.self, EntryPhotoAsset.self, MealType.self])
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodBuddy-PhotoSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let imageStore = ImageStore(baseDirectory: directory)
        return SyncTestHarness(modelContext: context, imageStore: imageStore, tempDirectory: directory)
    }

    init(modelContext: ModelContext, imageStore: ImageStore, tempDirectory: URL) {
        self.modelContext = modelContext
        self.imageStore = imageStore
        self.tempDirectory = tempDirectory
    }

    func makeMealEntryService(now: Date) -> MealEntryService {
        MealEntryService(
            modelContext: modelContext,
            imageStore: imageStore,
            nowProvider: { now }
        )
    }

    func makePhotoSyncService(
        cloudStore: any CloudPhotoStoring,
        nowProvider: @escaping () -> Date = Date.init
    ) -> PhotoSyncService {
        PhotoSyncService(
            modelContext: modelContext,
            imageStore: imageStore,
            cloudStore: cloudStore,
            nowProvider: nowProvider
        )
    }

    func fetchPhotoAssets() throws -> [EntryPhotoAsset] {
        try modelContext.fetch(FetchDescriptor<EntryPhotoAsset>())
    }

    func fetchPhotoAsset(entryID: UUID) throws -> EntryPhotoAsset? {
        try fetchPhotoAssets().first(where: { $0.entryId == entryID })
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

private actor MockCloudPhotoStore: CloudPhotoStoring {
    enum Error: Swift.Error {
        case transient
    }

    private var downloadData: [String: Data] = [:]
    private var remainingUploadFailures: Int

    init(remainingUploadFailures: Int = 0) {
        self.remainingUploadFailures = remainingUploadFailures
    }

    func upload(
        entryID: UUID,
        fullJPEGData: Data,
        thumbnailJPEGData: Data
    ) async throws -> UploadedPhotoAssetRefs {
        if remainingUploadFailures > 0 {
            remainingUploadFailures -= 1
            throw Error.transient
        }

        let fullRef = "\(entryID.uuidString)|full"
        let thumbRef = "\(entryID.uuidString)|thumb"

        downloadData[fullRef] = fullJPEGData
        downloadData[thumbRef] = thumbnailJPEGData

        return UploadedPhotoAssetRefs(fullAssetRef: fullRef, thumbnailAssetRef: thumbRef)
    }

    func download(assetRef: String) async throws -> Data {
        guard let data = downloadData[assetRef] else {
            throw CloudPhotoStoreError.assetNotFound
        }

        return data
    }

    func seed(assetRef: String, data: Data) {
        downloadData[assetRef] = data
    }
}
