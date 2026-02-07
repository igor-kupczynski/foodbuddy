import Foundation
import SwiftData

@MainActor
final class PhotoSyncService {
    struct Diagnostics {
        let pendingCount: Int
        let failedCount: Int
        let uploadedCount: Int
        let waitingForRetryCount: Int
    }

    private struct UploadPayload {
        let fullFilename: String
        let fullData: Data
        let thumbnailFilename: String
        let thumbnailData: Data
    }

    private enum Constants {
        static let retryBaseSeconds: TimeInterval = 5
        static let retryMaxSeconds: TimeInterval = 3600
    }

    private let modelContext: ModelContext
    private let imageStore: ImageStore
    private let preprocessor: ImagePreprocessor
    private let cloudStore: (any CloudPhotoStoring)?
    private let nowProvider: () -> Date

    init(
        modelContext: ModelContext,
        imageStore: ImageStore,
        preprocessor: ImagePreprocessor = ImagePreprocessor(),
        cloudStore: (any CloudPhotoStoring)? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.imageStore = imageStore
        self.preprocessor = preprocessor
        self.cloudStore = cloudStore
        self.nowProvider = nowProvider
    }

    func runSyncCycle() async {
        do {
            try bootstrapLocalPhotoAssetsIfNeeded()
            try repairStaleLinks()
            await uploadPendingAssets()
            await hydrateMissingAssets()
        } catch {
            return
        }
    }

    func retryFailedNow() async {
        do {
            let now = nowProvider()
            for asset in try fetchAssets() where asset.state == .failed {
                asset.state = .pending
                asset.nextRetryAt = now
                asset.updatedAt = now
            }
            try save()
        } catch {
            return
        }

        await runSyncCycle()
    }

    func retryAsset(entryID: UUID) async {
        do {
            guard let asset = try fetchAsset(entryID: entryID) else {
                return
            }

            let now = nowProvider()
            asset.state = .pending
            asset.nextRetryAt = now
            asset.updatedAt = now
            try save()
        } catch {
            return
        }

        await runSyncCycle()
    }

    func bootstrapLocalPhotoAssetsIfNeeded() throws {
        let entries = try modelContext.fetch(FetchDescriptor<MealEntry>())
        var didChange = false

        for entry in entries {
            if entry.photoAsset == nil {
                let now = nowProvider()
                let fullFilename = entry.imageFilename

                var state: PhotoAssetSyncState = .pending
                var lastError: String?
                var retryCount = 0
                var nextRetryAt: Date?

                var thumbnailFilename: String?
                if imageStore.fileExists(filename: fullFilename) {
                    thumbnailFilename = try? ensureThumbnailFilename(forAssetID: entry.id, fullFilename: fullFilename)
                } else {
                    state = .failed
                    lastError = "Missing local source image for bootstrap"
                    retryCount = 1
                    nextRetryAt = now.addingTimeInterval(nextBackoff(forRetryCount: retryCount))
                }

                let asset = EntryPhotoAsset(
                    id: entry.id,
                    entryId: entry.id,
                    fullImageFilename: fullFilename,
                    thumbnailFilename: thumbnailFilename,
                    state: state,
                    lastError: lastError,
                    retryCount: retryCount,
                    nextRetryAt: nextRetryAt,
                    updatedAt: now,
                    entry: entry
                )

                entry.photoAsset = asset
                entry.photoAssetId = asset.id
                modelContext.insert(asset)
                didChange = true
            } else if entry.photoAssetId == nil {
                entry.photoAssetId = entry.photoAsset?.id
                didChange = true
            }

            if let asset = entry.photoAsset,
               asset.thumbnailFilename == nil,
               let fullFilename = asset.fullImageFilename,
               imageStore.fileExists(filename: fullFilename) {
                asset.thumbnailFilename = try? ensureThumbnailFilename(forAssetID: asset.id, fullFilename: fullFilename)
                asset.updatedAt = nowProvider()
                didChange = true
            }
        }

        if didChange {
            try save()
        }
    }

