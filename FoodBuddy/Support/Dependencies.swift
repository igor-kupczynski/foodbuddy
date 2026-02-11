import Foundation
import SwiftData

enum Dependencies {
    private static let cloudKitContainerID = "iCloud.info.kupczynski.foodbuddy"

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

    static func makeMistralAPIKeyStore() -> any MistralAPIKeyStoring {
        KeychainMistralAPIKeyStore(service: mistralKeychainServiceName)
    }

    static func makeFoodRecognitionService(
        apiKeyStore: (any MistralAPIKeyStoring)? = nil
    ) -> any FoodRecognitionService {
        if AppRuntimeFlags.useMockFoodRecognition {
            return MockFoodRecognitionService(behavior: .success("Mock AI description"))
        }

        let resolvedAPIKeyStore = apiKeyStore ?? makeMistralAPIKeyStore()
        return MistralFoodRecognitionService(apiKeyStore: resolvedAPIKeyStore)
    }

    @MainActor
    static func makeFoodAnalysisCoordinator(modelContext: ModelContext) -> FoodAnalysisCoordinator {
        let keyStore = makeMistralAPIKeyStore()
        return FoodAnalysisCoordinator(
            modelStore: FoodAnalysisModelStore(modelContext: modelContext),
            imageStore: makeImageStore(),
            foodRecognitionService: makeFoodRecognitionService(apiKeyStore: keyStore),
            apiKeyStore: keyStore
        )
    }

    private static var mistralKeychainServiceName: String {
        let env = ProcessInfo.processInfo.environment["FOODBUDDY_MISTRAL_KEYCHAIN_SERVICE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return env
        }
        return "info.kupczynski.foodbuddy"
    }
}
