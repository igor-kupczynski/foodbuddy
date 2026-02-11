import Foundation

struct ImageStore: @unchecked Sendable {
    enum Error: Swift.Error {
        case imageEncodingFailed
    }

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let uuidProvider: () -> UUID
    private let compressionQuality: CGFloat

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL,
        uuidProvider: @escaping () -> UUID = UUID.init,
        compressionQuality: CGFloat = 0.8
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.uuidProvider = uuidProvider
        self.compressionQuality = compressionQuality
    }

    static func live(fileManager: FileManager = .default) -> ImageStore {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDirectory = documentsDirectory.appendingPathComponent("MealImages", isDirectory: true)
        return ImageStore(fileManager: fileManager, baseDirectory: imagesDirectory)
    }

    func saveJPEG(_ image: PlatformImage) throws -> String {
        guard let data = image.foodBuddyJPEGData(compressionQuality: compressionQuality) else {
            throw Error.imageEncodingFailed
        }

        return try saveJPEGData(data)
    }

    func saveJPEGData(_ data: Data, preferredFilename: String? = nil) throws -> String {
        try ensureDirectoryExists()

        let filename = preferredFilename ?? "\(uuidProvider().uuidString).jpg"
        let destination = url(for: filename)
        try data.write(to: destination, options: .atomic)
        return filename
    }

    func loadImage(filename: String) -> PlatformImage? {
        guard let data = loadData(filename: filename) else {
            return nil
        }
        return PlatformImage.fromFoodBuddyData(data)
    }

    func loadData(filename: String) -> Data? {
        let imageURL = url(for: filename)
        return try? Data(contentsOf: imageURL)
    }

    func fileExists(filename: String) -> Bool {
        fileManager.fileExists(atPath: url(for: filename).path)
    }

    func deleteImage(filename: String) throws {
        let imageURL = url(for: filename)
        do {
            try fileManager.removeItem(at: imageURL)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
                return
            }
            throw error
        }
    }

    func url(for filename: String) -> URL {
        baseDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDirectory)
        if exists {
            if isDirectory.boolValue {
                return
            }
            throw CocoaError(.fileWriteFileExists)
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
