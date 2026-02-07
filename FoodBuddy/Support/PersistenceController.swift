import SwiftData

enum PersistenceController {
    private static let cloudKitContainerID = "iCloud.com.igorkupczynski.foodbuddy"

    static func makeContainerWithSyncStatus() -> (container: ModelContainer, syncStatus: SyncStatus) {
        let schema = Schema([
            Meal.self,
            MealEntry.self,
            EntryPhotoAsset.self,
            MealType.self
        ])

        do {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            return (container, .cloudEnabled)
        } catch {
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )

            do {
                let fallbackContainer = try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfiguration]
                )
                let message = "iCloud is unavailable. FoodBuddy continues storing metadata locally on this device."
                return (fallbackContainer, .localOnly(reason: message))
            } catch {
                fatalError("Failed to create local SwiftData container: \(error)")
            }
        }
    }
}
