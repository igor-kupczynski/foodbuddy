import SwiftData
import SwiftUI

@main
struct FoodBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HistoryView()
            }
        }
        .modelContainer(for: [MealEntry.self])
    }
}
