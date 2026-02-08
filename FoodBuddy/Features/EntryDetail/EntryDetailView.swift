import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext

    let entry: MealEntry
    let syncStatus: SyncStatus
    let onDelete: (() -> Void)?

    @Query(sort: [SortDescriptor(\MealType.displayName)])
    private var mealTypes: [MealType]

    @State private var editedLoggedAt: Date
    @State private var editedMealTypeID: UUID?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingReassignmentConfirmation = false
    @State private var isShowingMealTypeReassignmentConfirmation = false
    @State private var actionErrorMessage: String?

    init(
        entry: MealEntry,
        syncStatus: SyncStatus = .cloudEnabled,
        onDelete: (() -> Void)? = nil
    ) {
        self.entry = entry
        self.syncStatus = syncStatus
        self.onDelete = onDelete
        _editedLoggedAt = State(initialValue: entry.loggedAt)
        _editedMealTypeID = State(initialValue: entry.meal?.typeId)
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
            get: { actionErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private var currentMealTypeID: UUID? {
        entry.meal?.typeId
    }

    private var hasMealTypeChanges: Bool {
        guard let currentMealTypeID, let editedMealTypeID else {
            return false
        }
        return currentMealTypeID != editedMealTypeID
    }

    private var shouldUseTwoColumnLayout: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            Group {
                if shouldUseTwoColumnLayout {
                    regularContent
                } else {
                    compactContent
                }
            }
            .padding()
            .frame(maxWidth: 1_100, alignment: .topLeading)
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !shouldUseTwoColumnLayout {
                ToolbarItem(placement: .topBarTrailing) {
                    deleteButton
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
        .alert("Move Entry to Another Meal Type?", isPresented: $isShowingMealTypeReassignmentConfirmation) {
            Button("Move", role: .destructive) {
                applyMealTypeUpdate()
            }
            Button("Cancel", role: .cancel) {
                editedMealTypeID = currentMealTypeID
            }
        } message: {
            Text("This keeps date/time unchanged and reassigns the entry to a different meal type.")
        }
        .alert("Could Not Save Changes", isPresented: isShowingDeleteError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(actionErrorMessage ?? "Unknown error")
        })
        .onAppear {
            if editedMealTypeID == nil {
                editedMealTypeID = currentMealTypeID ?? mealTypes.first?.id
            }
        }
        .onChange(of: currentMealTypeID) { _, newValue in
            if !hasMealTypeChanges {
                editedMealTypeID = newValue ?? mealTypes.first?.id
            }
        }
    }

    private var regularContent: some View {
        HStack(alignment: .top, spacing: 24) {
            imageSection
                .frame(maxWidth: .infinity, alignment: .topLeading)

            metadataSection
                .padding(16)
                .frame(width: 360, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.thinMaterial)
                }
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            imageSection
            metadataSection
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        if let image = fullImage ?? thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: shouldUseTwoColumnLayout ? 700 : nil)
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
                Text("Meal Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if mealTypes.isEmpty {
                    Text("No meal types available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Meal Type", selection: selectedMealTypeBinding) {
                        ForEach(mealTypes) { type in
                            Text(type.displayName).tag(type.id)
                        }
                    }
                    .labelsHidden()

                    Button("Save Meal Type") {
                        isShowingMealTypeReassignmentConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasMealTypeChanges)
                }

                Divider()

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

                if shouldUseTwoColumnLayout {
                    deleteButton
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete Entry", systemImage: "trash")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
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
            actionErrorMessage = error.localizedDescription
            editedLoggedAt = entry.loggedAt
        }
    }

    private func applyMealTypeUpdate() {
        guard let selectedMealTypeID = editedMealTypeID else {
            actionErrorMessage = "Select a meal type before saving."
            return
        }

        do {
            let result = try service.reassignMealType(entry: entry, to: selectedMealTypeID)
            if result == .noChange {
                self.editedMealTypeID = currentMealTypeID
            } else {
                self.editedMealTypeID = entry.meal?.typeId
            }
        } catch {
            actionErrorMessage = error.localizedDescription
            self.editedMealTypeID = currentMealTypeID
        }
    }

    private func deleteEntry() {
        do {
            try service.delete(entry: entry)

            if let onDelete {
                onDelete()
            } else {
                dismiss()
            }
        } catch {
            actionErrorMessage = error.localizedDescription
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

    private var selectedMealTypeBinding: Binding<UUID> {
        Binding(
            get: {
                if let editedMealTypeID {
                    return editedMealTypeID
                }

                if let currentMealTypeID {
                    return currentMealTypeID
                }

                return mealTypes.first?.id ?? UUID()
            },
            set: { newValue in
                editedMealTypeID = newValue
            }
        )
    }
}
