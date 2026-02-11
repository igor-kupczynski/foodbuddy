import Foundation
import SwiftData

enum PersistenceController {
    private static let cloudKitContainerID = "iCloud.info.kupczynski.foodbuddy"
    private static let localFallbackMessage = "iCloud is unavailable. FoodBuddy continues storing metadata locally on this device."

    static func makeContainerWithSyncStatus() -> (container: ModelContainer, syncStatus: SyncStatus) {
        let schema = Schema([
            Meal.self,
            MealEntry.self,
            EntryPhotoAsset.self,
            MealType.self
        ])

        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            return (container, .cloudEnabled)
        } catch {
            let localURL = URL.applicationSupportDirectory
                .appending(path: "FoodBuddy-local.store")
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                url: localURL,
                cloudKitDatabase: .none
            )

            do {
                let fallbackContainer = try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfiguration]
                )
                return (fallbackContainer, .localOnly(reason: localFallbackMessage))
            } catch {
                fatalError("Failed to create any SwiftData container: \(error)")
            }
        }
    }
}
