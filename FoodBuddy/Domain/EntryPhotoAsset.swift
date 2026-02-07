import Foundation
import SwiftData

@Model
final class EntryPhotoAsset: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var entryId: UUID
    var fullAssetRef: String?
    var thumbAssetRef: String?
    var fullImageFilename: String?
    var thumbnailFilename: String?
    var stateRawValue: String
    var lastError: String?
    var retryCount: Int
    var nextRetryAt: Date?
    var updatedAt: Date

    @Relationship
    var entry: MealEntry?

    var state: PhotoAssetSyncState {
        get { PhotoAssetSyncState(rawValue: stateRawValue) ?? .pending }
        set { stateRawValue = newValue.rawValue }
    }

    init(
        id: UUID,
        entryId: UUID,
        fullAssetRef: String? = nil,
        thumbAssetRef: String? = nil,
        fullImageFilename: String? = nil,
        thumbnailFilename: String? = nil,
        state: PhotoAssetSyncState = .pending,
        lastError: String? = nil,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil,
        updatedAt: Date = .now,
        entry: MealEntry? = nil
    ) {
        self.id = id
        self.entryId = entryId
        self.fullAssetRef = fullAssetRef
        self.thumbAssetRef = thumbAssetRef
        self.fullImageFilename = fullImageFilename
        self.thumbnailFilename = thumbnailFilename
        self.stateRawValue = state.rawValue
        self.lastError = lastError
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.updatedAt = updatedAt
        self.entry = entry
    }
}
