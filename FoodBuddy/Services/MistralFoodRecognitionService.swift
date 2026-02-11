import Foundation

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")
        static let model = "mistral-large-3-25-12"
        static let systemPrompt = """
        You are a food-logging assistant. The user sends photos from a single
        meal, possibly with notes for context.

        - Describe all food and drink items visible across the photos
        - If a photo shows a nutrition label or restaurant menu, extract the
          relevant items and nutritional info instead of describing the image
        - Incorporate the user's notes - they may correct, clarify, or add
          context the photos don't show
        - Be concise and specific (e.g. "grilled chicken breast" not just "meat")
        """
    }

    private let apiKeyStore: any MistralAPIKeyStoring
    private let urlSession: URLSession

    init(
        apiKeyStore: any MistralAPIKeyStoring,
        urlSession: URLSession = .shared
    ) {
        self.apiKeyStore = apiKeyStore
        self.urlSession = urlSession
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        guard let endpoint = Constants.endpoint else {
            throw FoodRecognitionServiceError.decodingError
        }
        guard !images.isEmpty else {
            throw FoodRecognitionServiceError.decodingError
        }

        let key = try apiKeyStore.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw FoodRecognitionServiceError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            MistralRequest(
                model: Constants.model,
                messages: [
                    Message(role: "system", content: .text(Constants.systemPrompt)),
                    Message(role: "user", content: .blocks(makeUserContent(images: images, notes: notes)))
                ],
                responseFormat: .strictDescriptionSchema
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw FoodRecognitionServiceError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodRecognitionServiceError.networkError
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(2000), encoding: .utf8)
            throw FoodRecognitionServiceError.httpError(statusCode: httpResponse.statusCode, responseBody: body)
        }

        let payload: MistralResponse
        do {
            payload = try JSONDecoder().decode(MistralResponse.self, from: data)
        } catch {
            throw FoodRecognitionServiceError.decodingError
        }

        guard let content = payload.choices.first?.message.content else {
            throw FoodRecognitionServiceError.decodingError
        }
        guard let contentData = content.data(using: .utf8) else {
            throw FoodRecognitionServiceError.decodingError
        }

        let descriptionPayload: DescriptionPayload
        do {
            descriptionPayload = try JSONDecoder().decode(DescriptionPayload.self, from: contentData)
        } catch {
            throw FoodRecognitionServiceError.decodingError
        }

        let description = descriptionPayload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            throw FoodRecognitionServiceError.decodingError
        }

        return description
    }

    private func makeUserContent(images: [Data], notes: String?) -> [ContentBlock] {
        var blocks = images.map { image in
            ContentBlock.imageURL("data:image/jpeg;base64,\(image.base64EncodedString())")
        }

        let normalizedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedNotes, !normalizedNotes.isEmpty {
            blocks.append(.text("Additional context: \(normalizedNotes)"))
        }

        return blocks
    }
}

private struct MistralRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
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

    static let strictDescriptionSchema = ResponseFormat(
        type: "json_schema",
        jsonSchema: JSONSchema(
            name: "food_description",
            strict: true,
            schema: DescriptionSchema(
                type: "object",
                properties: DescriptionProperties(
                    description: DescriptionProperty(
                        type: "string",
                        description: "1-3 sentence description of the food and drink items in the meal"
                    )
                ),
                required: ["description"],
                additionalProperties: false
            )
        )
    )
}

private struct JSONSchema: Encodable {
    let name: String
    let strict: Bool
    let schema: DescriptionSchema
}

private struct DescriptionSchema: Encodable {
    let type: String
    let properties: DescriptionProperties
    let required: [String]
    let additionalProperties: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties = "additionalProperties"
    }
}

private struct DescriptionProperties: Encodable {
    let description: DescriptionProperty
}

private struct DescriptionProperty: Encodable {
    let type: String
    let description: String
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

private struct DescriptionPayload: Decodable {
    let description: String
}
