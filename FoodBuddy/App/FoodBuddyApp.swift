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
            AdaptiveRootView(syncStatus: syncStatus)
        }
        .modelContainer(modelContainer)
    }
}

private struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let syncStatus: SyncStatus

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                HistoryView(syncStatus: syncStatus, layoutMode: .compact)
            }
        } else {
            HistoryView(syncStatus: syncStatus, layoutMode: .regular)
        }
    }
}
