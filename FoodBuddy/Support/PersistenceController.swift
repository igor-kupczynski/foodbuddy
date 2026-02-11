import SwiftData

enum PersistenceController {
    private static let cloudKitContainerID = "iCloud.info.kupczynski.foodbuddy"
    private static let localFallbackMessage = "iCloud is unavailable. FoodBuddy continues storing metadata locally on this device."
    private static let inMemoryFallbackMessage = "SwiftData store could not be opened. FoodBuddy is running with temporary in-memory metadata storage for this launch."

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
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )

            do {
                let fallbackContainer = try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfiguration]
                )
                return (fallbackContainer, .localOnly(reason: localFallbackMessage))
            } catch {
                let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    let inMemoryContainer = try ModelContainer(
                        for: schema,
                        configurations: [inMemoryConfiguration]
                    )
                    return (inMemoryContainer, .localOnly(reason: inMemoryFallbackMessage))
                } catch {
                    fatalError("Failed to create any SwiftData container: \(error)")
                }
            }
        }
    }
}
