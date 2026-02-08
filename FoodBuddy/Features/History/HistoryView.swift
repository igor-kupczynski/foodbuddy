import SwiftData
import SwiftUI
import UIKit

enum HistoryLayoutMode {
    case compact
    case regular
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    let syncStatus: SyncStatus
    let layoutMode: HistoryLayoutMode

    @Query(sort: [SortDescriptor(\Meal.updatedAt, order: .reverse)])
    private var meals: [Meal]

    @Query(sort: [SortDescriptor(\MealType.displayName)])
    private var mealTypes: [MealType]

    @Query(sort: [SortDescriptor(\EntryPhotoAsset.updatedAt, order: .reverse)])
    private var photoAssets: [EntryPhotoAsset]

    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var selection = HistorySelectionState()

    @State private var isShowingCaptureSource = false
    @State private var activeCaptureSource: CaptureSource?
    @State private var isShowingMealTypeChooser = false
    @State private var isShowingMealTypeManagement = false
    @State private var isShowingSyncDiagnostics = false

    @State private var pendingImage: PlatformImage?
    @State private var pendingLoggedAt = Date.now
    @State private var selectedMealTypeID: UUID?

    @State private var hasBootstrappedMealTypes = false
    @State private var isRunningPhotoSync = false
    @State private var ingestErrorMessage: String?

