import Foundation

enum FoodRecognitionServiceError: Swift.Error, Equatable, LocalizedError {
    case noAPIKey
    case networkError
    case httpError(statusCode: Int, responseBody: String?)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .networkError:
            return "Network error — check your connection"
        case .httpError(let statusCode, _):
            return "Server error (HTTP \(statusCode))"
        case .decodingError:
            return "Unexpected response from AI service"
        }
    }
}

protocol FoodRecognitionService: Sendable {
    func describe(images: [Data], notes: String?) async throws -> String
}

struct MockFoodRecognitionService: FoodRecognitionService {
    enum Behavior {
        case success(String)
        case failure(FoodRecognitionServiceError)
    }

    let behavior: Behavior

    init(behavior: Behavior = .success("Meal description unavailable in mock mode.")) {
        self.behavior = behavior
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        switch behavior {
        case .success(let description):
            return description
        case .failure(let error):
            throw error
        }
    }
}
