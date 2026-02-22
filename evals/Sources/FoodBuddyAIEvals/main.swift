import AsyncHTTPClient
import FoodBuddyAIShared
import CoreGraphics
import Foundation
import ImageIO
import NIOCore
import NIOFoundationCompat
import UniformTypeIdentifiers

@main
struct FoodBuddyAIEvals {
    static func main() async {
        do {
            let config = try CLIConfig.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            if config.showHelp {
                print(CLIConfig.helpText)
                return
            }

            let evalRoot = try resolveEvalRoot(explicitPath: config.evalRootPath)
            let evalCase = try loadCase(id: config.caseID, evalRoot: evalRoot)
            let resolvedModel = config.modelOverride ?? evalCase.model ?? "mistral-large-latest"
            let (apiKey, apiKeySource) = try resolveAPIKey(config: config, evalRoot: evalRoot)
            let outputURL = outputFileURL(
                caseID: config.caseID,
                evalRoot: evalRoot,
                explicitOutputDir: config.outputDirPath
            )
            let caseRoot = evalRoot.appendingPathComponent("cases/\(config.caseID)", isDirectory: true)

            let result = await runEval(
                evalCase: evalCase,
                caseID: config.caseID,
                caseRoot: caseRoot,
                model: resolvedModel,
                judgeModel: config.judgeModel,
                apiKey: apiKey,
                apiKeySource: apiKeySource,
                timeoutSeconds: config.timeoutSeconds
            )

            try writeResult(result, to: outputURL)
            printSummary(result: result, outputURL: outputURL)
            if result.status == "FAIL" {
                exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct CLIConfig {
    let caseID: String
    let apiKeyOverride: String?
    let modelOverride: String?
    let judgeModel: String
    let evalRootPath: String?
    let outputDirPath: String?
    let timeoutSeconds: TimeInterval
    let showHelp: Bool

    static let helpText = """
    FoodBuddy AI Evals

    Usage:
      swift run FoodBuddyAIEvals --case <case-id> [--api-key <key>] [--model <model-id>] [--judge-model <model-id>] [--eval-root <path>] [--output-dir <path>] [--timeout-seconds <seconds>]

    Options:
      --judge-model   Model for LLM-as-judge scoring (default: mistral-small-latest)

    API key resolution priority:
      1) --api-key
      2) MISTRAL_API_KEY environment variable
      3) .env file in eval root
    """

    static func parse(arguments: [String]) throws -> CLIConfig {
        var caseID = "case-001"
        var apiKeyOverride: String?
        var modelOverride: String?
        var judgeModel = "mistral-small-latest"
        var evalRootPath: String?
        var outputDirPath: String?
        var timeoutSeconds: TimeInterval = 180
        var showHelp = false

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--help", "-h":
                showHelp = true
            case "--case":
                index += 1
                caseID = try value(for: arg, at: index, in: arguments)
            case "--api-key":
                index += 1
                apiKeyOverride = try value(for: arg, at: index, in: arguments)
            case "--model":
                index += 1
                modelOverride = try value(for: arg, at: index, in: arguments)
            case "--judge-model":
                index += 1
                judgeModel = try value(for: arg, at: index, in: arguments)
            case "--eval-root":
                index += 1
                evalRootPath = try value(for: arg, at: index, in: arguments)
            case "--output-dir":
                index += 1
                outputDirPath = try value(for: arg, at: index, in: arguments)
            case "--timeout-seconds":
                index += 1
                let raw = try value(for: arg, at: index, in: arguments)
                guard let parsed = TimeInterval(raw), parsed > 0 else {
                    throw CLIError.invalidArgument("Invalid value for --timeout-seconds: \(raw)")
                }
                timeoutSeconds = parsed
            default:
                throw CLIError.invalidArgument("Unknown argument: \(arg)")
            }
            index += 1
        }

        return CLIConfig(
            caseID: caseID,
            apiKeyOverride: apiKeyOverride,
            modelOverride: modelOverride,
            judgeModel: judgeModel,
            evalRootPath: evalRootPath,
            outputDirPath: outputDirPath,
            timeoutSeconds: timeoutSeconds,
            showHelp: showHelp
        )
    }

    private static func value(for argument: String, at index: Int, in args: [String]) throws -> String {
        guard index < args.count else {
            throw CLIError.invalidArgument("Missing value for \(argument)")
        }
        return args[index]
    }
}

private enum CLIError: LocalizedError {
    case invalidArgument(String)
    case invalidPath(String)
    case missingAPIKey
    case missingFile(String)
    case invalidCase(String)
    case requestBuildFailed
    case fileWriteFailed
    case judgeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message):
            return message
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .missingAPIKey:
            return "Missing API key. Set --api-key, MISTRAL_API_KEY, or evals/.env."
        case .missingFile(let path):
            return "Missing file: \(path)"
        case .invalidCase(let message):
            return message
        case .requestBuildFailed:
            return "Failed to build Mistral request body."
        case .fileWriteFailed:
            return "Failed to write eval result artifact."
        case .judgeFailed(let message):
            return "LLM judge failed: \(message)"
        }
    }
}