    func diagnostics() throws -> Diagnostics {
        let now = nowProvider()
        let assets = try fetchAssets().filter { $0.state != .deleted }

        let pendingCount = assets.filter { $0.state == .pending }.count
        let failedCount = assets.filter { $0.state == .failed }.count
        let uploadedCount = assets.filter { $0.state == .uploaded }.count
        let waitingForRetryCount = assets.filter { asset in
            guard asset.state == .failed, let nextRetryAt = asset.nextRetryAt else {
                return false
            }
            return nextRetryAt > now
        }.count

        return Diagnostics(
            pendingCount: pendingCount,
            failedCount: failedCount,
            uploadedCount: uploadedCount,
            waitingForRetryCount: waitingForRetryCount
        )
    }

    func recentFailures(limit: Int = 20) throws -> [EntryPhotoAsset] {
        try fetchAssets()
            .filter { $0.state == .failed }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(limit)
            .map { $0 }
    }

    private func uploadPendingAssets() async {
        guard let cloudStore else {
            return
        }

        do {
            let now = nowProvider()
            let candidates = try fetchAssets().filter { asset in
                switch asset.state {
                case .pending:
                    return true
                case .failed:
                    guard let nextRetryAt = asset.nextRetryAt else {
                        return true
                    }
                    return nextRetryAt <= now
                case .uploaded, .deleted:
                    return false
                }
            }

            for asset in candidates {
                guard let entry = asset.entry else {
                    asset.state = .deleted
                    asset.updatedAt = nowProvider()
                    continue
                }

                do {
                    let payload = try makeUploadPayload(for: asset, entry: entry)
                    let refs = try await cloudStore.upload(
                        entryID: entry.id,
                        fullJPEGData: payload.fullData,
                        thumbnailJPEGData: payload.thumbnailData
                    )

                    asset.fullAssetRef = refs.fullAssetRef
                    asset.thumbAssetRef = refs.thumbnailAssetRef
                    asset.fullImageFilename = payload.fullFilename
                    asset.thumbnailFilename = payload.thumbnailFilename
                    asset.state = .uploaded
                    asset.lastError = nil
                    asset.retryCount = 0
                    asset.nextRetryAt = nil
                    asset.updatedAt = nowProvider()

                    entry.imageFilename = payload.fullFilename
                    entry.photoAssetId = asset.id
                    entry.updatedAt = nowProvider()
                } catch {
                    markUploadFailure(asset: asset, error: error)
                }
            }

            try save()
        } catch {
            return
        }
    }

    private func hydrateMissingAssets() async {
        guard let cloudStore else {
            return
        }

        do {
            let candidates = try fetchAssets().filter { asset in
                guard asset.state == .uploaded else {
                    return false
                }
                return shouldHydrate(asset)
            }

            for asset in candidates {
                do {
                    try await hydrate(asset: asset, cloudStore: cloudStore)
                } catch {
                    markUploadFailure(asset: asset, error: error)
                }
            }

            try save()
        } catch {
            return
        }
    }

    private func shouldHydrate(_ asset: EntryPhotoAsset) -> Bool {
        let isMissingFull: Bool
        if let filename = asset.fullImageFilename {
            isMissingFull = !imageStore.fileExists(filename: filename)
        } else {
            isMissingFull = true
        }

        let isMissingThumbnail: Bool
        if let filename = asset.thumbnailFilename {
            isMissingThumbnail = !imageStore.fileExists(filename: filename)
        } else {
            isMissingThumbnail = true
        }

        if isMissingFull {
            return asset.fullAssetRef != nil
        }

        if isMissingThumbnail {
            return asset.thumbAssetRef != nil
        }

        return false
    }

    private func hydrate(asset: EntryPhotoAsset, cloudStore: any CloudPhotoStoring) async throws {
        if (asset.thumbnailFilename == nil || !(asset.thumbnailFilename.map { imageStore.fileExists(filename: $0) } ?? false)),
           let thumbRef = asset.thumbAssetRef {
            let data = try await cloudStore.download(assetRef: thumbRef)
            let filename = try imageStore.saveJPEGData(data, preferredFilename: "\(asset.id.uuidString)-thumb.jpg")
            asset.thumbnailFilename = filename
        }

        if (asset.fullImageFilename == nil || !(asset.fullImageFilename.map { imageStore.fileExists(filename: $0) } ?? false)),
           let fullRef = asset.fullAssetRef {
            let data = try await cloudStore.download(assetRef: fullRef)
            let filename = try imageStore.saveJPEGData(data, preferredFilename: "\(asset.id.uuidString)-full.jpg")
            asset.fullImageFilename = filename
            asset.entry?.imageFilename = filename
        }

        asset.state = .uploaded
        asset.lastError = nil
        asset.nextRetryAt = nil
        asset.updatedAt = nowProvider()
    }

