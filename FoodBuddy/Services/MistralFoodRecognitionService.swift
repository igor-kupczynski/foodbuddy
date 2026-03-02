import AsyncHTTPClient
import FoodBuddyAIShared
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

// MARK: - Transport protocol

/// Abstracts HTTP POST with streaming response so the service has a single code path.
/// Production uses AsyncHTTPClientTransport; tests inject a mock.
protocol MistralHTTPTransport: Sendable {
    func streamingPOST(
        url: String,
        headers: [(name: String, value: String)],
        body: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> MistralStreamingResponse
}

struct MistralStreamingResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let bodyLines: AsyncThrowingStream<String, Error>
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
    ) async throws -> MistralStreamingResponse {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)

        var request = HTTPClientRequest(url: url)
        request.method = .POST
        for (name, value) in headers {
            request.headers.add(name: name, value: value)
        }
        request.body = .bytes(ByteBuffer(data: body))

        let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeoutSeconds)))
        let statusCode = Int(response.status.code)
        let responseHeaders = normalizeHeaders(response.headers)

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

        return MistralStreamingResponse(
            statusCode: statusCode,
            headers: responseHeaders,
            bodyLines: stream
        )
    }

    private func normalizeHeaders(_ headers: HTTPHeaders) -> [String: String] {
        var normalized: [String: String] = [:]

        for header in headers {
            let name = header.name.lowercased()
            if let existing = normalized[name] {
                normalized[name] = "\(existing), \(header.value)"
            } else {
                normalized[name] = header.value
            }
        }

        return normalized
    }
}

// MARK: - Service

struct MistralFoodRecognitionService: FoodRecognitionService, @unchecked Sendable {
    private enum Constants {
        static let endpointURL = "https://api.mistral.ai/v1/chat/completions"
        static let model = "mistral-large-latest"
        static let timeoutSeconds: TimeInterval = 240
        static let responseMaxTokens = 400
        static let maxAttempts = 4
        static let retryBaseDelayMs: UInt64 = 2_000
        static let retryMaxDelayMs: UInt64 = 30_000
        static let retryJitterMaxMs: UInt64 = 250
        static let errorPreviewMaxChars = 2_000
        static let errorPreviewMaxLines = 8
    }

    private let apiKeyStore: any MistralAPIKeyStoring
    private let aiSettingsStore: any MistralAISettingsStoring
    private let transport: any MistralHTTPTransport
    private let nowProvider: @Sendable () -> Date
    private let retryJitterMillisecondsProvider: @Sendable () -> UInt64
    private let sleepMilliseconds: @Sendable (UInt64) async -> Void

    init(
        apiKeyStore: any MistralAPIKeyStoring,
        aiSettingsStore: any MistralAISettingsStoring = UserDefaultsMistralAISettingsStore(),
        transport: any MistralHTTPTransport = AsyncHTTPClientTransport(),
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        retryJitterMillisecondsProvider: @escaping @Sendable () -> UInt64 = {
            UInt64.random(in: 0...250)
        },
        sleepMilliseconds: @escaping @Sendable (UInt64) async -> Void = { delayMs in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        }
    ) {
        self.apiKeyStore = apiKeyStore
        self.aiSettingsStore = aiSettingsStore
        self.transport = transport
        self.nowProvider = nowProvider
        self.retryJitterMillisecondsProvider = retryJitterMillisecondsProvider
        self.sleepMilliseconds = sleepMilliseconds
    }

    func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult {
        let key = try apiKeyStore.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw FoodRecognitionServiceError.noAPIKey
        }
        let aiSettings = aiSettingsStore.settings()
        let aiPreprocessor = AIAnalysisImagePreprocessor(
            maxLongEdge: CGFloat(aiSettings.imageLongEdge),
            compressionQuality: aiSettings.compressionQuality
        )
        let processedImages = images.map(aiPreprocessor.preprocessForAI)
        let requestImages = processedImages.map(\.jpegData)
        let requestImageBytes = requestImages.map(\.count)

