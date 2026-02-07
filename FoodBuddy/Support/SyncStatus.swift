import Foundation

struct SyncStatus {
    let title: String
    let detail: String
    let isCloudEnabled: Bool

    static let cloudEnabled = SyncStatus(
        title: "iCloud Metadata Sync Enabled",
        detail: "Meal metadata syncs through your private iCloud database.",
        isCloudEnabled: true
    )

    static func localOnly(reason: String) -> SyncStatus {
        SyncStatus(
            title: "Local-Only Mode",
            detail: reason,
            isCloudEnabled: false
        )
    }
}