    private func makeUploadPayload(for asset: EntryPhotoAsset, entry: MealEntry) throws -> UploadPayload {
        let fullFilename = asset.fullImageFilename ?? entry.imageFilename
        guard let fullData = imageStore.loadData(filename: fullFilename) else {
            throw CloudPhotoStoreError.assetNotFound
        }

        var thumbnailFilename = asset.thumbnailFilename
        if thumbnailFilename == nil || !(thumbnailFilename.map { imageStore.fileExists(filename: $0) } ?? false) {
            thumbnailFilename = try ensureThumbnailFilename(forAssetID: asset.id, fullFilename: fullFilename)
        }

        guard let resolvedThumbnailFilename = thumbnailFilename,
              let thumbnailData = imageStore.loadData(filename: resolvedThumbnailFilename) else {
            throw CloudPhotoStoreError.assetNotFound
        }

        return UploadPayload(
            fullFilename: fullFilename,
            fullData: fullData,
            thumbnailFilename: resolvedThumbnailFilename,
            thumbnailData: thumbnailData
        )
    }

    private func ensureThumbnailFilename(forAssetID assetID: UUID, fullFilename: String) throws -> String {
        let preferredFilename = "\(assetID.uuidString)-thumb.jpg"
        if imageStore.fileExists(filename: preferredFilename) {
            return preferredFilename
        }

        guard let image = imageStore.loadImage(filename: fullFilename) else {
            throw CloudPhotoStoreError.assetNotFound
        }

        let processed = try preprocessor.preprocess(image)
        return try imageStore.saveJPEGData(processed.thumbnailJPEGData, preferredFilename: preferredFilename)
    }

    private func repairStaleLinks() throws {
        var didChange = false

        let assets = try fetchAssets()
        for asset in assets where asset.entry == nil && asset.state != .deleted {
            asset.state = .deleted
            asset.lastError = nil
            asset.updatedAt = nowProvider()
            didChange = true
        }

        let entries = try modelContext.fetch(FetchDescriptor<MealEntry>())
        for entry in entries {
            if entry.photoAssetId == nil, let linked = entry.photoAsset {
                entry.photoAssetId = linked.id
                didChange = true
            }

            if let linked = entry.photoAsset,
               let fullFilename = linked.fullImageFilename,
               imageStore.fileExists(filename: fullFilename),
               entry.imageFilename != fullFilename {
                entry.imageFilename = fullFilename
                didChange = true
            }
        }

        if didChange {
            try save()
        }
    }

    private func fetchAssets() throws -> [EntryPhotoAsset] {
        let descriptor = FetchDescriptor<EntryPhotoAsset>(
            sortBy: [SortDescriptor(\EntryPhotoAsset.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchAsset(entryID: UUID) throws -> EntryPhotoAsset? {
        let assets = try fetchAssets()
        return assets.first(where: { $0.entryId == entryID })
    }

    private func markUploadFailure(asset: EntryPhotoAsset, error: any Swift.Error) {
        let retryCount = asset.retryCount + 1
        let now = nowProvider()
        asset.state = .failed
        asset.retryCount = retryCount
        asset.nextRetryAt = now.addingTimeInterval(nextBackoff(forRetryCount: retryCount))
        asset.lastError = String(describing: error)
        asset.updatedAt = now
    }

    private func nextBackoff(forRetryCount retryCount: Int) -> TimeInterval {
        guard retryCount > 0 else {
            return Constants.retryBaseSeconds
        }

        let exponent = min(12, retryCount - 1)
        let delay = Constants.retryBaseSeconds * pow(2, Double(exponent))
        return min(Constants.retryMaxSeconds, delay)
    }

    private func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
