import XCTest

final class MistralAPIKeyStoreTests: XCTestCase {
    func testWriteReadDeleteAPIKeyLifecycle() throws {
        let serviceName = "info.kupczynski.foodbuddy.tests.\(UUID().uuidString)"
        let store = KeychainMistralAPIKeyStore(service: serviceName, account: "test-account")

        try store.setAPIKey("abc123")
        XCTAssertEqual(try store.apiKey(), "abc123")

        try store.setAPIKey(nil)
        XCTAssertNil(try store.apiKey())
    }
}
