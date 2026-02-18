import Foundation

enum AppRuntimeFlags {
    private static let arguments = Set(ProcessInfo.processInfo.arguments)
    private static let argumentsArray = ProcessInfo.processInfo.arguments
    private static let environment = ProcessInfo.processInfo.environment

    static var useMockCameraCapture: Bool {
        arguments.contains("--use-mock-camera-capture")
            || environment["FOODBUDDY_USE_MOCK_CAMERA_CAPTURE"] == "1"
    }

    static var useMockFoodRecognition: Bool {
        arguments.contains("--use-mock-food-recognition")
            || environment["FOODBUDDY_USE_MOCK_FOOD_RECOGNITION"] == "1"
    }

    static var localStoreSuffix: String? {
        if let value = environment["FOODBUDDY_LOCAL_STORE_SUFFIX"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return argumentValue(prefix: "--local-store-suffix=")
    }

    static var dqsFixture: String? {
        if let value = environment["FOODBUDDY_DQS_FIXTURE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return argumentValue(prefix: "--dqs-fixture=")
    }

    private static func argumentValue(prefix: String) -> String? {
        for argument in argumentsArray where argument.hasPrefix(prefix) {
            let value = String(argument.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
