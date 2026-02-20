import Foundation

public struct FoodAnalysisResponseParseResult: Equatable, Sendable {
    public let payload: FoodAnalysisPayload
    public let rawContent: String

    public init(payload: FoodAnalysisPayload, rawContent: String) {
        self.payload = payload
        self.rawContent = rawContent
    }
}

public enum FoodAnalysisResponseParser {
    public static func parseResponseData(_ data: Data) throws -> FoodAnalysisResponseParseResult {
        let response: MistralResponse
        do {
            response = try JSONDecoder().decode(MistralResponse.self, from: data)
        } catch {
            throw FoodBuddyAISharedError.decodingError
        }

        guard let content = response.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw FoodBuddyAISharedError.decodingError
        }

        let payload: FoodAnalysisPayload
        do {
            payload = try JSONDecoder().decode(FoodAnalysisPayload.self, from: contentData)
        } catch {
            throw FoodBuddyAISharedError.decodingError
        }

        let description = payload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            throw FoodBuddyAISharedError.decodingError
        }

        return FoodAnalysisResponseParseResult(
            payload: FoodAnalysisPayload(description: description, foodItems: payload.foodItems),
            rawContent: content
        )
    }
}

private struct MistralResponse: Decodable {
    let choices: [Choice]
}

private struct Choice: Decodable {
    let message: ChoiceMessage
}

private struct ChoiceMessage: Decodable {
    let content: String?
}
