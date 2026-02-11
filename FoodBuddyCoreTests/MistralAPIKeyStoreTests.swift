import Security
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

    func testCorruptNonUTF8KeyValueIsHealedAndTreatedAsMissing() throws {
        let serviceName = "info.kupczynski.foodbuddy.tests.\(UUID().uuidString)"
        let account = "test-account"
        let store = KeychainMistralAPIKeyStore(service: serviceName, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data([0xFF, 0xD8, 0xFF])
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        XCTAssertTrue(addStatus == errSecSuccess || addStatus == errSecDuplicateItem)

        XCTAssertNil(try store.apiKey())
        XCTAssertNil(try store.apiKey())
    }
}
