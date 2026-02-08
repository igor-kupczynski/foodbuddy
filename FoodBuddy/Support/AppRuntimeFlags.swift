import Foundation

enum AppRuntimeFlags {
    private static let arguments = Set(ProcessInfo.processInfo.arguments)
    private static let environment = ProcessInfo.processInfo.environment

    static var useMockCameraCapture: Bool {
        arguments.contains("--use-mock-camera-capture")
            || environment["FOODBUDDY_USE_MOCK_CAMERA_CAPTURE"] == "1"
    }
}
