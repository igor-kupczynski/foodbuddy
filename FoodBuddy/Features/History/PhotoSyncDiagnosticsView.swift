import SwiftData
import SwiftUI

struct PhotoSyncDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let syncStatus: SyncStatus

    @Query(sort: [SortDescriptor(\EntryPhotoAsset.updatedAt, order: .reverse)])
    private var photoAssets: [EntryPhotoAsset]

    @State private var isSyncing = false

    private var service: PhotoSyncService {
        Dependencies.makePhotoSyncService(modelContext: modelContext, syncStatus: syncStatus)
    }

    var body: some View {
        List {
            Section("Overview") {
                row(title: "Cloud", value: syncStatus.isCloudEnabled ? "Enabled" : "Disabled")
                row(title: "Uploaded", value: "\(uploadedCount)")
                row(title: "Pending", value: "\(pendingCount)")
                row(title: "Failed", value: "\(failedCount)")
                row(title: "Waiting Retry", value: "\(waitingRetryCount)")
            }

            Section("Actions") {
                Button(isSyncing ? "Syncing..." : "Run Sync Now") {
                    Task { await runSync() }
                }
                .disabled(isSyncing)

                Button("Retry Failed") {
                    Task { await retryFailed() }
                }
                .disabled(isSyncing || failedCount == 0)
            }

            if !failedAssets.isEmpty {
                Section("Recent Failures") {
                    ForEach(failedAssets) { asset in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.entryId.uuidString)
                                .font(.caption.monospaced())
                                .lineLimit(1)

                            Text(asset.lastError ?? "Unknown error")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let nextRetryAt = asset.nextRetryAt {
                                Text("Next retry: \(nextRetryAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Photo Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var uploadedCount: Int {
        photoAssets.filter { $0.state == .uploaded }.count
    }

    private var pendingCount: Int {
        photoAssets.filter { $0.state == .pending }.count
    }

    private var failedCount: Int {
        photoAssets.filter { $0.state == .failed }.count
    }

    private var waitingRetryCount: Int {
        let now = Date.now
        return photoAssets.filter { asset in
            guard asset.state == .failed, let nextRetryAt = asset.nextRetryAt else {
                return false
            }
            return nextRetryAt > now
        }.count
    }

    private var failedAssets: [EntryPhotoAsset] {
        photoAssets.filter { $0.state == .failed }
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func runSync() async {
        isSyncing = true
        defer { isSyncing = false }
        await service.runSyncCycle()
    }

    private func retryFailed() async {
        isSyncing = true
        defer { isSyncing = false }
        await service.retryFailedNow()
    }
}
