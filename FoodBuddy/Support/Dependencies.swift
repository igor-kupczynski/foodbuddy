import SwiftData

enum Dependencies {
    private static let cloudKitContainerID = "iCloud.com.igorkupczynski.foodbuddy"

    static func makeImageStore() -> ImageStore {
        ImageStore.live()
    }

    static func makeCloudPhotoStore(syncStatus: SyncStatus) -> (any CloudPhotoStoring)? {
        guard syncStatus.isCloudEnabled else {
            return nil
        }
        return CloudKitPhotoStore.live(containerIdentifier: cloudKitContainerID)
    }

    @MainActor
    static func makePhotoSyncService(modelContext: ModelContext, syncStatus: SyncStatus) -> PhotoSyncService {
        PhotoSyncService(
            modelContext: modelContext,
            imageStore: makeImageStore(),
            cloudStore: makeCloudPhotoStore(syncStatus: syncStatus)
        )
    }

    @MainActor
    static func makeMealEntryService(modelContext: ModelContext) -> MealEntryService {
        MealEntryService(
            modelContext: modelContext,
            imageStore: makeImageStore()
        )
    }
}