// MARK: - Case & Expected Types

private struct EvalCase: Decodable {
    let id: String
    let model: String?
    let notes: String?
    let images: [String]
    let expected: EvalExpected?
}

private struct EvalExpected: Codable {
    let passThreshold: Double?
    let mealContext: String?
    let descriptionHints: [String]?
    let foodItems: [ExpectedFoodItem]?

    enum CodingKeys: String, CodingKey {
        case passThreshold = "pass_threshold"
        case mealContext = "meal_context"
        case descriptionHints = "description_hints"
        case foodItems = "food_items"
    }
}

private struct ExpectedFoodItem: Codable {
    let name: String
    let category: String
    let servings: Double
}

// MARK: - Judge Types

private struct JudgeDimensionScore: Codable {
    let score: Int
    let reasoning: String
}

private struct JudgeResult: Codable {
    let itemIdentification: JudgeDimensionScore
    let categoryAccuracy: JudgeDimensionScore
    let servingEstimation: JudgeDimensionScore
    let descriptionQuality: JudgeDimensionScore
    let overallNotes: String?

    enum CodingKeys: String, CodingKey {
        case itemIdentification = "item_identification"
        case categoryAccuracy = "category_accuracy"
        case servingEstimation = "serving_estimation"
        case descriptionQuality = "description_quality"
        case overallNotes = "overall_notes"
    }

    /// Weighted average scaled to 0-100.
    /// Weights: category_accuracy 40%, serving_estimation 25%, item_identification 25%, description_quality 10%.
    var weightedScore: Double {
        let raw = Double(categoryAccuracy.score) * 0.40
            + Double(servingEstimation.score) * 0.25
            + Double(itemIdentification.score) * 0.25
            + Double(descriptionQuality.score) * 0.10
        return (raw / 10.0) * 100.0
    }
}

// MARK: - Result Types

private struct MistralUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private enum APIKeySource: String, Encodable {
    case commandLine = "cli_flag"
    case environment = "environment"
    case dotEnv = "dot_env"
}

private struct HardGates: Encodable {
    var http2xx: Bool
    var topLevelDecoded: Bool
    var contentJSONParsed: Bool
    var schemaConformant: Bool

    var allPassed: Bool {
        http2xx && topLevelDecoded && contentJSONParsed && schemaConformant
    }
}

private struct ComponentScores: Encodable {
    let itemIdentification: Int?
    let categoryAccuracy: Int?
    let servingEstimation: Int?
    let descriptionQuality: Int?

    enum CodingKeys: String, CodingKey {
        case itemIdentification = "item_identification"
        case categoryAccuracy = "category_accuracy"
        case servingEstimation = "serving_estimation"
        case descriptionQuality = "description_quality"
    }
}

private struct EvalRunResult: Encodable {
    let runAt: String
    let caseID: String
    let caseFileID: String
    let model: String
    let judgeModel: String
    let status: String
    let score: Double?
    let threshold: Double?
    let apiKeySource: APIKeySource
    let latencyMs: Int?
    let requestBodyBytes: Int?
    let timeToFirstByteMs: Int?
    let streamCompleted: Bool?
    let httpStatus: Int?
    let hardGates: HardGates
    let componentScores: ComponentScores
    let judgeReasoning: JudgeReasoning?
    let usage: MistralUsage?
    let actualPayload: FoodAnalysisPayload?
    let expected: EvalExpected?
    let responseBody: String?
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case runAt = "run_at"
        case caseID = "case_id"
        case caseFileID = "case_file_id"
        case model
        case judgeModel = "judge_model"
        case status
        case score
        case threshold
        case apiKeySource = "api_key_source"
        case latencyMs = "latency_ms"
        case requestBodyBytes = "request_body_bytes"
        case timeToFirstByteMs = "time_to_first_byte_ms"
        case streamCompleted = "stream_completed"
        case httpStatus = "http_status"
        case hardGates = "hard_gates"
        case componentScores = "component_scores"
        case judgeReasoning = "judge_reasoning"
        case usage
        case actualPayload = "actual_payload"
        case expected
        case responseBody = "response_body"
        case notes
    }
}

/// Reasoning strings from the judge, persisted in the artifact for debugging.
private struct JudgeReasoning: Encodable {
    let itemIdentification: String
    let categoryAccuracy: String
    let servingEstimation: String
    let descriptionQuality: String
    let overallNotes: String?