        let requestBody: Data
        do {
            requestBody = try FoodAnalysisRequestFactory.makeJSONData(
                model: Constants.model,
                images: requestImages,
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
        let requestBodyBytes = requestBody.count
        var appliedRetryDelayMs: [UInt64] = []

        for attempt in 1...Constants.maxAttempts {
            do {
                let response = try await transport.streamingPOST(
                    url: Constants.endpointURL,
                    headers: headers,
                    body: requestBody,
                    timeoutSeconds: Constants.timeoutSeconds
                )

                guard (200..<300).contains(response.statusCode) else {
                    let bodyPreview = await collectBodyPreview(from: response.bodyLines)
                    let responseTelemetry = HTTPResponseTelemetry(headers: response.headers)

                    if response.statusCode == 429 {
                        let retryAfterRawValue = response.headers["retry-after"]
                        let delayMs = retryDelayMilliseconds(
                            attempt: attempt,
                            retryAfterRawValue: retryAfterRawValue
                        )
                        let nextEligibleRetryAt = nowProvider()
                            .addingTimeInterval(TimeInterval(delayMs) / 1_000)

                        if attempt < Constants.maxAttempts {
                            appliedRetryDelayMs.append(delayMs)
                            await sleep(milliseconds: delayMs)
                            continue
                        }

                        throw FoodRecognitionServiceError.rateLimited(
                            FoodRecognitionRateLimitTelemetry(
                                statusCode: response.statusCode,
                                responseBody: bodyPreview,
                                responseTelemetry: responseTelemetry,
                                requestImageCount: requestImages.count,
                                requestImageBytes: requestImageBytes,
                                requestBodyBytes: requestBodyBytes,
                                model: Constants.model,
                                imageLongEdge: aiSettings.imageLongEdge,
                                imageQuality: aiSettings.imageQuality,
                                attemptCount: attempt,
                                maxAttempts: Constants.maxAttempts,
                                appliedRetryDelayMs: appliedRetryDelayMs,
                                retryAfterRawValue: retryAfterRawValue,
                                nextEligibleRetryAt: nextEligibleRetryAt
                            )
                        )
                    }

                    let error = FoodRecognitionServiceError.httpError(
                        statusCode: response.statusCode,
                        responseBody: bodyPreview,
                        responseTelemetry: responseTelemetry
                    )

                    if shouldRetry(statusCode: response.statusCode, attempt: attempt) {
                        let delayMs = retryDelayMilliseconds(attempt: attempt)
                        appliedRetryDelayMs.append(delayMs)
                        await sleep(milliseconds: delayMs)
                        continue
                    }
                    throw error
                }

                var rawLines: [String] = []
                rawLines.reserveCapacity(128)

                var streamAccumulator = MistralStreamAccumulator()
                for try await line in response.bodyLines {
                    rawLines.append(line)
                    try streamAccumulator.consume(line: line)
                }

                return try parseStreamResult(accumulator: streamAccumulator, rawLines: rawLines)
            } catch let error as FoodRecognitionServiceError {
                throw error
            } catch {
                let errorDesc = String(describing: error)
                let isRetryable = errorDesc.contains("deadlineExceeded")
                    || errorDesc.contains("readTimeout")
                    || errorDesc.contains("connectTimeout")
                    || errorDesc.contains("remoteConnectionClosed")

                if isRetryable, attempt < Constants.maxAttempts {
                    let delayMs = retryDelayMilliseconds(attempt: attempt)
                    appliedRetryDelayMs.append(delayMs)
                    await sleep(milliseconds: delayMs)
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

    private func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        guard attempt < Constants.maxAttempts else {
            return false
        }

        return [408, 500, 502, 503, 504].contains(statusCode)
    }

    private func retryDelayMilliseconds(
        attempt: Int,
        retryAfterRawValue: String? = nil
    ) -> UInt64 {
        if let retryAfterRawValue,
           let retryAfterMilliseconds = parseRetryAfterMilliseconds(rawValue: retryAfterRawValue) {
            return clampRetryDelay(milliseconds: retryAfterMilliseconds)
        }

        let exponent = UInt64(max(0, attempt - 1))
        let baseDelayMs = Constants.retryBaseDelayMs * (1 << exponent)
        let jitterMs = retryJitterMillisecondsProvider()
        return clampRetryDelay(milliseconds: baseDelayMs.saturatingAdd(jitterMs))
    }

    private func clampRetryDelay(milliseconds: UInt64) -> UInt64 {
        min(milliseconds, Constants.retryMaxDelayMs)
    }

    private func parseRetryAfterMilliseconds(rawValue: String) -> UInt64? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return UInt64((seconds * 1_000).rounded())
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        guard let retryDate = formatter.date(from: trimmed) else {
            return nil
        }

        let interval = retryDate.timeIntervalSince(nowProvider())
        guard interval > 0 else {
            return 0
        }

        return UInt64((interval * 1_000).rounded())
    }

    private func sleep(milliseconds delayMs: UInt64) async {
        await sleepMilliseconds(delayMs)
    }
}

private extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : value
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
