import FoodBuddyAIShared
import Foundation

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")
        static let model = "mistral-large-latest"
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

        let key = try apiKeyStore.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw FoodRecognitionServiceError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try FoodAnalysisRequestFactory.makeJSONData(
                model: Constants.model,
                images: images,
                notes: notes,
                categoryIdentifiers: FoodAnalysisCategories.all
            )
        } catch {
            throw FoodRecognitionServiceError.decodingError
        }

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

        let parseResult: FoodAnalysisResponseParseResult
        do {
            parseResult = try FoodAnalysisResponseParser.parseResponseData(data)
        } catch {
            throw FoodRecognitionServiceError.decodingError
        }

        return FoodAnalysisResult(
            description: parseResult.payload.description,
            foodItems: normalizeFoodItems(parseResult.payload.foodItems)
        )
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }

    private func normalizeFoodItems(_ items: [FoodAnalysisItem]) -> [AIFoodItem] {
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
