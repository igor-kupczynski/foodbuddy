import SwiftUI
import UIKit

struct CaptureSessionPayload {
    let images: [PlatformImage]
    let mealTypeID: UUID
    let loggedAt: Date
    let notes: String?
}

struct CaptureSessionView: View {
    private struct SessionPhoto: Identifiable {
        let id = UUID()
        let image: PlatformImage
    }

    let initialImage: PlatformImage
    let mealTypes: [MealType]
    let loggedAt: Date
    let initialMealTypeID: UUID?
    let onSave: (CaptureSessionPayload) -> Void
    let onCancel: () -> Void

    @State private var photos: [SessionPhoto] = []
    @State private var selectedMealTypeID: UUID?
    @State private var notes = ""
    @State private var isShowingAddPhotoDialog = false
    @State private var activeCaptureSource: CaptureSource?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("capture-session-photo-count")

                    if photos.count < CaptureSessionLimits.maxPhotos {
                        Button {
                            isShowingAddPhotoDialog = true
                        } label: {
                            Label("Add another photo", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("capture-session-add-photo")
                    }

                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        VStack(alignment: .trailing, spacing: 8) {
                            Button {
                                removePhoto(id: photo.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("capture-session-remove-photo-\(index)")

                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("capture-session-photo-\(index)")
                        }
                    }
                }

                Section("Meal Details") {
                    TextField("Any details? (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("capture-session-notes")

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
            .navigationTitle("Save Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .accessibilityIdentifier("capture-session-cancel")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSession()
                    }
                    .disabled(photos.isEmpty || selectedMealTypeID == nil || mealTypes.isEmpty)
                    .accessibilityIdentifier("capture-session-save")
                }
            }
            .onAppear {
                if photos.isEmpty {
                    photos = [SessionPhoto(image: initialImage)]
                }
                if selectedMealTypeID == nil {
                    selectedMealTypeID = initialMealTypeID ?? mealTypes.first?.id
                }
            }
            .confirmationDialog("Add Photo", isPresented: $isShowingAddPhotoDialog, titleVisibility: .visible) {
                Button(CaptureSource.camera.title) {
                    activeCaptureSource = .camera
                }

                Button(CaptureSource.library.title) {
                    activeCaptureSource = .library
                }

                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(item: $activeCaptureSource) { source in
                switch source {
                case .camera:
                    if AppRuntimeFlags.useMockCameraCapture {
                        MockCameraCaptureView { image in
                            appendPhoto(image)
                        }
                    } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        CameraPicker { image in
                            appendPhoto(image)
                        }
                    } else {
                        ContentUnavailableView(
                            "Camera Unavailable",
                            systemImage: "camera",
                            description: Text("This device does not provide camera capture.")
                        )
                    }
                case .library:
                    LibraryPicker { image in
                        appendPhoto(image)
                    }
                }
            }
        }
        .accessibilityIdentifier("capture-session-root")
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

    private func appendPhoto(_ image: PlatformImage) {
        guard photos.count < CaptureSessionLimits.maxPhotos else {
            return
        }
        photos.append(SessionPhoto(image: image))
    }

    private func removePhoto(id: UUID) {
        photos.removeAll { $0.id == id }
    }

    private func saveSession() {
        guard let selectedMealTypeID else {
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = CaptureSessionPayload(
            images: photos.map(\.image),
            mealTypeID: selectedMealTypeID,
            loggedAt: loggedAt,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        onSave(payload)
    }
}
