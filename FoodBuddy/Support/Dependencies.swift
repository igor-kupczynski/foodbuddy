import SwiftData

enum Dependencies {
    static func makeImageStore() -> ImageStore {
        ImageStore.live()
    }

    @MainActor
    static func makeMealEntryService(modelContext: ModelContext) -> MealEntryService {
        MealEntryService(
            repository: SwiftDataMealEntryRepository(modelContext: modelContext),
            imageStore: makeImageStore()
        )
    }
}
