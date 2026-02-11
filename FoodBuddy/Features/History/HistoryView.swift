import SwiftData
import SwiftUI
import UIKit

enum HistoryLayoutMode {
    case compact
    case regular
}

struct HistoryView: View {
    private struct PendingCaptureSession: Identifiable {
        let id = UUID()
        let initialImage: PlatformImage
        let loggedAt: Date
        let suggestedMealTypeID: UUID?
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var activeCaptureSession: PendingCaptureSession?
    @State private var stagedCaptureSession: PendingCaptureSession?
    @State private var shouldShowCaptureSessionAfterDismiss = false
    @State private var isShowingMealTypeManagement = false
    @State private var isShowingSyncDiagnostics = false
    @State private var isShowingAISettings = false

    @State private var hasBootstrappedMealTypes = false
    @State private var isRunningPhotoSync = false
    @State private var isRunningFoodAnalysis = false
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

    private var foodAnalysisCoordinator: FoodAnalysisCoordinator {
        Dependencies.makeFoodAnalysisCoordinator(modelContext: modelContext)
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
                await runFoodAnalysisCycle()
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
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else {
                    return
                }

                Task {
                    await runFoodAnalysisCycle()
                }
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
            .fullScreenCover(item: $activeCaptureSource, onDismiss: handleCaptureDismissal) { source in
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
            .sheet(item: $activeCaptureSession, onDismiss: clearPendingCapture) { capture in
                CaptureSessionView(
                    initialImage: capture.initialImage,
                    mealTypes: mealTypes,
                    loggedAt: capture.loggedAt,
                    initialMealTypeID: capture.suggestedMealTypeID,
                    onSave: saveCaptureSession,
                    onCancel: clearPendingCapture,
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            .sheet(isPresented: $isShowingAISettings) {
                NavigationStack {
                    AISettingsView()
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

        ToolbarItem(placement: .topBarLeading) {
            Button("AI Settings") {
                isShowingAISettings = true
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
        let loggedAt = Date.now

        do {
            let suggestedMealTypeID = try service.suggestedMealType(for: loggedAt)?.id ?? mealTypes.first?.id
            let capture = PendingCaptureSession(
                initialImage: image,
                loggedAt: loggedAt,
                suggestedMealTypeID: suggestedMealTypeID
            )
            stagedCaptureSession = capture

            if activeCaptureSource == nil {
                activeCaptureSession = capture
            } else {
                shouldShowCaptureSessionAfterDismiss = true
            }
        } catch {
            ingestErrorMessage = error.localizedDescription
            clearPendingCapture()
        }
    }

    private func handleCaptureDismissal() {
        guard shouldShowCaptureSessionAfterDismiss else {
            return
        }

        shouldShowCaptureSessionAfterDismiss = false

        guard let stagedCaptureSession else {
            ingestErrorMessage = "Could not load the selected image. Please try again."
            return
        }

        activeCaptureSession = stagedCaptureSession
    }

    private func saveCaptureSession(_ payload: CaptureSessionPayload) {
        guard !payload.images.isEmpty else {
            ingestErrorMessage = "Missing captured image"
            return
        }

        do {
            let hasAPIKey = hasConfiguredAPIKey()
            let aiStatus: AIAnalysisStatus = hasAPIKey ? .pending : .none
            _ = try service.ingest(
                images: payload.images,
                mealTypeID: payload.mealTypeID,
                loggedAt: payload.loggedAt,
                userNotes: payload.notes,
                aiAnalysisStatus: aiStatus
            )
            clearPendingCapture()
            reconcileSelectionIfNeeded()

            Task {
                await runPhotoSyncCycle()
                await runFoodAnalysisCycle()
            }
        } catch {
            ingestErrorMessage = error.localizedDescription
        }
    }

    private func clearPendingCapture() {
        stagedCaptureSession = nil
        activeCaptureSession = nil
        shouldShowCaptureSessionAfterDismiss = false
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

    private func runFoodAnalysisCycle() async {
        if isRunningFoodAnalysis {
            return
        }

        isRunningFoodAnalysis = true
        defer { isRunningFoodAnalysis = false }
        await foodAnalysisCoordinator.processPendingMeals()
    }

    private func hasConfiguredAPIKey() -> Bool {
        let key = (try? Dependencies.makeMistralAPIKeyStore().apiKey())?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }
}

#Preview {
    NavigationStack {
        HistoryView(syncStatus: .cloudEnabled, layoutMode: .compact)
            .modelContainer(for: [Meal.self, MealEntry.self, MealType.self, EntryPhotoAsset.self], inMemory: true)
    }
}
