import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    let syncStatus: SyncStatus

    @Query(sort: [SortDescriptor(\Meal.updatedAt, order: .reverse)])
    private var meals: [Meal]

    @Query(sort: [SortDescriptor(\MealType.displayName)])
    private var mealTypes: [MealType]

    @State private var isShowingCaptureSource = false
    @State private var isShowingCamera = false
    @State private var isShowingLibraryPicker = false
    @State private var isShowingMealTypeChooser = false
    @State private var isShowingMealTypeManagement = false

    @State private var pendingImage: PlatformImage?
    @State private var pendingLoggedAt = Date.now
    @State private var selectedMealTypeID: UUID?

    @State private var hasBootstrappedMealTypes = false
    @State private var ingestErrorMessage: String?

    private var imageStore: ImageStore {
        Dependencies.makeImageStore()
    }

    private var service: MealEntryService {
        Dependencies.makeMealEntryService(modelContext: modelContext)
    }

    private var isShowingIngestError: Binding<Bool> {
        Binding(
            get: { ingestErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    ingestErrorMessage = nil
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                syncStatusRow
            }
            .listRowSeparator(.hidden)

            if meals.isEmpty {
                ContentUnavailableView(
                    "No Meals Yet",
                    systemImage: "fork.knife.circle",
                    description: Text("Tap Add to capture or choose a meal photo.")
                )
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(meals) { meal in
                    NavigationLink {
                        MealDetailView(
                            meal: meal,
                            mealTypeName: mealTypeName(for: meal)
                        )
                    } label: {
                        MealRowView(
                            meal: meal,
                            mealTypeName: mealTypeName(for: meal),
                            imageStore: imageStore
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Meal Types") {
                    isShowingMealTypeManagement = true
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") {
                    isShowingCaptureSource = true
                }
            }
        }
        .task {
            if !hasBootstrappedMealTypes {
                do {
                    try service.bootstrapMealTypesIfNeeded()
                    hasBootstrappedMealTypes = true
                } catch {
                    ingestErrorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Add Meal", isPresented: $isShowingCaptureSource, titleVisibility: .visible) {
            Button(CaptureSource.camera.title) {
                isShowingCamera = true
            }

            Button(CaptureSource.library.title) {
                isShowingLibraryPicker = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isShowingCamera) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                CameraPicker { image in
                    beginIngest(with: image)
                }
            } else {
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera",
                    description: Text("This device does not provide camera capture.")
                )
            }
        }
        .sheet(isPresented: $isShowingLibraryPicker) {
            LibraryPicker { image in
                beginIngest(with: image)
            }
        }
        .sheet(isPresented: $isShowingMealTypeChooser, onDismiss: clearPendingCapture) {
            if let pendingImage {
                CaptureMealTypeSheet(
                    image: pendingImage,
                    mealTypes: mealTypes,
                    loggedAt: pendingLoggedAt,
                    onSave: savePendingCapture,
                    onCancel: clearPendingCapture,
                    selectedMealTypeID: $selectedMealTypeID
                )
            }
        }
        .sheet(isPresented: $isShowingMealTypeManagement) {
            NavigationStack {
                MealTypeManagementView()
            }
        }
        .alert("Could Not Save Entry", isPresented: isShowingIngestError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(ingestErrorMessage ?? "Unknown error")
        })
    }

    private var syncStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(syncStatus.title, systemImage: syncStatus.isCloudEnabled ? "icloud" : "externaldrive")
                .font(.subheadline.weight(.semibold))
            Text(syncStatus.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func mealTypeName(for meal: Meal) -> String {
        mealTypes.first(where: { $0.id == meal.typeId })?.displayName ?? "Unknown Meal"
    }

    private func beginIngest(with image: PlatformImage) {
        pendingImage = image
        pendingLoggedAt = Date.now

        do {
            selectedMealTypeID = try service.suggestedMealType(for: pendingLoggedAt)?.id
            if selectedMealTypeID == nil {
                selectedMealTypeID = mealTypes.first?.id
            }
            isShowingMealTypeChooser = true
        } catch {
            ingestErrorMessage = error.localizedDescription
            clearPendingCapture()
        }
    }

    private func savePendingCapture() {
        guard let pendingImage else {
            ingestErrorMessage = "Missing captured image"
            return
        }

        guard let selectedMealTypeID else {
            ingestErrorMessage = "Select a meal type before saving"
            return
        }

        do {
            _ = try service.ingest(
                image: pendingImage,
                mealTypeID: selectedMealTypeID,
                loggedAt: pendingLoggedAt
            )
            clearPendingCapture()
        } catch {
            ingestErrorMessage = error.localizedDescription
        }
    }

    private func clearPendingCapture() {
        pendingImage = nil
        selectedMealTypeID = nil
        isShowingMealTypeChooser = false
    }
}

#Preview {
    NavigationStack {
        HistoryView(syncStatus: .cloudEnabled)
            .modelContainer(for: [Meal.self, MealEntry.self, MealType.self], inMemory: true)
    }
}
