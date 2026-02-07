import Foundation

@MainActor
protocol MealEntryIngesting {
    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry
}

@MainActor
final class MealEntryService: MealEntryIngesting {
    private let repository: any MealEntryRepository
    private let imageStore: ImageStore
    private let nowProvider: () -> Date
    private let uuidProvider: () -> UUID

    init(
        repository: any MealEntryRepository,
        imageStore: ImageStore,
        nowProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.nowProvider = nowProvider
        self.uuidProvider = uuidProvider
    }

    func listEntriesNewestFirst() throws -> [MealEntry] {
        try repository.fetchAllNewestFirst()
    }

    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry {
        let imageFilename = try imageStore.saveJPEG(image)
        let entry = MealEntry(
            id: uuidProvider(),
            createdAt: nowProvider(),
            imageFilename: imageFilename
        )

        do {
            try repository.insert(entry)
            try repository.save()
            return entry
        } catch {
            try? imageStore.deleteImage(filename: imageFilename)
            throw error
        }
    }

    func delete(entry: MealEntry) throws {
        try imageStore.deleteImage(filename: entry.imageFilename)
        try repository.delete(entry)
        try repository.save()
    }

    func delete(entryID: UUID) throws {
        guard let entry = try repository.fetchByID(entryID) else {
            return
        }
        try delete(entry: entry)
    }
}
