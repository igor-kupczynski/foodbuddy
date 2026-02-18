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

struct FoodAnalysisResult: Sendable, Equatable {
    let description: String
    let foodItems: [AIFoodItem]
}

struct AIFoodItem: Sendable, Codable, Equatable {
    let name: String
    let categories: [String]
    let servings: Double
}

protocol FoodRecognitionService: Sendable {
    func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult
    func describe(images: [Data], notes: String?) async throws -> String
}

extension FoodRecognitionService {
    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }
}

struct MockFoodRecognitionService: FoodRecognitionService {
    enum Behavior {
        case success(FoodAnalysisResult)
        case failure(FoodRecognitionServiceError)
    }

    let behavior: Behavior

    init(
        behavior: Behavior = .success(
            FoodAnalysisResult(
                description: "Meal description unavailable in mock mode.",
                foodItems: []
            )
        )
    ) {
        self.behavior = behavior
    }

    func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult {
        switch behavior {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }
}
