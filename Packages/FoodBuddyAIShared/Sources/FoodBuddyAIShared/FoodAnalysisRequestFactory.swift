import Foundation

public enum FoodAnalysisRequestFactory {
    public static func makeJSONData(
        model: String,
        images: [Data],
        notes: String?,
        categoryIdentifiers: [String],
        stream: Bool = false,
        maxTokens: Int? = nil
    ) throws -> Data {
        let normalizedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !images.isEmpty || !(normalizedNotes?.isEmpty ?? true) else {
            throw FoodBuddyAISharedError.emptyInput
        }

        let request = MistralRequest(
            model: model,
            messages: [
                Message(role: "system", content: .text(FoodAnalysisPrompt.system)),
                Message(role: "user", content: .blocks(makeUserContent(images: images, notes: normalizedNotes)))
            ],
            responseFormat: .strictFoodAnalysisSchema(categoryIdentifiers: categoryIdentifiers),
            stream: stream,
            maxTokens: maxTokens
        )

        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw FoodBuddyAISharedError.encodingError
        }
    }

    private static func makeUserContent(images: [Data], notes: String?) -> [ContentBlock] {
        var blocks = images.map { image in
            ContentBlock.imageURL("data:image/jpeg;base64,\(image.base64EncodedString())")
        }

        if let notes, !notes.isEmpty {
            if images.isEmpty {
                blocks.append(.text("Meal note: \(notes)"))
            } else {
                blocks.append(.text("Additional context: \(notes)"))
            }
        }

        return blocks
    }
}

private struct MistralRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    let stream: Bool?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case stream
        case maxTokens = "max_tokens"
    }
}

private struct Message: Encodable {
    let role: String
    let content: MessageContent
}

private enum MessageContent: Encodable {
    case text(String)
    case blocks([ContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

private struct ContentBlock: Encodable {
    let type: String
    let imageURL: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case imageURL = "image_url"
        case text
    }

    static func imageURL(_ dataURI: String) -> ContentBlock {
        ContentBlock(type: "image_url", imageURL: dataURI, text: nil)
    }

    static func text(_ value: String) -> ContentBlock {
        ContentBlock(type: "text", imageURL: nil, text: value)
    }
}

private struct ResponseFormat: Encodable {
    let type: String
    let jsonSchema: JSONSchema

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    static func strictFoodAnalysisSchema(categoryIdentifiers: [String]) -> ResponseFormat {
        ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchema(
                name: "food_analysis",
                strict: true,
                schema: FoodAnalysisSchema(
                    type: "object",
                    properties: FoodAnalysisProperties(
                        description: DescriptionProperty(
                            type: "string",
                            description: "1-3 sentence description of the food and drink items in the meal"
                        ),
                        foodItems: FoodItemsProperty(
                            type: "array",
                            description: "Individual food items identified, categorized for diet quality scoring",
                            items: FoodItemSchema(
                                type: "object",
                                properties: FoodItemProperties(
                                    name: DescriptionProperty(
                                        type: "string",
                                        description: "Specific name of the food item"
                                    ),
                                    category: CategoryProperty(
                                        type: "string",
                                        description: "Exactly one DQS category for this food item",
                                        enumValues: categoryIdentifiers
                                    ),
                                    servings: DescriptionProperty(
                                        type: "number",
                                        description: "Estimated number of standard servings (0.5, 1, 1.5, 2, etc.)"
                                    )
                                ),
                                required: ["name", "category", "servings"],
                                additionalProperties: false
                            )
                        )
                    ),
                    required: ["description", "food_items"],
                    additionalProperties: false
                )
            )
        )
    }
}

private struct JSONSchema: Encodable {
    let name: String
    let strict: Bool
    let schema: FoodAnalysisSchema
}

private struct FoodAnalysisSchema: Encodable {
    let type: String
    let properties: FoodAnalysisProperties
    let required: [String]
    let additionalProperties: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties = "additionalProperties"
    }
}

private struct FoodAnalysisProperties: Encodable {
    let description: DescriptionProperty
    let foodItems: FoodItemsProperty

    enum CodingKeys: String, CodingKey {
        case description
        case foodItems = "food_items"
    }
}

private struct DescriptionProperty: Encodable {
    let type: String
    let description: String
}

private struct FoodItemsProperty: Encodable {
    let type: String
    let description: String
    let items: FoodItemSchema
}

private struct FoodItemSchema: Encodable {
    let type: String
    let properties: FoodItemProperties
    let required: [String]
    let additionalProperties: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties = "additionalProperties"
    }
}

private struct FoodItemProperties: Encodable {
    let name: DescriptionProperty
    let category: CategoryProperty
    let servings: DescriptionProperty
}

private struct CategoryProperty: Encodable {
    let type: String
    let description: String
    let enumValues: [String]

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
}