    enum CodingKeys: String, CodingKey {
        case itemIdentification = "item_identification"
        case categoryAccuracy = "category_accuracy"
        case servingEstimation = "serving_estimation"
        case descriptionQuality = "description_quality"
        case overallNotes = "overall_notes"
    }
}

// MARK: - Eval Root & Case Loading

private func resolveEvalRoot(explicitPath: String?) throws -> URL {
    let fileManager = FileManager.default
    let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

    if let explicitPath {
        let url = URL(fileURLWithPath: explicitPath, relativeTo: cwd).standardizedFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            throw CLIError.invalidPath(explicitPath)
        }
        return url
    }

    let cwdPackage = cwd.appendingPathComponent("Package.swift")
    let cwdCases = cwd.appendingPathComponent("cases")
    if fileManager.fileExists(atPath: cwdPackage.path),
       fileManager.fileExists(atPath: cwdCases.path) {
        return cwd
    }

    let nestedEvals = cwd.appendingPathComponent("evals", isDirectory: true)
    let nestedPackage = nestedEvals.appendingPathComponent("Package.swift")
    let nestedCases = nestedEvals.appendingPathComponent("cases")
    if fileManager.fileExists(atPath: nestedPackage.path),
       fileManager.fileExists(atPath: nestedCases.path) {
        return nestedEvals
    }

    throw CLIError.invalidPath("Could not resolve eval root. Pass --eval-root explicitly.")
}

private func loadCase(id: String, evalRoot: URL) throws -> EvalCase {
    let caseURL = evalRoot.appendingPathComponent("cases/\(id)/case.json")
    guard let data = FileManager.default.contents(atPath: caseURL.path) else {
        throw CLIError.missingFile(caseURL.path)
    }

    let evalCase = try JSONDecoder().decode(EvalCase.self, from: data)
    let hasImages = !evalCase.images.isEmpty
    let hasNotes = !(evalCase.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    guard hasImages || hasNotes else {
        throw CLIError.invalidCase("Case \(id) must include at least one image or non-empty notes.")
    }
    return evalCase
}

private func resolveAPIKey(config: CLIConfig, evalRoot: URL) throws -> (String, APIKeySource) {
    if let override = config.apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        return (override, .commandLine)
    }

    let envKey = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let envKey, !envKey.isEmpty {
        return (envKey, .environment)
    }

    let dotEnvURL = evalRoot.appendingPathComponent(".env")
    if let dotEnvData = FileManager.default.contents(atPath: dotEnvURL.path),
       let dotEnvContent = String(data: dotEnvData, encoding: .utf8),
       let value = parseDotEnv(content: dotEnvContent, key: "MISTRAL_API_KEY"),
       !value.isEmpty {
        return (value, .dotEnv)
    }

    throw CLIError.missingAPIKey
}

