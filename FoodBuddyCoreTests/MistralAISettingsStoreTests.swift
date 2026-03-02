import XCTest

final class MistralAISettingsStoreTests: XCTestCase {
    func testSettingsStoreDefaultsWhenUnset() {
        let defaults = UserDefaults(suiteName: "MistralAISettingsStoreTests.defaults.\(UUID().uuidString)")!
        let store = UserDefaultsMistralAISettingsStore(userDefaults: defaults)

        let settings = store.settings()
        XCTAssertEqual(settings.imageLongEdge, 1024)
        XCTAssertEqual(settings.imageQuality, 75)
    }

    func testSettingsStorePersistsAndNormalizesValues() {
        let defaults = UserDefaults(suiteName: "MistralAISettingsStoreTests.persist.\(UUID().uuidString)")!
        let store = UserDefaultsMistralAISettingsStore(userDefaults: defaults)

        store.setSettings(MistralAISettings(imageLongEdge: 1111, imageQuality: 77))
        let settings = store.settings()

        XCTAssertEqual(settings.imageLongEdge, 1152)
        XCTAssertEqual(settings.imageQuality, 75)
    }
}
