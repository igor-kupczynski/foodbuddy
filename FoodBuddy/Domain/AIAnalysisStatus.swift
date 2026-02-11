import Foundation

enum AIAnalysisStatus: String, Codable, CaseIterable {
    case none
    case pending
    case analyzing
    case completed
    case failed
}