private func parseDotEnv(content: String, key: String) -> String? {
    let lines = content.split(whereSeparator: \.isNewline)
    for line in lines {
        var entry = String(line).trimmingCharacters(in: .whitespaces)
        if entry.isEmpty || entry.hasPrefix("#") {
            continue
        }

        if entry.hasPrefix("export ") {
            entry = String(entry.dropFirst("export ".count))
        }

        guard let separator = entry.firstIndex(of: "=") else {
            continue
        }

        let entryKey = String(entry[..<separator]).trimmingCharacters(in: .whitespaces)
        guard entryKey == key else {
            continue
        }

        var value = String(entry[entry.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    return nil
}

private func outputFileURL(caseID: String, evalRoot: URL, explicitOutputDir: String?) -> URL {
    let baseDir: URL
    if let explicitOutputDir {
        baseDir = URL(fileURLWithPath: explicitOutputDir, relativeTo: evalRoot).standardizedFileURL
    } else {
        baseDir = evalRoot.appendingPathComponent("results")
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    return baseDir.appendingPathComponent("\(caseID)-\(timestamp).json")
}

// MARK: - Eval Runner

private func runEval(
    evalCase: EvalCase,
    caseID: String,
    caseRoot: URL,
    model: String,
    judgeModel: String,
    apiKey: String,
    apiKeySource: APIKeySource,
    timeoutSeconds: TimeInterval
) async -> EvalRunResult {
    var notes: [String] = []
    var hardGates = HardGates(http2xx: false, topLevelDecoded: false, contentJSONParsed: false, schemaConformant: false)
    var httpStatus: Int?
    var latencyMs: Int?
    var requestBodyBytes: Int?
    var timeToFirstByteMs: Int?
    var streamCompleted: Bool?
    var usage: MistralUsage?
    var actualPayload: FoodAnalysisPayload?
    var rawResponseBody: String?

    var imageData: [Data] = []
    imageData.reserveCapacity(evalCase.images.count)
    var sourceImageBytes = 0
    var preparedImageBytes = 0
    for imagePath in evalCase.images {
        let url = caseRoot.appendingPathComponent(imagePath)
        guard let sourceData = FileManager.default.contents(atPath: url.path) else {
            notes.append("Could not load image fixture at \(url.path).")
            return buildResult(
                evalCase: evalCase,
                caseID: caseID,
                model: model,
                judgeModel: judgeModel,
                apiKeySource: apiKeySource,
                latencyMs: latencyMs,
                requestBodyBytes: requestBodyBytes,
                timeToFirstByteMs: timeToFirstByteMs,
                streamCompleted: streamCompleted,
                httpStatus: httpStatus,
                hardGates: hardGates,
                usage: usage,
                actualPayload: actualPayload,
                judgeResult: nil,
                rawResponseBody: rawResponseBody,
                notes: notes
            )
        }
        sourceImageBytes += sourceData.count
        let preparedData = preprocessImageForAnalysis(sourceData)
        preparedImageBytes += preparedData.count
        imageData.append(preparedData)
    }
    if sourceImageBytes > 0 {
        let ratio = Double(preparedImageBytes) / Double(sourceImageBytes)
        notes.append(
            "Prepared image bytes: \(preparedImageBytes) (from \(sourceImageBytes), ratio \(String(format: "%.2f", ratio)))."
        )
    }

    let requestBodyData: Data
    do {
        requestBodyData = try FoodAnalysisRequestFactory.makeJSONData(
            model: model,
            images: imageData,
            notes: evalCase.notes,
            categoryIdentifiers: FoodAnalysisCategories.all,
            stream: true,
            maxTokens: 400
        )
        requestBodyBytes = requestBodyData.count
    } catch {
        notes.append("Failed to encode request payload: \(error)")
        return buildResult(
            evalCase: evalCase,
            caseID: caseID,
            model: model,
            judgeModel: judgeModel,
            apiKeySource: apiKeySource,
            latencyMs: latencyMs,
            requestBodyBytes: requestBodyBytes,
            timeToFirstByteMs: timeToFirstByteMs,
            streamCompleted: streamCompleted,
            httpStatus: httpStatus,
            hardGates: hardGates,
            usage: usage,
            actualPayload: actualPayload,
            judgeResult: nil,
            rawResponseBody: rawResponseBody,
            notes: notes
        )
    }

    // Use AsyncHTTPClient (SwiftNIO) instead of URLSession to force HTTP/2.
    // URLSession may negotiate HTTP/3 (QUIC) with Cloudflare and fail with 502.
    // AsyncHTTPClient only advertises h2/http1.1 via ALPN, avoiding this issue.
    let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)

    var ahcRequest = HTTPClientRequest(url: "https://api.mistral.ai/v1/chat/completions")
    ahcRequest.method = .POST
    ahcRequest.headers.add(name: "Content-Type", value: "application/json")
    ahcRequest.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
    ahcRequest.headers.add(name: "Accept", value: "text/event-stream")
    ahcRequest.body = .bytes(ByteBuffer(data: requestBodyData))

    let runStart = Date()
    let maxAttempts = 3
    attemptLoop: for attempt in 1...maxAttempts {
        let attemptStart = Date()
        do {
            let response = try await httpClient.execute(ahcRequest, timeout: .seconds(Int64(timeoutSeconds)))
            let statusCode = Int(response.status.code)

            httpStatus = statusCode
            hardGates.http2xx = (200..<300).contains(statusCode)

            if !hardGates.http2xx {
                // Collect bounded error body preview
                var errorBody = ""
                var linesRead = 0
                var lineBuffer = ByteBuffer()
                for try await chunk in response.body {
                    lineBuffer.writeImmutableBuffer(chunk)
                    while let line = lineBuffer.readLine() {
                        if timeToFirstByteMs == nil {
                            timeToFirstByteMs = Int(Date().timeIntervalSince(attemptStart) * 1_000)
                        }
                        if !line.isEmpty {
                            errorBody += line + "\n"
                        }
                        linesRead += 1
                        if errorBody.count >= 2_000 || linesRead >= 8 { break }
                    }
                    if errorBody.count >= 2_000 || linesRead >= 8 { break }
                }
                rawResponseBody = errorBody.isEmpty ? nil : errorBody
                latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
                notes.append("HTTP \(statusCode) from Mistral.")

                if shouldRetry(statusCode: statusCode, attempt: attempt, maxAttempts: maxAttempts) {
                    notes.append("Retrying after transient HTTP \(statusCode) (attempt \(attempt + 1)/\(maxAttempts)).")
                    await sleepBeforeRetry(attempt: attempt)
                    continue attemptLoop
                }
                break attemptLoop
            }

            var streamAccumulator = MistralStreamAccumulator()
            var rawStreamLines: [String] = []
            rawStreamLines.reserveCapacity(256)

            var lineBuffer = ByteBuffer()
            for try await chunk in response.body {
                lineBuffer.writeImmutableBuffer(chunk)
                while let line = lineBuffer.readLine() {
                    if timeToFirstByteMs == nil {
                        timeToFirstByteMs = Int(Date().timeIntervalSince(attemptStart) * 1_000)
                    }
                    rawStreamLines.append(line)
                    try streamAccumulator.consume(line: line)
                }
            }
            latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
            rawResponseBody = rawStreamLines.joined(separator: "\n")

            do {
                let streamResult = try streamAccumulator.finish()
                streamCompleted = streamResult.receivedDone
                usage = mapUsage(streamResult.usage)
                hardGates.topLevelDecoded = true

                let parseResult = try FoodAnalysisResponseParser.parseAssistantContent(streamResult.assistantContent)
                hardGates.contentJSONParsed = true

                if let contentData = streamResult.assistantContent.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: contentData) {
                    hardGates.schemaConformant = validateSchema(object: object, allowedCategories: Set(FoodAnalysisCategories.all))
                }
                if hardGates.schemaConformant {
                    actualPayload = parseResult.payload
                }
            } catch {
                if let rawResponseBody,
                   let fallbackData = rawResponseBody.data(using: .utf8),
                   let fallbackParse = try? FoodAnalysisResponseParser.parseResponseData(fallbackData),
                   let object = try? JSONSerialization.jsonObject(with: Data(fallbackParse.rawContent.utf8)) {
                    hardGates.topLevelDecoded = true
                    hardGates.contentJSONParsed = true
                    hardGates.schemaConformant = validateSchema(object: object, allowedCategories: Set(FoodAnalysisCategories.all))
                    if hardGates.schemaConformant {
                        actualPayload = fallbackParse.payload
                    }
                    notes.append("Stream parser fallback parsed a non-stream JSON body.")
                } else {
                    throw error
                }
            }

            break attemptLoop
        } catch let streamError as MistralStreamParserError {
            latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
            notes.append("Failed to parse streaming response: \(streamError.localizedDescription)")
            break attemptLoop
        } catch {
            latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
            let errorDesc = String(describing: error)
            let isTimeout = errorDesc.contains("deadlineExceeded") || errorDesc.contains("readTimeout") || errorDesc.contains("connectTimeout")
            let isConnectionClosed = errorDesc.contains("remoteConnectionClosed")
            let isRetryable = isTimeout || isConnectionClosed

            if isRetryable, attempt < maxAttempts {
                notes.append("Transient network failure (\(errorDesc)); retrying attempt \(attempt + 1)/\(maxAttempts).")
                await sleepBeforeRetry(attempt: attempt)
                continue attemptLoop
            }

            notes.append("Network call failed: \(errorDesc)")
            if isTimeout {
                notes.append("Request timed out after \(Int(timeoutSeconds))s. Try a higher --timeout-seconds value (e.g. 240).")
            }
            break attemptLoop
        }
    }

    if hardGates.http2xx, actualPayload == nil {
        notes.append("HTTP succeeded but payload could not be parsed and validated.")
    }

    // Run LLM-as-judge if hard gates passed and we have a payload
    var judgeResult: JudgeResult?
    if hardGates.allPassed, let actualPayload, let expected = evalCase.expected {
        do {
            judgeResult = try await callJudge(
                httpClient: httpClient,
                apiKey: apiKey,
                judgeModel: judgeModel,
                expected: expected,
                actualPayload: actualPayload,
                timeoutSeconds: timeoutSeconds
            )
            notes.append("LLM judge scored successfully using \(judgeModel).")
        } catch {
            notes.append("LLM judge call failed: \(error). Scoring will use WARN status.")
        }
    }

    try? await httpClient.shutdown()

    return buildResult(
        evalCase: evalCase,
        caseID: caseID,
        model: model,
        judgeModel: judgeModel,
        apiKeySource: apiKeySource,
        latencyMs: latencyMs,
        requestBodyBytes: requestBodyBytes,
        timeToFirstByteMs: timeToFirstByteMs,
        streamCompleted: streamCompleted,
        httpStatus: httpStatus,
        hardGates: hardGates,
        usage: usage,
        actualPayload: actualPayload,
        judgeResult: judgeResult,
        rawResponseBody: rawResponseBody,
        notes: notes
    )
}

// MARK: - LLM-as-Judge

private func callJudge(
    httpClient: HTTPClient,
    apiKey: String,
    judgeModel: String,
    expected: EvalExpected,
    actualPayload: FoodAnalysisPayload,
    timeoutSeconds: TimeInterval
) async throws -> JudgeResult {
    let prompt = buildJudgePrompt(expected: expected, actualPayload: actualPayload)

    let requestBody: [String: Any] = [
        "model": judgeModel,
        "messages": [
            ["role": "user", "content": prompt]
        ],
        "response_format": ["type": "json_object"],
        "max_tokens": 500,
        "temperature": 0.0
    ]

    let requestData = try JSONSerialization.data(withJSONObject: requestBody)

    var request = HTTPClientRequest(url: "https://api.mistral.ai/v1/chat/completions")
    request.method = .POST
    request.headers.add(name: "Content-Type", value: "application/json")
    request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
    request.body = .bytes(ByteBuffer(data: requestData))

    let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeoutSeconds)))
    let statusCode = Int(response.status.code)
    guard (200..<300).contains(statusCode) else {
        throw CLIError.judgeFailed("HTTP \(statusCode) from judge model")
    }

    var bodyBuffer = ByteBuffer()
    for try await chunk in response.body {
        bodyBuffer.writeImmutableBuffer(chunk)
    }
    guard let bodyData = bodyBuffer.readData(length: bodyBuffer.readableBytes) else {
        throw CLIError.judgeFailed("Empty response body")
    }

    // Parse the Mistral response envelope to extract the assistant content
    guard let envelope = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
          let choices = envelope["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
        throw CLIError.judgeFailed("Could not extract assistant content from judge response")
    }

    guard let contentData = content.data(using: .utf8) else {
        throw CLIError.judgeFailed("Judge content is not valid UTF-8")
    }

    let decoder = JSONDecoder()
    let result = try decoder.decode(JudgeResult.self, from: contentData)

    // Validate score ranges
    let scores = [
        result.itemIdentification.score,
        result.categoryAccuracy.score,
        result.servingEstimation.score,
        result.descriptionQuality.score,
    ]
    for score in scores {
        guard (0...10).contains(score) else {
            throw CLIError.judgeFailed("Judge returned score \(score) outside 0-10 range")
        }
    }

    return result
}

