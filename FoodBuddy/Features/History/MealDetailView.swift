import SwiftData
import SwiftUI

struct MealDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    let meal: Meal
    let mealTypeName: String
    let syncStatus: SyncStatus

    @State private var errorMessage: String?
    @State private var notesDraft = ""
    @State private var isRunningFoodAnalysis = false
    @State private var isShowingFailureDetails = false

    private var imageStore: ImageStore {
        Dependencies.makeImageStore()
    }

    private var service: MealEntryService {
        Dependencies.makeMealEntryService(modelContext: modelContext)
    }

    private var foodAnalysisCoordinator: FoodAnalysisCoordinator {
        Dependencies.makeFoodAnalysisCoordinator(modelContext: modelContext)
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
            aiDescriptionSection

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
        .onAppear {
            notesDraft = meal.userNotes ?? ""
        }
        .onChange(of: meal.userNotes) { _, newValue in
            let nextValue = newValue ?? ""
            if notesDraft != nextValue {
                notesDraft = nextValue
            }
        }
        .alert("Could Not Update Meal", isPresented: isShowingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
        .sheet(isPresented: $isShowingFailureDetails) {
            AnalysisErrorDetailsSheet(details: meal.aiAnalysisErrorDetails ?? "No details available.")
        }
    }

    private var sortedEntries: [MealEntry] {
        meal.entries.sorted(by: { $0.loggedAt > $1.loggedAt })
    }

    @ViewBuilder
    private var aiDescriptionSection: some View {
        Section("AI Description") {
            if meal.aiAnalysisStatus == .none && !hasConfiguredAPIKey {
                Text("Set up AI in Settings to get meal descriptions.")
                    .foregroundStyle(.secondary)
            } else if meal.aiAnalysisStatus == .pending || meal.aiAnalysisStatus == .analyzing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing...")
                        .foregroundStyle(.secondary)
                }
            } else if meal.aiAnalysisStatus == .completed {
                if let description = meal.aiDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    Text(description)
                } else {
                    Text("Analysis completed but no description is available.")
                        .foregroundStyle(.secondary)
                }
            } else if meal.aiAnalysisStatus == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis failed. Update notes and try again.")
                        .foregroundStyle(.secondary)
                    if meal.aiAnalysisErrorDetails != nil {
                        Button("Show details") {
                            isShowingFailureDetails = true
                        }
                        .font(.footnote)
                    }
                }
            } else {
                Text("No AI description yet.")
                    .foregroundStyle(.secondary)
            }
        }

        if shouldShowAIControls {
            Section("Notes") {
                TextField("Any details? (optional)", text: $notesDraft, axis: .vertical)
                    .lineLimit(2...4)

                Button("Re-analyze") {
                    reAnalyze()
                }
                .disabled(isRunningFoodAnalysis || !hasConfiguredAPIKey)
            }
        }
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

    private var shouldShowAIControls: Bool {
        hasConfiguredAPIKey || meal.aiAnalysisStatus != .none || !(meal.userNotes ?? "").isEmpty
    }

    private var hasConfiguredAPIKey: Bool {
        let key = (try? Dependencies.makeMistralAPIKeyStore().apiKey())?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    private func reAnalyze() {
        guard hasConfiguredAPIKey else {
            errorMessage = "Configure your Mistral API key in AI Settings first."
            return
        }

        do {
            try service.updateMealNotes(notesDraft, for: meal)
            try service.queueMealForAnalysis(meal)
            Task {
                await runFoodAnalysisCycle()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runFoodAnalysisCycle() async {
        if isRunningFoodAnalysis {
            return
        }

        isRunningFoodAnalysis = true
        defer { isRunningFoodAnalysis = false }
        await foodAnalysisCoordinator.processPendingMeals()
    }
}

private struct AnalysisErrorDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: String
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(details)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Analysis Error")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = details
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }
}
