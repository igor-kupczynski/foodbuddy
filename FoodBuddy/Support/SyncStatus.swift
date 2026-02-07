import Foundation

struct SyncStatus {
    let title: String
    let detail: String
    let isCloudEnabled: Bool

    static let cloudEnabled = SyncStatus(
        title: "iCloud Sync Enabled",
        detail: "Meal metadata and photo assets sync through your private iCloud database.",
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
