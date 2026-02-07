import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: MealEntry

    @State private var isShowingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    private var imageStore: ImageStore {
        Dependencies.makeImageStore()
    }

    private var service: MealEntryService {
        Dependencies.makeMealEntryService(modelContext: modelContext)
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
        .alert("Could Not Delete Entry", isPresented: isShowingDeleteError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(deleteErrorMessage ?? "Unknown error")
        })
    }

    @ViewBuilder
    private var imageSection: some View {
        if let image = imageStore.loadImage(filename: entry.imageFilename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ContentUnavailableView(
                "Image Not Found",
                systemImage: "photo.badge.exclamationmark",
                description: Text("The image file is missing from local storage.")
            )
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
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
}
