import SwiftData
import SwiftUI

struct MealTypeManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\MealType.displayName)])
    private var mealTypes: [MealType]

    @State private var renameDrafts: [UUID: String] = [:]
    @State private var newMealTypeName = ""
    @State private var errorMessage: String?

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
            Section("Existing Types") {
                ForEach(mealTypes) { type in
                    HStack(spacing: 12) {
                        TextField(
                            "Meal Type",
                            text: Binding(
                                get: { renameDrafts[type.id] ?? type.displayName },
                                set: { renameDrafts[type.id] = $0 }
                            )
                        )
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                        Button("Save") {
                            rename(typeID: type.id)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("Add Custom Type") {
                TextField("Name", text: $newMealTypeName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)

                Button("Add") {
                    addMealType()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newMealTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Meal Types")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Could Not Save Meal Type", isPresented: isShowingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
        .task {
            do {
                try service.bootstrapMealTypesIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rename(typeID: UUID) {
        guard let draft = renameDrafts[typeID] else {
            return
        }

        do {
            try service.renameMealType(id: typeID, to: draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addMealType() {
        do {
            _ = try service.createCustomMealType(named: newMealTypeName)
            newMealTypeName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        MealTypeManagementView()
            .modelContainer(for: [Meal.self, MealEntry.self, MealType.self, EntryPhotoAsset.self], inMemory: true)
    }
}
