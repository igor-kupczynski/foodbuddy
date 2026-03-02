import Foundation

struct HTTPResponseTelemetry: Sendable, Equatable {
    let headers: [String: String]

    var interestingHeaders: [String: String] {
        let interestingNames = [
            "retry-after",
            "x-ratelimit-limit",
            "x-ratelimit-remaining",
            "x-ratelimit-reset",
            "ratelimit-limit",
            "ratelimit-remaining",
            "ratelimit-reset",
            "cf-ray",
        ]

        return headers
            .filter { interestingNames.contains($0.key.lowercased()) }
            .sorted(by: { $0.key < $1.key })
            .reduce(into: [:]) { partialResult, item in
                partialResult[item.key] = item.value
            }
    }
}

struct FoodRecognitionRateLimitTelemetry: Sendable, Equatable {
    let statusCode: Int
    let responseBody: String?
    let responseTelemetry: HTTPResponseTelemetry
    let requestImageCount: Int
    let requestImageBytes: [Int]
    let requestBodyBytes: Int
    let model: String
    let imageLongEdge: Int
    let imageQuality: Int
    let attemptCount: Int
    let maxAttempts: Int
    let appliedRetryDelayMs: [UInt64]
    let retryAfterRawValue: String?
    let nextEligibleRetryAt: Date
}

enum FoodRecognitionServiceError: Swift.Error, Equatable, LocalizedError {
    case noAPIKey
    case networkError
    case httpError(statusCode: Int, responseBody: String?, responseTelemetry: HTTPResponseTelemetry?)
    case rateLimited(FoodRecognitionRateLimitTelemetry)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .networkError:
            return "Network error — check your connection"
        case .httpError(let statusCode, _, _):
            return "Server error (HTTP \(statusCode))"
        case .rateLimited:
            return "Server rate limit reached (HTTP 429)"
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
    let category: String
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
