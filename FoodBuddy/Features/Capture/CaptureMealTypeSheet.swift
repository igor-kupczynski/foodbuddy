import SwiftUI

struct CaptureMealTypeSheet: View {
    let image: PlatformImage
    let mealTypes: [MealType]
    let loggedAt: Date
    let onSave: () -> Void
    let onCancel: () -> Void

    @Binding var selectedMealTypeID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Section("Meal Details") {
                    Text(loggedAt.formatted(date: .abbreviated, time: .shortened))

                    if mealTypes.isEmpty {
                        Text("No meal types available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Meal Type", selection: selectedTypeBinding) {
                            ForEach(mealTypes) { type in
                                Text(type.displayName).tag(type.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .accessibilityIdentifier("capture-mealtype-cancel")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(selectedMealTypeID == nil || mealTypes.isEmpty)
                    .accessibilityIdentifier("capture-mealtype-save")
                }
            }
            .onAppear {
                if selectedMealTypeID == nil {
                    selectedMealTypeID = mealTypes.first?.id
                }
            }
        }
    }

    private var selectedTypeBinding: Binding<UUID> {
        Binding<UUID>(
            get: {
                if let selectedMealTypeID {
                    return selectedMealTypeID
                }
                return mealTypes.first?.id ?? UUID()
            },
            set: { newValue in
                selectedMealTypeID = newValue
            }
        )
    }
}
