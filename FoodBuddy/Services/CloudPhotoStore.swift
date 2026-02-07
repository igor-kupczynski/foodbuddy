import CloudKit
import Foundation

struct UploadedPhotoAssetRefs {
    let fullAssetRef: String
    let thumbnailAssetRef: String
}

enum CloudPhotoStoreError: Swift.Error, Equatable {
    case invalidAssetReference
    case assetNotFound
}

protocol CloudPhotoStoring: Actor {
    func upload(
        entryID: UUID,
        fullJPEGData: Data,
        thumbnailJPEGData: Data
    ) async throws -> UploadedPhotoAssetRefs

    func download(assetRef: String) async throws -> Data
}

actor CloudKitPhotoStore: CloudPhotoStoring {
    private enum Constants {
        static let recordType = "EntryPhotoAsset"
        static let entryIDField = "entryId"
        static let updatedAtField = "updatedAt"
        static let fullAssetField = "fullAsset"
        static let thumbAssetField = "thumbAsset"
    }

    private let database: CKDatabase
    private let fileManager: FileManager

    init(database: CKDatabase, fileManager: FileManager = .default) {
        self.database = database
        self.fileManager = fileManager
    }

    static func live(containerIdentifier: String) -> CloudKitPhotoStore {
        let container = CKContainer(identifier: containerIdentifier)
        return CloudKitPhotoStore(database: container.privateCloudDatabase)
    }

    func upload(
        entryID: UUID,
        fullJPEGData: Data,
        thumbnailJPEGData: Data
    ) async throws -> UploadedPhotoAssetRefs {
        let recordID = CKRecord.ID(recordName: entryID.uuidString)
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Constants.recordType, recordID: recordID)
        }

        let fullURL = try makeTemporaryFileURL(suffix: "-full.jpg")
        let thumbURL = try makeTemporaryFileURL(suffix: "-thumb.jpg")
        defer {
            try? fileManager.removeItem(at: fullURL)
            try? fileManager.removeItem(at: thumbURL)
        }

        try fullJPEGData.write(to: fullURL, options: .atomic)
        try thumbnailJPEGData.write(to: thumbURL, options: .atomic)

        record[Constants.entryIDField] = entryID.uuidString as CKRecordValue
        record[Constants.updatedAtField] = Date() as CKRecordValue
        record[Constants.fullAssetField] = CKAsset(fileURL: fullURL)
        record[Constants.thumbAssetField] = CKAsset(fileURL: thumbURL)

        let saved = try await database.save(record)

        let fullRef = makeAssetReference(recordName: saved.recordID.recordName, field: Constants.fullAssetField)
        let thumbRef = makeAssetReference(recordName: saved.recordID.recordName, field: Constants.thumbAssetField)
        return UploadedPhotoAssetRefs(fullAssetRef: fullRef, thumbnailAssetRef: thumbRef)
    }

    func download(assetRef: String) async throws -> Data {
        let parsed = try parseAssetReference(assetRef)
        let record = try await database.record(for: CKRecord.ID(recordName: parsed.recordName))

        guard let asset = record[parsed.field] as? CKAsset,
              let fileURL = asset.fileURL,
              let data = try? Data(contentsOf: fileURL) else {
            throw CloudPhotoStoreError.assetNotFound
        }

        return data
    }

    private func makeTemporaryFileURL(suffix: String) throws -> URL {
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FoodBuddy-PhotoSync", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory.appendingPathComponent("\(UUID().uuidString)\(suffix)", isDirectory: false)
    }

    private func makeAssetReference(recordName: String, field: String) -> String {
        "\(recordName)|\(field)"
    }

    private func parseAssetReference(_ value: String) throws -> (recordName: String, field: String) {
        let components = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            throw CloudPhotoStoreError.invalidAssetReference
        }
        return (components[0], components[1])
    }
}