private func buildJudgePrompt(expected: EvalExpected, actualPayload: FoodAnalysisPayload) -> String {
    let categoryList = FoodAnalysisCategories.all.joined(separator: ", ")

    // Serialize expected food items for the judge
    var expectedItemsJSON = "[]"
    if let items = expected.foodItems {
        let itemDicts = items.map { item -> [String: Any] in
            ["name": item.name, "category": item.category, "servings": item.servings]
        }
        if let data = try? JSONSerialization.data(withJSONObject: itemDicts, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            expectedItemsJSON = str
        }
    }

    // Serialize actual food items
    let actualItemDicts = actualPayload.foodItems.map { item -> [String: Any] in
        ["name": item.name, "category": item.category, "servings": item.servings]
    }
    var actualItemsJSON = "[]"
    if let data = try? JSONSerialization.data(withJSONObject: actualItemDicts, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
        actualItemsJSON = str
    }

    let mealContext = expected.mealContext ?? "No meal context provided."
    let hints = expected.descriptionHints ?? []
    let hintsText = hints.isEmpty ? "None" : hints.joined(separator: ", ")

    return """
    You are a food analysis evaluator. Compare an AI's meal analysis against the expected answer and score it.

    ## Meal Context
    \(mealContext)

    ## Expected Output
    Description hints (keywords that should appear): \(hintsText)
    Expected food items:
    \(expectedItemsJSON)

    ## Actual AI Output
    Description: \(actualPayload.description)
    Food items:
    \(actualItemsJSON)

    ## Scoring Rubric

    Score each dimension 0-10. **Category accuracy is the most important dimension.**

    1. **item_identification**: Did the AI identify the correct food items? Be lenient on exact names — semantically equivalent names are fine (e.g. "chicken breast" ≈ "grilled chicken", "penne" ≈ "pasta", "sourdough" ≈ "bread"). What matters is that the AI found the right number of distinct food items. Penalize missing items more than extra reasonable items. Score 8-10 if all major items found, 5-7 if some missing, 0-4 if mostly wrong.

    2. **category_accuracy**: THIS IS THE PRIMARY METRIC. Are the DQS categories assigned correctly for each item? Valid categories: \(categoryList). Even if the AI uses a slightly different name for a food item (e.g. "rigatoni" instead of "penne"), the category should still be correct (both are refined_grains). Penalize wrong categories strictly. Score 9-10 if all categories correct, 7-8 if one minor error, 5-6 if multiple errors, 0-4 if mostly wrong.

    3. **serving_estimation**: Are the serving counts reasonable? Within ±0.5 of expected is excellent (9-10). Within ±1.0 is good (6-8). Larger deviations score lower.

    4. **description_quality**: Is the description relevant to the meal and concise (1-3 sentences)? Be lenient on exact food names — e.g. saying "rigatoni" instead of "penne" or "rye bread" instead of "sourdough" is acceptable as long as the description captures the overall meal accurately.

    Respond with ONLY this JSON (no other text):
    {"item_identification": {"score": <0-10>, "reasoning": "<1 sentence>"}, "category_accuracy": {"score": <0-10>, "reasoning": "<1 sentence>"}, "serving_estimation": {"score": <0-10>, "reasoning": "<1 sentence>"}, "description_quality": {"score": <0-10>, "reasoning": "<1 sentence>"}, "overall_notes": "<optional 1 sentence>"}
    """
}

