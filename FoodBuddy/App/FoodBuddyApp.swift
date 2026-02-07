import SwiftData
import SwiftUI

@main
struct FoodBuddyApp: App {
    private let modelContainer: ModelContainer
    private let syncStatus: SyncStatus

    init() {
        let setup = PersistenceController.makeContainerWithSyncStatus()
        modelContainer = setup.container
        syncStatus = setup.syncStatus
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HistoryView(syncStatus: syncStatus)
            }
        }
        .modelContainer(modelContainer)
    }
}
