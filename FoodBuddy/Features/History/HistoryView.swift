import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\MealEntry.createdAt, order: .reverse)])
    private var entries: [MealEntry]

    @State private var isShowingCaptureSource = false
    @State private var isShowingCamera = false
    @State private var isShowingLibraryPicker = false
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
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Meals Yet",
                    systemImage: "fork.knife.circle",
                    description: Text("Tap Add to capture or choose a meal photo.")
                )
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        EntryRowView(entry: entry, imageStore: imageStore)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") {
                    isShowingCaptureSource = true
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
                    ingestCameraImage(image)
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
                ingestLibraryImage(image)
            }
        }
        .alert("Could Not Save Entry", isPresented: isShowingIngestError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(ingestErrorMessage ?? "Unknown error")
        })
    }

    private func ingestCameraImage(_ image: PlatformImage) {
        let coordinator = CaptureIngestCoordinator(ingestService: service)
        do {
            try coordinator.ingestFromCamera(image)
        } catch {
            ingestErrorMessage = error.localizedDescription
        }
    }

    private func ingestLibraryImage(_ image: PlatformImage) {
        let coordinator = CaptureIngestCoordinator(ingestService: service)
        do {
            try coordinator.ingestFromLibrary(image)
        } catch {
            ingestErrorMessage = error.localizedDescription
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            do {
                try service.delete(entry: entry)
            } catch {
                ingestErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
            .modelContainer(for: [MealEntry.self], inMemory: true)
    }
}
