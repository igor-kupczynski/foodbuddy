import Foundation
import XCTest

final class MetadataConflictResolverTests: XCTestCase {
    func testRemoteWinsWhenRemoteUpdatedAtIsNewer() {
        let local = DummyEntity(value: "local", updatedAt: Date(timeIntervalSince1970: 100))
        let remote = DummyEntity(value: "remote", updatedAt: Date(timeIntervalSince1970: 200))

        let resolved = MetadataConflictResolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolved.value, "remote")
    }

    func testLocalWinsWhenLocalUpdatedAtIsNewer() {
        let local = DummyEntity(value: "local", updatedAt: Date(timeIntervalSince1970: 200))
        let remote = DummyEntity(value: "remote", updatedAt: Date(timeIntervalSince1970: 100))

        let resolved = MetadataConflictResolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolved.value, "local")
    }

    func testRemoteWinsWhenTimestampsAreEqual() {
        let local = DummyEntity(value: "local", updatedAt: Date(timeIntervalSince1970: 300))
        let remote = DummyEntity(value: "remote", updatedAt: Date(timeIntervalSince1970: 300))

        let resolved = MetadataConflictResolver.resolve(local: local, remote: remote)

        XCTAssertEqual(resolved.value, "remote")
    }
}

private struct DummyEntity: UpdatedAtVersioned {
    let value: String
    let updatedAt: Date
}
