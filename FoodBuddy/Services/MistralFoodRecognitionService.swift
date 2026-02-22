import AsyncHTTPClient
import FoodBuddyAIShared
import Foundation
import NIOCore
import NIOFoundationCompat

// MARK: - Transport protocol

/// Abstracts HTTP POST with streaming response so the service has a single code path.
/// Production uses AsyncHTTPClientTransport; tests inject a mock.
protocol MistralHTTPTransport: Sendable {
    func streamingPOST(
        url: String,
        headers: [(name: String, value: String)],
        body: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> (statusCode: Int, bodyLines: AsyncThrowingStream<String, Error>)
}

// MARK: - Production transport (AsyncHTTPClient, HTTP/2 only)

/// Uses AsyncHTTPClient (SwiftNIO) which only advertises h2/http1.1 via ALPN,
/// avoiding Cloudflare HTTP/3 (QUIC) 502 failures that URLSession causes.
struct AsyncHTTPClientTransport: MistralHTTPTransport {
    func streamingPOST(
        url: String,
        headers: [(name: String, value: String)],
        body: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> (statusCode: Int, bodyLines: AsyncThrowingStream<String, Error>) {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)

        var request = HTTPClientRequest(url: url)
        request.method = .POST
        for (name, value) in headers {
            request.headers.add(name: name, value: value)
        }
        request.body = .bytes(ByteBuffer(data: body))

        let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeoutSeconds)))
        let statusCode = Int(response.status.code)

        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                defer {
                    continuation.finish()
                    Task { try? await httpClient.shutdown() }
                }
                do {
                    var lineBuffer = ByteBuffer()
                    for try await chunk in response.body {
                        lineBuffer.writeImmutableBuffer(chunk)
                        while let line = lineBuffer.readLine() {
                            continuation.yield(line)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return (statusCode, stream)
    }
}

// MARK: - Service

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpointURL = "https://api.mistral.ai/v1/chat/completions"
        static let model = "mistral-large-latest"
        static let timeoutSeconds: TimeInterval = 240
        static let responseMaxTokens = 400
        static let maxAttempts = 3
        static let retryBaseDelayMs: UInt64 = 500
        static let errorPreviewMaxChars = 2_000
        static let errorPreviewMaxLines = 8
    }

    private let apiKeyStore: any MistralAPIKeyStoring
    private let transport: any MistralHTTPTransport

    init(
        apiKeyStore: any MistralAPIKeyStoring,
        transport: any MistralHTTPTransport = AsyncHTTPClientTransport()
    ) {
        self.apiKeyStore = apiKeyStore
        self.transport = transport
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

        let headers: [(name: String, value: String)] = [
            ("Content-Type", "application/json"),
            ("Authorization", "Bearer \(key)"),
            ("Accept", "text/event-stream"),
        ]

        for attempt in 1...Constants.maxAttempts {
            do {
                let (statusCode, bodyLines) = try await transport.streamingPOST(
                    url: Constants.endpointURL,
                    headers: headers,
                    body: requestBody,
                    timeoutSeconds: Constants.timeoutSeconds
                )

                guard (200..<300).contains(statusCode) else {
                    let bodyPreview = await collectBodyPreview(from: bodyLines)
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
                for try await line in bodyLines {
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

    func describe(images: [Data], notes: String?) async throws -> String {
        try await analyze(images: images, notes: notes).description
    }

    // MARK: - Private helpers

    private func collectBodyPreview(from lines: AsyncThrowingStream<String, Error>) async -> String? {
        var body = ""
        var linesRead = 0

        do {
            for try await line in lines {
                if !line.isEmpty {
                    body += line + "\n"
                }
                linesRead += 1
                if body.count >= Constants.errorPreviewMaxChars || linesRead >= Constants.errorPreviewMaxLines {
                    break
                }
            }
        } catch {
            if body.isEmpty { return nil }
        }

        return body.isEmpty ? nil : String(body.prefix(Constants.errorPreviewMaxChars))
    }

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

            guard DQSCategory(apiIdentifier: item.category) != nil else {
                continue
            }

            normalized.append(
                AIFoodItem(
                    name: name,
                    category: item.category,
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
