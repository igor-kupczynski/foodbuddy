import Foundation

enum CaptureSource: String, CaseIterable, Identifiable {
    case camera
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera:
            return "Take Photo"
        case .library:
            return "Choose from Library"
        }
    }
}
