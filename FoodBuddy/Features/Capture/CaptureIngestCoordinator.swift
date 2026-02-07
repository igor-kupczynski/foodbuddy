@MainActor
final class CaptureIngestCoordinator {
    private let ingestService: any MealEntryIngesting

    init(ingestService: any MealEntryIngesting) {
        self.ingestService = ingestService
    }

    @discardableResult
    func ingestFromCamera(_ image: PlatformImage) throws -> MealEntry {
        try ingest(image)
    }

    @discardableResult
    func ingestFromLibrary(_ image: PlatformImage) throws -> MealEntry {
        try ingest(image)
    }

    @discardableResult
    private func ingest(_ image: PlatformImage) throws -> MealEntry {
        try ingestService.ingest(image: image)
    }
}
