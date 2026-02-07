import SwiftData
import SwiftUI

struct MealDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    let meal: Meal
    let mealTypeName: String
    let syncStatus: SyncStatus

    @State private var errorMessage: String?

    private var imageStore: ImageStore {
        Dependencies.makeImageStore()
    }

    private var service: MealEntryService {
        Dependencies.makeMealEntryService(modelContext: modelContext)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    var body: some View {
        List {
            if sortedEntries.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "tray",
                    description: Text("This meal currently has no saved entries.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(sortedEntries) { entry in
                    NavigationLink {
                        EntryDetailView(entry: entry, syncStatus: syncStatus)
                    } label: {
                        EntryRowView(entry: entry, imageStore: imageStore)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
        }
        .contentMargins(horizontalSizeClass == .regular ? 24 : 0, for: .scrollContent)
        .navigationTitle(mealTypeName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could Not Delete Entry", isPresented: isShowingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }

    private var sortedEntries: [MealEntry] {
        meal.entries.sorted(by: { $0.loggedAt > $1.loggedAt })
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            let entry = sortedEntries[index]
            do {
                try service.delete(entry: entry)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
