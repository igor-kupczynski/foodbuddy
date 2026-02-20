import Foundation

public enum FoodBuddyAISharedError: Swift.Error, Equatable {
    case emptyInput
    case decodingError
    case encodingError
}

public struct FoodAnalysisPayload: Codable, Equatable, Sendable {
    public let description: String
    public let foodItems: [FoodAnalysisItem]

    enum CodingKeys: String, CodingKey {
        case description
        case foodItems = "food_items"
    }

    public init(description: String, foodItems: [FoodAnalysisItem]) {
        self.description = description
        self.foodItems = foodItems
    }
}

public struct FoodAnalysisItem: Codable, Equatable, Sendable {
    public let name: String
    public let categories: [String]
    public let servings: Double

    public init(name: String, categories: [String], servings: Double) {
        self.name = name
        self.categories = categories
        self.servings = servings
    }
}
