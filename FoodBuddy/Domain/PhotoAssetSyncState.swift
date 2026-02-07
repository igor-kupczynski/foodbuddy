import Foundation

enum PhotoAssetSyncState: String, CaseIterable {
    case pending
    case uploaded
    case failed
    case deleted
}
