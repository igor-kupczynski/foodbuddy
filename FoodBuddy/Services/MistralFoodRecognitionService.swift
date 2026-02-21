import FoodBuddyAIShared
import Foundation

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")
        static let model = "mistral-large-latest"
        static let timeoutSeconds: TimeInterval = 240
        static let responseMaxTokens = 400
        static let maxAttempts = 3
        static let retryBaseDelayMs: UInt64 = 500
        static let errorPreviewMaxChars = 2_000
        static let errorPreviewMaxLines = 8
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Constants.timeoutSeconds

        do {
            request.httpBody = try FoodAnalysisRequestFactory.makeJSONData(
                model: Constants.model,
                images: images,
                notes: notes,
                categoryIdentifiers: FoodAnalysisCategories.all,
                stream: true,
                maxTokens: Constants.responseMaxTokens
            )
        } catch {
            throw FoodRecognitionServiceError.decodingError
        }

        for attempt in 1...Constants.maxAttempts {
            do {
                let (bytes, response) = try await urlSession.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FoodRecognitionServiceError.networkError
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let bodyPreview = await collectBodyPreview(from: bytes)
                    let error = FoodRecognitionServiceError.httpError(
                        statusCode: httpResponse.statusCode,
                        responseBody: bodyPreview
                    )

                    if shouldRetry(error: error, attempt: attempt) {
                        await sleepBeforeRetry(attempt: attempt)
                        continue
                    }
                    throw error
                }

                var rawLines: [String] = []
                rawLines.reserveCapacity(128)

                var streamAccumulator = MistralStreamAccumulator()
                for try await line in bytes.lines {
                    rawLines.append(line)
                    try streamAccumulator.consume(line: line)
                }

                do {
                    let streamResult = try streamAccumulator.finish()
                    let parseResult = try FoodAnalysisResponseParser.parseAssistantContent(streamResult.assistantContent)
                    return FoodAnalysisResult(
                        description: parseResult.payload.description,
                        foodItems: normalizeFoodItems(parseResult.payload.foodItems)
                    )
                } catch {
                    let fallbackBody = rawLines.joined(separator: "\n")
                    if let fallbackData = fallbackBody.data(using: .utf8),
                       let fallbackParse = try? FoodAnalysisResponseParser.parseResponseData(fallbackData) {
                        return FoodAnalysisResult(
                            description: fallbackParse.payload.description,
                            foodItems: normalizeFoodItems(fallbackParse.payload.foodItems)
                        )
                    }

                    throw FoodRecognitionServiceError.decodingError
                }
            } catch let error as FoodRecognitionServiceError {
                if shouldRetry(error: error, attempt: attempt) {
                    await sleepBeforeRetry(attempt: attempt)
                    continue
                }
                throw error
            } catch let urlError as URLError {
                if shouldRetry(urlError: urlError, attempt: attempt) {
                    await sleepBeforeRetry(attempt: attempt)
                    continue
                }
                throw FoodRecognitionServiceError.networkError
            } catch {
                throw FoodRecognitionServiceError.networkError
            }
        }

        throw FoodRecognitionServiceError.networkError
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

    private func shouldRetry(error: FoodRecognitionServiceError, attempt: Int) -> Bool {
        guard attempt < Constants.maxAttempts else {
            return false
        }

        switch error {
        case .httpError(let statusCode, _):
            return [408, 429, 500, 502, 503, 504].contains(statusCode)
        default:
            return false
        }
    }

    private func shouldRetry(urlError: URLError, attempt: Int) -> Bool {
        guard attempt < Constants.maxAttempts else {
            return false
        }

        if Task.isCancelled {
            return false
        }

        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .resourceUnavailable, .cancelled:
            return true
        default:
            return false
        }
    }

    private func sleepBeforeRetry(attempt: Int) async {
        let exponent = UInt64(max(0, attempt - 1))
        let delayMs = Constants.retryBaseDelayMs * (1 << exponent)
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
    }

    private func collectBodyPreview(from bytes: URLSession.AsyncBytes) async -> String? {
        var body = ""
        var linesRead = 0

        do {
            for try await line in bytes.lines {
                if !line.isEmpty {
                    body += line
                    body += "\n"
                }
                linesRead += 1
                if body.count >= Constants.errorPreviewMaxChars || linesRead >= Constants.errorPreviewMaxLines {
                    break
                }
            }
        } catch {
            if body.isEmpty {
                return nil
            }
        }

        guard !body.isEmpty else {
            return nil
        }
        return String(body.prefix(Constants.errorPreviewMaxChars))
    }
}
