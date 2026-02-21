import AsyncHTTPClient
import FoodBuddyAIShared
import Foundation
import NIOCore
import NIOFoundationCompat

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")
        static let endpointString = "https://api.mistral.ai/v1/chat/completions"
        static let model = "mistral-large-latest"
        static let timeoutSeconds: TimeInterval = 240
        static let responseMaxTokens = 400
        static let maxAttempts = 3
        static let retryBaseDelayMs: UInt64 = 500
        static let errorPreviewMaxChars = 2_000
        static let errorPreviewMaxLines = 8
    }

    /// Transport layer for HTTP requests.
    /// Production uses AsyncHTTPClient (HTTP/2 only, avoids Cloudflare h3 502s).
    /// Tests use URLSession with URLProtocolStub for mocking.
    enum Transport: @unchecked Sendable {
        case asyncHTTPClient
        case urlSession(URLSession)
    }

    private let apiKeyStore: any MistralAPIKeyStoring
    private let transport: Transport

    init(
        apiKeyStore: any MistralAPIKeyStoring,
        transport: Transport = .asyncHTTPClient
    ) {
        self.apiKeyStore = apiKeyStore
        self.transport = transport
    }

    /// Convenience init for tests that inject a mocked URLSession.
    init(
        apiKeyStore: any MistralAPIKeyStoring,
        urlSession: URLSession
    ) {
        self.apiKeyStore = apiKeyStore
        self.transport = .urlSession(urlSession)
    }

    func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult {
        let key = try apiKeyStore.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw FoodRecognitionServiceError.noAPIKey
        }

        let requestBody: Data
        do {
            requestBody = try FoodAnalysisRequestFactory.makeJSONData(
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

        switch transport {
        case .asyncHTTPClient:
            return try await analyzeViaAsyncHTTPClient(key: key, requestBody: requestBody)
        case .urlSession(let session):
            return try await analyzeViaURLSession(key: key, requestBody: requestBody, session: session)
        }
    }

    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }

    // MARK: - AsyncHTTPClient transport (production)

    private func analyzeViaAsyncHTTPClient(key: String, requestBody: Data) async throws -> FoodAnalysisResult {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)

        var request = HTTPClientRequest(url: Constants.endpointString)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "Bearer \(key)")
        request.headers.add(name: "Accept", value: "text/event-stream")
        request.body = .bytes(ByteBuffer(data: requestBody))

        defer { Task { try? await httpClient.shutdown() } }

        for attempt in 1...Constants.maxAttempts {
            do {
                let response = try await httpClient.execute(request, timeout: .seconds(Int64(Constants.timeoutSeconds)))
                let statusCode = Int(response.status.code)

                guard (200..<300).contains(statusCode) else {
                    let bodyPreview = try await collectBodyPreviewAHC(from: response)
                    let error = FoodRecognitionServiceError.httpError(
                        statusCode: statusCode,
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
                var lineBuffer = ByteBuffer()
                for try await chunk in response.body {
                    lineBuffer.writeImmutableBuffer(chunk)
                    while let line = lineBuffer.readLine() {
                        rawLines.append(line)
                        try streamAccumulator.consume(line: line)
                    }
                }

                return try parseStreamResult(accumulator: streamAccumulator, rawLines: rawLines)
            } catch let error as FoodRecognitionServiceError {
                if shouldRetry(error: error, attempt: attempt) {
                    await sleepBeforeRetry(attempt: attempt)
                    continue
                }
                throw error
            } catch {
                let errorDesc = String(describing: error)
                let isRetryable = errorDesc.contains("deadlineExceeded")
                    || errorDesc.contains("readTimeout")
                    || errorDesc.contains("connectTimeout")
                    || errorDesc.contains("remoteConnectionClosed")

                if isRetryable, attempt < Constants.maxAttempts {
                    await sleepBeforeRetry(attempt: attempt)
                    continue
                }
                throw FoodRecognitionServiceError.networkError
            }
        }

        throw FoodRecognitionServiceError.networkError
    }

    private func collectBodyPreviewAHC(from response: HTTPClientResponse) async throws -> String? {
        var body = ""
        var linesRead = 0
        var lineBuffer = ByteBuffer()

        for try await chunk in response.body {
            lineBuffer.writeImmutableBuffer(chunk)
            while let line = lineBuffer.readLine() {
                if !line.isEmpty {
                    body += line + "\n"
                }
                linesRead += 1
                if body.count >= Constants.errorPreviewMaxChars || linesRead >= Constants.errorPreviewMaxLines {
                    return String(body.prefix(Constants.errorPreviewMaxChars))
                }
            }
            if body.count >= Constants.errorPreviewMaxChars || linesRead >= Constants.errorPreviewMaxLines {
                break
            }
        }

        return body.isEmpty ? nil : String(body.prefix(Constants.errorPreviewMaxChars))
    }

    // MARK: - URLSession transport (tests)

    private func analyzeViaURLSession(key: String, requestBody: Data, session: URLSession) async throws -> FoodAnalysisResult {
        guard let endpoint = Constants.endpoint else {
            throw FoodRecognitionServiceError.decodingError
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Constants.timeoutSeconds
        request.httpBody = requestBody

        for attempt in 1...Constants.maxAttempts {
            do {
                let (bytes, response) = try await session.bytes(for: request)
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

                return try parseStreamResult(accumulator: streamAccumulator, rawLines: rawLines)
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

    // MARK: - Shared helpers

    private func parseStreamResult(accumulator: consuming MistralStreamAccumulator, rawLines: [String]) throws -> FoodAnalysisResult {
        do {
            var accumulator = accumulator
            let streamResult = try accumulator.finish()
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
}

// MARK: - ByteBuffer line reading

extension ByteBuffer {
    /// Read a complete line (up to and including `\n`) from the buffer.
    /// Returns the line content without the trailing `\r\n` or `\n`, or nil if no complete line is available.
    mutating func readLine() -> String? {
        guard let newlineIndex = self.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let lineLength = newlineIndex - self.readableBytesView.startIndex + 1
        guard let slice = self.readSlice(length: lineLength) else {
            return nil
        }
        var line = String(buffer: slice)
        while line.last == "\n" || line.last == "\r" {
            line.removeLast()
        }
        return line
    }
}