// MARK: - Scoring

private func buildResult(
    evalCase: EvalCase,
    caseID: String,
    model: String,
    judgeModel: String,
    apiKeySource: APIKeySource,
    latencyMs: Int?,
    requestBodyBytes: Int?,
    timeToFirstByteMs: Int?,
    streamCompleted: Bool?,
    httpStatus: Int?,
    hardGates: HardGates,
    usage: MistralUsage?,
    actualPayload: FoodAnalysisPayload?,
    judgeResult: JudgeResult?,
    rawResponseBody: String?,
    notes: [String]
) -> EvalRunResult {
    let threshold = evalCase.expected?.passThreshold ?? 75
    let status: String
    let score: Double?
    let components: ComponentScores
    let reasoning: JudgeReasoning?

    if !hardGates.allPassed {
        status = "FAIL"
        score = nil
        components = ComponentScores(itemIdentification: nil, categoryAccuracy: nil, servingEstimation: nil, descriptionQuality: nil)
        reasoning = nil
    } else if let judgeResult {
        let weighted = (judgeResult.weightedScore * 100).rounded() / 100
        score = weighted
        status = weighted >= threshold ? "PASS" : "WARN"
        components = ComponentScores(
            itemIdentification: judgeResult.itemIdentification.score,
            categoryAccuracy: judgeResult.categoryAccuracy.score,
            servingEstimation: judgeResult.servingEstimation.score,
            descriptionQuality: judgeResult.descriptionQuality.score
        )
        reasoning = JudgeReasoning(
            itemIdentification: judgeResult.itemIdentification.reasoning,
            categoryAccuracy: judgeResult.categoryAccuracy.reasoning,
            servingEstimation: judgeResult.servingEstimation.reasoning,
            descriptionQuality: judgeResult.descriptionQuality.reasoning,
            overallNotes: judgeResult.overallNotes
        )
    } else {
        // Hard gates passed but judge didn't run (no expected data or judge failed)
        status = "WARN"
        score = nil
        components = ComponentScores(itemIdentification: nil, categoryAccuracy: nil, servingEstimation: nil, descriptionQuality: nil)
        reasoning = nil
    }

    return EvalRunResult(
        runAt: ISO8601DateFormatter().string(from: Date()),
        caseID: caseID,
        caseFileID: evalCase.id,
        model: model,
        judgeModel: judgeModel,
        status: status,
        score: score,
        threshold: threshold,
        apiKeySource: apiKeySource,
        latencyMs: latencyMs,
        requestBodyBytes: requestBodyBytes,
        timeToFirstByteMs: timeToFirstByteMs,
        streamCompleted: streamCompleted,
        httpStatus: httpStatus,
        hardGates: hardGates,
        componentScores: components,
        judgeReasoning: reasoning,
        usage: usage,
        actualPayload: actualPayload,
        expected: evalCase.expected,
        responseBody: rawResponseBody,
        notes: notes
    )
}

