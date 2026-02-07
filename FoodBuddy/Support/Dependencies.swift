import SwiftData

enum Dependencies {
    static func makeImageStore() -> ImageStore {
        ImageStore.live()
    }

    @MainActor
    static func makeMealEntryService(modelContext: ModelContext) -> MealEntryService {
        MealEntryService(
            modelContext: modelContext,
            imageStore: makeImageStore()
        )
    }
}
