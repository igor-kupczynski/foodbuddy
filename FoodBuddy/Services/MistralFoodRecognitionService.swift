import Foundation

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")
        static let model = "mistral-large-latest"
        static let systemPrompt = """
        You are a food-logging assistant. The user sends photos from a single meal, possibly with notes for context.

        Return two things:
        1. A 1-3 sentence description of the food and drink items visible
        2. A structured list of individual food items for diet quality scoring

        For descriptions:
        - If a photo shows a nutrition label or restaurant menu, extract the relevant items and nutritional info instead of describing the image
        - Incorporate the user's notes - they may correct, clarify, or add context the photos don't show
        - Be concise and specific (e.g. "grilled chicken breast" not just "meat")

        For food items, classify each into one or more Diet Quality Score (DQS) categories:

        HIGH-QUALITY categories:
        - fruits: Whole fresh/canned/frozen fruit, 100% fruit juice
        - vegetables: Fresh/cooked/canned/frozen vegetables, pureed vegetables in soups and sauces
        - lean_meats_and_fish: All fish, meats <=10% fat, eggs
        - legumes_and_plant_proteins: Beans, lentils, chickpeas, tofu, tempeh, edamame, high-protein plant foods (>5g protein/serving)
        - nuts_and_seeds: All nuts and seeds, natural nut/seed butters (no added sugar)
        - whole_grains: Brown rice, 100% whole-grain breads/pastas/cereals
        - dairy: All milk-based products (milk, cheese, yogurt, butter) - cow, goat, sheep

        LOW-QUALITY categories:
        - refined_grains: White rice, processed flours, breads/pastas/cereals not 100% whole grain
        - sweets: Foods/drinks with large amounts of refined sugar, diet sodas. If any form of sugar is the 1st or 2nd ingredient, classify as sweets. Exception: dark chocolate >=80% cacao in small amounts does NOT count
        - fried_foods: All deep-fried foods, all snack chips (even baked/veggie-based). Does NOT include pan-fried foods (stir-fry, fried eggs)
        - fatty_proteins: Meats >10% fat, farm-raised fish, processed meats (bacon, sausages, cold cuts)

        Serving size guidance:
        - Fruit: 1 medium piece, a big handful of berries, a glass of juice
        - Vegetables: a fist-sized portion, 1/2 cup sauce, a bowl of soup/salad
        - Meats/fish: a palm-sized portion
        - Grains: a fist-sized portion of rice, a bowl of cereal/pasta, 2 slices bread
        - Dairy: a glass of milk, 2 slices cheese, 1 yogurt tub
        - Nuts: a palmful, 1 heaping tbsp nut butter

        Special rules:
        - DOUBLE-COUNTING: A food can belong to TWO categories. Sweetened yogurt = dairy + sweets. Honey Nut Cheerios = refined_grains + sweets. Ice cream = dairy + sweets. If sugar is a top-2 ingredient, add sweets alongside the primary category.
        - CONDIMENTS used sparingly: don't include. Used generously (e.g. mayo on fries, BBQ sauce smothered on ribs): include as a separate sweets or fatty_proteins item.
        - ALCOHOL: moderate (1-2 drinks) don't include. Beyond that, classify each extra drink as sweets.
        - COFFEE/TEA: unsweetened don't include. Lattes or heavily sweetened drinks: classify as sweets (and dairy if significant milk).
        - COMBINATION FOODS: break into components. Pizza = refined_grains (crust) + vegetables (sauce) + dairy (cheese) + fatty_proteins (pepperoni).
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

    func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult {
        guard let endpoint = Constants.endpoint else {
            throw FoodRecognitionServiceError.decodingError
        }
        let normalizedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !images.isEmpty || !(normalizedNotes?.isEmpty ?? true) else {
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
                    Message(role: "user", content: .blocks(makeUserContent(images: images, notes: normalizedNotes)))
                ],
                responseFormat: .strictFoodAnalysisSchema
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

        guard let content = payload.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw FoodRecognitionServiceError.decodingError
        }

        let analysisPayload: FoodAnalysisPayload
        do {
            analysisPayload = try JSONDecoder().decode(FoodAnalysisPayload.self, from: contentData)
        } catch {
            throw FoodRecognitionServiceError.decodingError
        }

        let description = analysisPayload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            throw FoodRecognitionServiceError.decodingError
        }

        return FoodAnalysisResult(
            description: description,
            foodItems: normalizeFoodItems(analysisPayload.foodItems)
        )
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }

    private func makeUserContent(images: [Data], notes: String?) -> [ContentBlock] {
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

    private func normalizeFoodItems(_ items: [AIFoodItem]) -> [AIFoodItem] {
        var normalized: [AIFoodItem] = []
        normalized.reserveCapacity(items.count)

        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.servings > 0 else {
                continue
            }

            var uniqueCategories = Set<String>()
            var categories: [String] = []
            for rawCategory in item.categories {
                guard let category = DQSCategory(apiIdentifier: rawCategory) else {
                    continue
                }
                if uniqueCategories.insert(category.apiIdentifier).inserted {
                    categories.append(category.apiIdentifier)
                }
            }

            guard !categories.isEmpty else {
                continue
            }

            normalized.append(
                AIFoodItem(
                    name: name,
                    categories: categories,
                    servings: item.servings
                )
            )
        }

        return normalized
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

    static let strictFoodAnalysisSchema = ResponseFormat(
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
                                categories: CategoriesProperty(
                                    type: "array",
                                    description: "DQS categories (usually 1, sometimes 2 for double-counted foods)",
                                    items: CategoriesItemProperty(
                                        type: "string",
                                        enumValues: DQSCategory.allCases.map(\.apiIdentifier)
                                    )
                                ),
                                servings: DescriptionProperty(
                                    type: "number",
                                    description: "Estimated number of standard servings (0.5, 1, 1.5, 2, etc.)"
                                )
                            ),
                            required: ["name", "categories", "servings"],
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
    let categories: CategoriesProperty
    let servings: DescriptionProperty
}

private struct CategoriesProperty: Encodable {
    let type: String
    let description: String
    let items: CategoriesItemProperty
}

private struct CategoriesItemProperty: Encodable {
    let type: String
    let enumValues: [String]

    enum CodingKeys: String, CodingKey {
        case type
        case enumValues = "enum"
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

private struct FoodAnalysisPayload: Decodable {
    let description: String
    let foodItems: [AIFoodItem]

    enum CodingKeys: String, CodingKey {
        case description
        case foodItems = "food_items"
    }
}