    init(syncStatus: SyncStatus, layoutMode: HistoryLayoutMode = .compact) {
        self.syncStatus = syncStatus
        self.layoutMode = layoutMode
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

    private var selectedMeal: Meal? {
        guard let selectedMealID = selection.selectedMealID else {
            return nil
        }
        return meals.first(where: { $0.id == selectedMealID })
    }

    private var selectedMealEntries: [MealEntry] {
        guard let selectedMeal else {
            return []
        }
        return sortedEntries(for: selectedMeal)
    }

    private var selectedEntry: MealEntry? {
        guard let selectedEntryID = selection.selectedEntryID else {
            return nil
        }
        return selectedMealEntries.first(where: { $0.id == selectedEntryID })
    }

    private var selectedMealTypeName: String {
        guard let selectedMeal else {
            return "Entries"
        }
        return mealTypeName(for: selectedMeal)
    }

    var body: some View {
        rootContent
            .task {
                if !hasBootstrappedMealTypes {
                    do {
                        try service.bootstrapMealTypesIfNeeded()
                        hasBootstrappedMealTypes = true
                    } catch {
                        ingestErrorMessage = error.localizedDescription
                    }
                }

                reconcileSelectionIfNeeded()
                await runPhotoSyncCycle()
            }
            .onChange(of: meals.map(\.id)) { _, _ in
                reconcileSelectionIfNeeded()
            }
            .onChange(of: selectedMealEntries.map(\.id)) { _, _ in
                reconcileSelectionIfNeeded()
            }
            .onChange(of: selection.selectedMealID) { oldValue, newValue in
                guard oldValue != newValue else {
                    return
                }

                selection.selectedEntryID = nil
                reconcileSelectionIfNeeded()
            }
            .confirmationDialog("Add Meal", isPresented: $isShowingCaptureSource, titleVisibility: .visible) {
                Button(CaptureSource.camera.title) {
                    queueCapturePresentation(for: .camera)
                }

                Button(CaptureSource.library.title) {
                    queueCapturePresentation(for: .library)
                }

                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(item: $activeCaptureSource) { source in
                switch source {
                case .camera:
                    if AppRuntimeFlags.useMockCameraCapture {
                        MockCameraCaptureView { image in
                            beginIngest(with: image)
                        }
                    } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
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
                case .library:
                    LibraryPicker { image in
                        beginIngest(with: image)
                    }
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
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isShowingMealTypeManagement) {
                NavigationStack {
                    MealTypeManagementView()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingSyncDiagnostics) {
                NavigationStack {
                    PhotoSyncDiagnosticsView(syncStatus: syncStatus)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert("Could Not Save Entry", isPresented: isShowingIngestError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(ingestErrorMessage ?? "Unknown error")
            })
    }

    @ViewBuilder
    private var rootContent: some View {
        switch layoutMode {
        case .compact:
            compactHistoryView
        case .regular:
            regularHistoryView
        }
    }

    private var compactHistoryView: some View {
        List {
            Section {
                syncStatusRow
            }
            .listRowSeparator(.hidden)

            if meals.isEmpty {
                emptyMealsView
                    .listRowSeparator(.hidden)
            } else {
                ForEach(meals) { meal in
                    NavigationLink {
                        MealDetailView(
                            meal: meal,
                            mealTypeName: mealTypeName(for: meal),
                            syncStatus: syncStatus
                        )
                    } label: {
                        mealRow(for: meal)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .toolbar {
            historyToolbar
        }
    }

    private var regularHistoryView: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List(selection: $selection.selectedMealID) {
                Section {
                    syncStatusRow
                }
                .listRowSeparator(.hidden)

                Section("Meals") {
                    if meals.isEmpty {
                        emptyMealsView
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(meals) { meal in
                            mealRow(for: meal)
                                .tag(Optional(meal.id))
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                historyToolbar
            }
        } content: {
            if selectedMeal == nil {
                ContentUnavailableView(
                    "Select a Meal",
                    systemImage: "fork.knife.circle",
                    description: Text("Choose a meal from the sidebar to view entries.")
                )
                .navigationTitle("Entries")
            } else {
                List(selection: $selection.selectedEntryID) {
                    if selectedMealEntries.isEmpty {
                        ContentUnavailableView(
                            "No Entries",
                            systemImage: "tray",
                            description: Text("This meal currently has no saved entries.")
                        )
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(selectedMealEntries) { entry in
                            EntryRowView(entry: entry, imageStore: imageStore)
                                .tag(Optional(entry.id))
                        }
                    }
                }
                .navigationTitle(selectedMealTypeName)
            }
        } detail: {
            if let selectedEntry {
                EntryDetailView(
                    entry: selectedEntry,
                    syncStatus: syncStatus,
                    onDelete: {
                        selection.selectEntry(nil)
                        DispatchQueue.main.async {
                            reconcileSelectionIfNeeded()
                        }
                    }
                )
                .id(selectedEntry.id)
            } else {
                ContentUnavailableView(
                    "Select an Entry",
                    systemImage: "photo",
                    description: Text("Pick an entry to view and edit details.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
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

    private func mealRow(for meal: Meal) -> some View {
        MealRowView(
            meal: meal,
            mealTypeName: mealTypeName(for: meal),
            imageStore: imageStore
        )
    }

    private var emptyMealsView: some View {
        ContentUnavailableView(
            "No Meals Yet",
            systemImage: "fork.knife.circle",
            description: Text("Tap Add to capture or choose a meal photo.")
        )
        .frame(maxWidth: .infinity)
    }

    private var syncStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(syncStatus.title, systemImage: syncStatus.isCloudEnabled ? "icloud" : "externaldrive")
                .font(.subheadline.weight(.semibold))
            Text(syncStatus.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(photoSyncSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Photo Sync Details") {
                    isShowingSyncDiagnostics = true
                }
                .buttonStyle(.bordered)

                if failedPhotoSyncCount > 0 {
                    Button("Retry Failed") {
                        Task {
                            await photoSyncService.retryFailedNow()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sortedEntries(for meal: Meal) -> [MealEntry] {
        meal.entries.sorted(by: { $0.loggedAt > $1.loggedAt })
    }

    private func mealTypeName(for meal: Meal) -> String {
        mealTypes.first(where: { $0.id == meal.typeId })?.displayName ?? "Unknown Meal"
    }

    private func queueCapturePresentation(for source: CaptureSource) {
        DispatchQueue.main.async {
            activeCaptureSource = source
        }
    }

    private func beginIngest(with image: PlatformImage) {
        pendingImage = image
        pendingLoggedAt = Date.now

        do {
            selectedMealTypeID = try service.suggestedMealType(for: pendingLoggedAt)?.id
            if selectedMealTypeID == nil {
                selectedMealTypeID = mealTypes.first?.id
            }

            DispatchQueue.main.async {
                isShowingMealTypeChooser = true
            }
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
            reconcileSelectionIfNeeded()

            Task {
                await runPhotoSyncCycle()
            }
        } catch {
            ingestErrorMessage = error.localizedDescription
        }
    }

    private func clearPendingCapture() {
        pendingImage = nil
        selectedMealTypeID = nil
        isShowingMealTypeChooser = false
    }

    private func reconcileSelectionIfNeeded() {
        guard layoutMode == .regular else {
            return
        }

        let next = selection.reconciled(
            meals: meals,
            autoSelectFirstMeal: true,
            autoSelectFirstEntry: true
        )

        guard next != selection else {
            return
        }

        selection = next
    }

    private var failedPhotoSyncCount: Int {
        photoAssets.filter { $0.state == .failed }.count
    }

    private var photoSyncSummaryText: String {
        let pending = photoAssets.filter { $0.state == .pending }.count
        let failed = photoAssets.filter { $0.state == .failed }.count
        let uploaded = photoAssets.filter { $0.state == .uploaded }.count

        return "Photos: \(uploaded) synced, \(pending) pending, \(failed) failed"
    }

    private func runPhotoSyncCycle() async {
        if isRunningPhotoSync {
            return
        }

        isRunningPhotoSync = true
        defer { isRunningPhotoSync = false }
        await photoSyncService.runSyncCycle()
    }
}

#Preview {
    NavigationStack {
        HistoryView(syncStatus: .cloudEnabled, layoutMode: .compact)
            .modelContainer(for: [Meal.self, MealEntry.self, MealType.self, EntryPhotoAsset.self], inMemory: true)
    }
}