// MARK: - Helpers

private func mapUsage(_ usage: MistralStreamUsage?) -> MistralUsage? {
    guard let usage else {
        return nil
    }

    return MistralUsage(
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        totalTokens: usage.totalTokens
    )
}

private func shouldRetry(statusCode: Int, attempt: Int, maxAttempts: Int) -> Bool {
    guard attempt < maxAttempts else {
        return false
    }
    return [408, 429, 500, 502, 503, 504].contains(statusCode)
}

private func sleepBeforeRetry(attempt: Int) async {
    let exponent = UInt64(max(0, attempt - 1))
    let delayMs = UInt64(500) * (1 << exponent)
    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
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

// MARK: - Schema Validation

private func validateSchema(object: Any, allowedCategories: Set<String>) -> Bool {
    guard let root = object as? [String: Any] else {
        return false
    }
    let expectedRootKeys: Set<String> = ["description", "food_items"]
    guard Set(root.keys) == expectedRootKeys else {
        return false
    }

    guard let description = root["description"] as? String,
          !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let foodItems = root["food_items"] as? [[String: Any]] else {
        return false
    }

    for item in foodItems {
        let expectedItemKeys: Set<String> = ["name", "category", "servings"]
        guard Set(item.keys) == expectedItemKeys else {
            return false
        }

        guard let name = item["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let category = item["category"] as? String,
              allowedCategories.contains(category),
              let servings = item["servings"] as? Double,
              servings > 0 else {
            return false
        }
    }

    return true
}

// MARK: - Image Preprocessing

private func preprocessImageForAnalysis(
    _ sourceData: Data,
    maxLongEdge: CGFloat = 1600,
    compressionQuality: CGFloat = 0.75
) -> Data {
    guard let imageSource = CGImageSourceCreateWithData(sourceData as CFData, nil),
          let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        return sourceData
    }

    let sourceWidth = CGFloat(sourceImage.width)
    let sourceHeight = CGFloat(sourceImage.height)
    let longEdge = max(sourceWidth, sourceHeight)

    let targetImage: CGImage
    if longEdge > maxLongEdge {
        let scale = maxLongEdge / longEdge
        let targetWidth = max(1, Int((sourceWidth * scale).rounded()))
        let targetHeight = max(1, Int((sourceHeight * scale).rounded()))
        let colorSpace = sourceImage.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return sourceData
        }
        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)))
        guard let resizedImage = context.makeImage() else {
            return sourceData
        }
        targetImage = resizedImage
    } else {
        targetImage = sourceImage
    }

    let encoded = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        encoded,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        return sourceData
    }

    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: compressionQuality
    ]
    CGImageDestinationAddImage(destination, targetImage, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        return sourceData
    }

    let preparedData = encoded as Data
    return preparedData.isEmpty ? sourceData : preparedData
}

