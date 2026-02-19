import SwiftUI

struct NoteOnlyMealPayload {
    let mealTypeID: UUID
    let loggedAt: Date
    let notes: String
}

struct NoteOnlyMealSheet: View {
    let mealTypes: [MealType]
    let loggedAt: Date
    let initialMealTypeID: UUID?
    let onSave: (NoteOnlyMealPayload) -> Void
    let onCancel: () -> Void

    @State private var selectedMealTypeID: UUID?
    @State private var notes = ""

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Details") {
                    TextField("What did you eat?", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("note-only-meal-notes")

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

                    Text(loggedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Note-Only Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .accessibilityIdentifier("note-only-meal-cancel")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveMeal()
                    }
                    .disabled(trimmedNotes.isEmpty || selectedMealTypeID == nil || mealTypes.isEmpty)
                    .accessibilityIdentifier("note-only-meal-save")
                }
            }
            .onAppear {
                if selectedMealTypeID == nil {
                    selectedMealTypeID = initialMealTypeID ?? mealTypes.first?.id
                }
            }
        }
    }

    private var selectedTypeBinding: Binding<UUID> {
        Binding(
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

    private func saveMeal() {
        guard let selectedMealTypeID else {
            return
        }

        onSave(
            NoteOnlyMealPayload(
                mealTypeID: selectedMealTypeID,
                loggedAt: loggedAt,
                notes: trimmedNotes
            )
        )
    }
}
