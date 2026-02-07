import Foundation

struct ImageStore {
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
        try ensureDirectoryExists()

        guard let data = image.foodBuddyJPEGData(compressionQuality: compressionQuality) else {
            throw Error.imageEncodingFailed
        }

        let filename = "\(uuidProvider().uuidString).jpg"
        let destination = url(for: filename)
        try data.write(to: destination, options: .atomic)
        return filename
    }

    func loadImage(filename: String) -> PlatformImage? {
        let imageURL = url(for: filename)
        guard let data = try? Data(contentsOf: imageURL) else {
            return nil
        }
        return PlatformImage.fromFoodBuddyData(data)
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
