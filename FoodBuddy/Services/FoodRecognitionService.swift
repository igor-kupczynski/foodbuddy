import Foundation

enum FoodRecognitionServiceError: Swift.Error, Equatable {
    case noAPIKey
    case networkError
    case httpError(statusCode: Int)
    case decodingError
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