// MARK: - Output

private func writeResult(_ result: EvalRunResult, to fileURL: URL) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let data = try encoder.encode(result)
        try data.write(to: fileURL, options: .atomic)
    } catch {
        throw CLIError.fileWriteFailed
    }
}

private func truncateForLog(_ value: String, maxChars: Int) -> String {
    guard value.count > maxChars else {
        return value
    }
    let endIndex = value.index(value.startIndex, offsetBy: maxChars)
    return String(value[..<endIndex]) + "..."
}

private func printSummary(result: EvalRunResult, outputURL: URL) {
    print("Case: \(result.caseID) (\(result.caseFileID))")
    print("Model: \(result.model)")
    print("Judge: \(result.judgeModel)")
    print("Status: \(result.status)")
    if let score = result.score, let threshold = result.threshold {
        print("Score: \(score) / 100 (threshold \(threshold))")
    }
    print("Hard gates: http2xx=\(result.hardGates.http2xx) topLevelDecoded=\(result.hardGates.topLevelDecoded) contentJSONParsed=\(result.hardGates.contentJSONParsed) schemaConformant=\(result.hardGates.schemaConformant)")

    // Print judge component scores and reasoning
    if let reasoning = result.judgeReasoning {
        print("Judge scores:")
        if let s = result.componentScores.itemIdentification {
            print("  Item identification: \(s)/10 — \(reasoning.itemIdentification)")
        }
        if let s = result.componentScores.categoryAccuracy {
            print("  Category accuracy:   \(s)/10 — \(reasoning.categoryAccuracy)")
        }
        if let s = result.componentScores.servingEstimation {
            print("  Serving estimation:  \(s)/10 — \(reasoning.servingEstimation)")
        }
        if let s = result.componentScores.descriptionQuality {
            print("  Description quality: \(s)/10 — \(reasoning.descriptionQuality)")
        }
        if let notes = reasoning.overallNotes, !notes.isEmpty {
            print("  Overall: \(notes)")
        }
    }

    if let latencyMs = result.latencyMs {
        print("Latency: \(latencyMs) ms")
    }
    if let requestBodyBytes = result.requestBodyBytes {
        print("Request body: \(requestBodyBytes) bytes")
    }
    if let timeToFirstByteMs = result.timeToFirstByteMs {
        print("Time to first byte: \(timeToFirstByteMs) ms")
    }
    if let streamCompleted = result.streamCompleted {
        print("Stream completed: \(streamCompleted)")
    }
    if let httpStatus = result.httpStatus {
        print("HTTP: \(httpStatus)")
    }
    print("API key source: \(result.apiKeySource.rawValue)")
    if !result.notes.isEmpty {
        print("Notes:")
        for note in result.notes {
            print("- \(note)")
        }
    }
    if result.status == "FAIL", let responseBody = result.responseBody, !responseBody.isEmpty {
        print("Response preview: \(truncateForLog(responseBody, maxChars: 500))")
    }
    print("Artifact: \(outputURL.path)")
}
