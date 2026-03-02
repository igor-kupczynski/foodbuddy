import Foundation

struct MistralAISettings: Sendable, Equatable {
    static let defaultImageLongEdge = 1024
    static let defaultImageQuality = 75
    static let minImageLongEdge = 512
    static let maxImageLongEdge = 1600
    static let imageLongEdgeStep = 128
    static let minImageQuality = 25
    static let maxImageQuality = 100
    static let imageQualityStep = 5

    var imageLongEdge: Int
    var imageQuality: Int

    init(
        imageLongEdge: Int = MistralAISettings.defaultImageLongEdge,
        imageQuality: Int = MistralAISettings.defaultImageQuality
    ) {
        self.imageLongEdge = Self.clampLongEdge(imageLongEdge)
        self.imageQuality = Self.clampQuality(imageQuality)
    }

    var compressionQuality: CGFloat {
        CGFloat(imageQuality) / 100
    }

    static func clampLongEdge(_ value: Int) -> Int {
        let clamped = min(max(value, minImageLongEdge), maxImageLongEdge)
        let stepOffset = clamped - minImageLongEdge
        let roundedStep = Int((Double(stepOffset) / Double(imageLongEdgeStep)).rounded())
        return minImageLongEdge + (roundedStep * imageLongEdgeStep)
    }

    static func clampQuality(_ value: Int) -> Int {
        let clamped = min(max(value, minImageQuality), maxImageQuality)
        let stepOffset = clamped - minImageQuality
        let roundedStep = Int((Double(stepOffset) / Double(imageQualityStep)).rounded())
        return minImageQuality + (roundedStep * imageQualityStep)
    }
}

protocol MistralAISettingsStoring: Sendable {
    func settings() -> MistralAISettings
    func setSettings(_ settings: MistralAISettings)
}

struct UserDefaultsMistralAISettingsStore: MistralAISettingsStoring, @unchecked Sendable {
    private enum Keys {
        static let imageLongEdge = "mistral_ai_image_long_edge"
        static let imageQuality = "mistral_ai_image_quality"
    }

    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func settings() -> MistralAISettings {
        let storedLongEdge = userDefaults.object(forKey: Keys.imageLongEdge) as? Int
            ?? MistralAISettings.defaultImageLongEdge
        let storedQuality = userDefaults.object(forKey: Keys.imageQuality) as? Int
            ?? MistralAISettings.defaultImageQuality
        return MistralAISettings(
            imageLongEdge: storedLongEdge,
            imageQuality: storedQuality
        )
    }

    func setSettings(_ settings: MistralAISettings) {
        let normalized = MistralAISettings(
            imageLongEdge: settings.imageLongEdge,
            imageQuality: settings.imageQuality
        )
        userDefaults.set(normalized.imageLongEdge, forKey: Keys.imageLongEdge)
        userDefaults.set(normalized.imageQuality, forKey: Keys.imageQuality)
    }
}
