import XCTest

final class ImageStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = ImageStore(baseDirectory: tempDirectory)
        let image = TestImageFactory.make(color: .systemRed)

        let filename = try store.saveJPEG(image)
        let savedURL = store.url(for: filename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertNotNil(store.loadImage(filename: filename))
    }

    func testDeleteMissingFileIsNoop() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = ImageStore(baseDirectory: tempDirectory)

        XCTAssertNoThrow(try store.deleteImage(filename: "does-not-exist.jpg"))
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodBuddy-ImageStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
