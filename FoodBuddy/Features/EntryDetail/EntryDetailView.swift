import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: MealEntry
    let syncStatus: SyncStatus

    @State private var editedLoggedAt: Date
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingReassignmentConfirmation = false
    @State private var deleteErrorMessage: String?

    init(entry: MealEntry, syncStatus: SyncStatus = .cloudEnabled) {
        self.entry = entry
        self.syncStatus = syncStatus
        _editedLoggedAt = State(initialValue: entry.loggedAt)
    }

    private var imageStore: ImageStore {
        Dependencies.makeImageStore()
    }

    private var service: MealEntryService {
        Dependencies.makeMealEntryService(modelContext: modelContext)
    }

    private var photoSyncService: PhotoSyncService {
        Dependencies.makePhotoSyncService(modelContext: modelContext, syncStatus: syncStatus)
    }

    private var isShowingDeleteError: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageSection
                metadataSection
            }
            .padding()
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete Entry", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the meal entry and its image.")
        }
        .alert("Move Entry to Another Meal?", isPresented: $isShowingReassignmentConfirmation) {
            Button("Move", role: .destructive) {
                applyLoggedAtUpdate(allowReassignment: true)
            }
            Button("Cancel", role: .cancel) {
                editedLoggedAt = entry.loggedAt
            }
        } message: {
            Text("This date/time change moves the entry into a different meal grouping.")
        }
        .alert("Could Not Save Changes", isPresented: isShowingDeleteError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(deleteErrorMessage ?? "Unknown error")
        })
    }

    @ViewBuilder
    private var imageSection: some View {
        if let image = fullImage ?? thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if fullImage == nil {
                Text("Showing thumbnail while full image syncs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView(
                "Image Not Found",
                systemImage: "photo.badge.exclamationmark",
                description: Text("The image file is missing from local storage.")
            )
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Captured")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Logged At")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "Date & Time",
                    selection: $editedLoggedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()

                Button("Save Date & Time") {
                    applyLoggedAtUpdate(allowReassignment: false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasLoggedAtChanges)

                if entry.photoAsset?.state == .failed {
                    Button("Retry Photo Sync") {
                        Task {
                            await photoSyncService.retryAsset(entryID: entry.id)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var hasLoggedAtChanges: Bool {
        abs(editedLoggedAt.timeIntervalSince(entry.loggedAt)) > 0.5
    }

    private func applyLoggedAtUpdate(allowReassignment: Bool) {
        do {
            let result = try service.updateLoggedAt(
                entry: entry,
                newLoggedAt: editedLoggedAt,
                allowMealReassignment: allowReassignment
            )

            switch result {
            case .updatedWithoutReassignment, .updatedWithReassignment:
                editedLoggedAt = entry.loggedAt
            case .requiresMealReassignmentConfirmation:
                isShowingReassignmentConfirmation = true
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
            editedLoggedAt = entry.loggedAt
        }
    }

    private func deleteEntry() {
        do {
            try service.delete(entry: entry)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private var fullImage: PlatformImage? {
        if let filename = entry.photoAsset?.fullImageFilename,
           let image = imageStore.loadImage(filename: filename) {
            return image
        }

        return imageStore.loadImage(filename: entry.imageFilename)
    }

    private var thumbnailImage: PlatformImage? {
        guard let filename = entry.photoAsset?.thumbnailFilename else {
            return nil
        }

        return imageStore.loadImage(filename: filename)
    }
}
