import FoodBuddyAIShared
import CoreGraphics
import Foundation
import ImageIO
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
    let evalRootPath: String?
    let outputDirPath: String?
    let timeoutSeconds: TimeInterval
    let showHelp: Bool

    static let helpText = """
    FoodBuddy AI Evals

    Usage:
      swift run FoodBuddyAIEvals --case <case-id> [--api-key <key>] [--model <model-id>] [--eval-root <path>] [--output-dir <path>] [--timeout-seconds <seconds>]

    API key resolution priority:
      1) --api-key
      2) MISTRAL_API_KEY environment variable
      3) .env file in eval root
    """

    static func parse(arguments: [String]) throws -> CLIConfig {
        var caseID = "case-001"
        var apiKeyOverride: String?
        var modelOverride: String?
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
        }
    }
}

private struct EvalCase: Decodable {
    let id: String
    let model: String?
    let notes: String?
    let images: [String]
    let expected: EvalExpected?
}

private struct EvalExpected: Decodable, Encodable {
    let passThreshold: Double?
    let servingsTolerance: Double?
    let description: DescriptionExpectation?
    let foodItems: [ExpectedFoodItem]?

    enum CodingKeys: String, CodingKey {
        case passThreshold = "pass_threshold"
        case servingsTolerance = "servings_tolerance"
        case description
        case foodItems = "food_items"
    }
}

private struct DescriptionExpectation: Decodable, Encodable {
    let minSentences: Int?
    let maxSentences: Int?
    let mustContain: [String]?

    enum CodingKeys: String, CodingKey {
        case minSentences = "min_sentences"
        case maxSentences = "max_sentences"
        case mustContain = "must_contain"
    }
}

private struct ExpectedFoodItem: Decodable, Encodable {
    let name: String
    let categories: [String]
    let servings: Double
}

private struct MistralUsage: Decodable, Encodable {
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
    let description: Double?
    let itemExtraction: Double?
    let categoryQuality: Double?
    let servingQuality: Double?

    enum CodingKeys: String, CodingKey {
        case description
        case itemExtraction = "item_extraction"
        case categoryQuality = "category_quality"
        case servingQuality = "serving_quality"
    }
}

private struct EvalRunResult: Encodable {
    let runAt: String
    let caseID: String
    let caseFileID: String
    let model: String
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
        case usage
        case actualPayload = "actual_payload"
        case expected
        case responseBody = "response_body"
        case notes
    }
}

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

private func runEval(
    evalCase: EvalCase,
    caseID: String,
    caseRoot: URL,
    model: String,
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
                apiKeySource: apiKeySource,
                latencyMs: latencyMs,
                requestBodyBytes: requestBodyBytes,
                timeToFirstByteMs: timeToFirstByteMs,
                streamCompleted: streamCompleted,
                httpStatus: httpStatus,
                hardGates: hardGates,
                usage: usage,
                actualPayload: actualPayload,
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

    var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.timeoutInterval = timeoutSeconds

    do {
        let requestBody = try FoodAnalysisRequestFactory.makeJSONData(
            model: model,
            images: imageData,
            notes: evalCase.notes,
            categoryIdentifiers: FoodAnalysisCategories.all,
            stream: true,
            maxTokens: 400
        )
        request.httpBody = requestBody
        requestBodyBytes = requestBody.count
    } catch {
        notes.append("Failed to encode request payload: \(error)")
        return buildResult(
            evalCase: evalCase,
            caseID: caseID,
            model: model,
            apiKeySource: apiKeySource,
            latencyMs: latencyMs,
            requestBodyBytes: requestBodyBytes,
            timeToFirstByteMs: timeToFirstByteMs,
            streamCompleted: streamCompleted,
            httpStatus: httpStatus,
            hardGates: hardGates,
            usage: usage,
            actualPayload: actualPayload,
            rawResponseBody: rawResponseBody,
            notes: notes
        )
    }

    let runStart = Date()
    let maxAttempts = 3
    attemptLoop: for attempt in 1...maxAttempts {
        let attemptStart = Date()
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                notes.append("Non-HTTP response received.")
                break attemptLoop
            }

            httpStatus = httpResponse.statusCode
            hardGates.http2xx = (200..<300).contains(httpResponse.statusCode)

            if !hardGates.http2xx {
                let bodyPreview = await collectBodyPreview(
                    from: bytes,
                    maxChars: 2_000,
                    maxLines: 8,
                    startedAt: attemptStart
                )
                if timeToFirstByteMs == nil {
                    timeToFirstByteMs = bodyPreview.timeToFirstByteMs
                }
                rawResponseBody = bodyPreview.body
                latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
                notes.append("HTTP \(httpResponse.statusCode) from Mistral.")

                if shouldRetry(statusCode: httpResponse.statusCode, attempt: attempt, maxAttempts: maxAttempts) {
                    notes.append("Retrying after transient HTTP \(httpResponse.statusCode) (attempt \(attempt + 1)/\(maxAttempts)).")
                    await sleepBeforeRetry(attempt: attempt)
                    continue attemptLoop
                }
                break attemptLoop
            }

            var streamAccumulator = MistralStreamAccumulator()
            var rawStreamLines: [String] = []
            rawStreamLines.reserveCapacity(256)

            for try await line in bytes.lines {
                if timeToFirstByteMs == nil {
                    timeToFirstByteMs = Int(Date().timeIntervalSince(attemptStart) * 1_000)
                }
                rawStreamLines.append(line)
                try streamAccumulator.consume(line: line)
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
        } catch let urlError as URLError {
            latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
            if shouldRetry(urlError: urlError, attempt: attempt, maxAttempts: maxAttempts) {
                notes.append("Transient network failure (\(urlError.code.rawValue): \(urlError.code)); retrying attempt \(attempt + 1)/\(maxAttempts).")
                await sleepBeforeRetry(attempt: attempt)
                continue attemptLoop
            }

            notes.append("Network call failed (\(urlError.code.rawValue): \(urlError.code)).")
            notes.append("Underlying: \(urlError.localizedDescription)")
            let nsError = urlError as NSError
            if let failingURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
                notes.append("Failing URL: \(failingURL)")
            }
            if urlError.code == .timedOut {
                notes.append("Request timed out after \(Int(timeoutSeconds))s. Try a higher --timeout-seconds value (e.g. 240).")
            } else if urlError.code == .cancelled, let latencyMs, latencyMs >= 90_000 {
                notes.append("Cancellation happened after ~\(latencyMs)ms, which often indicates an upstream timeout for long-running requests.")
                notes.append("Try stream-friendly budgets: lower max_tokens, faster model (e.g. --model mistral-small-latest), or simplify prompt/schema.")
            }
            break attemptLoop
        } catch let streamError as MistralStreamParserError {
            latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
            notes.append("Failed to parse streaming response: \(streamError.localizedDescription)")
            break attemptLoop
        } catch {
            latencyMs = Int(Date().timeIntervalSince(runStart) * 1_000)
            notes.append("Network call failed: \(error.localizedDescription)")
            break attemptLoop
        }
    }

    if hardGates.http2xx, actualPayload == nil {
        notes.append("HTTP succeeded but payload could not be parsed and validated.")
    }

    return buildResult(
        evalCase: evalCase,
        caseID: caseID,
        model: model,
        apiKeySource: apiKeySource,
        latencyMs: latencyMs,
        requestBodyBytes: requestBodyBytes,
        timeToFirstByteMs: timeToFirstByteMs,
        streamCompleted: streamCompleted,
        httpStatus: httpStatus,
        hardGates: hardGates,
        usage: usage,
        actualPayload: actualPayload,
        rawResponseBody: rawResponseBody,
        notes: notes
    )
}

private func buildResult(
    evalCase: EvalCase,
    caseID: String,
    model: String,
    apiKeySource: APIKeySource,
    latencyMs: Int?,
    requestBodyBytes: Int?,
    timeToFirstByteMs: Int?,
    streamCompleted: Bool?,
    httpStatus: Int?,
    hardGates: HardGates,
    usage: MistralUsage?,
    actualPayload: FoodAnalysisPayload?,
    rawResponseBody: String?,
    notes: [String]
) -> EvalRunResult {
    let scoreResult = score(evalCase: evalCase, actualPayload: actualPayload, hardGatesPassed: hardGates.allPassed)

    return EvalRunResult(
        runAt: ISO8601DateFormatter().string(from: Date()),
        caseID: caseID,
        caseFileID: evalCase.id,
        model: model,
        status: scoreResult.status,
        score: scoreResult.score,
        threshold: scoreResult.threshold,
        apiKeySource: apiKeySource,
        latencyMs: latencyMs,
        requestBodyBytes: requestBodyBytes,
        timeToFirstByteMs: timeToFirstByteMs,
        streamCompleted: streamCompleted,
        httpStatus: httpStatus,
        hardGates: hardGates,
        componentScores: scoreResult.components,
        usage: usage,
        actualPayload: actualPayload,
        expected: evalCase.expected,
        responseBody: rawResponseBody,
        notes: notes + scoreResult.notes
    )
}

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

private func shouldRetry(urlError: URLError, attempt: Int, maxAttempts: Int) -> Bool {
    guard attempt < maxAttempts else {
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
    let delayMs = UInt64(500) * (1 << exponent)
    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
}

private func collectBodyPreview(
    from bytes: URLSession.AsyncBytes,
    maxChars: Int,
    maxLines: Int,
    startedAt: Date
) async -> (body: String?, timeToFirstByteMs: Int?) {
    var body = ""
    var linesRead = 0
    var firstByteMs: Int?

    do {
        for try await line in bytes.lines {
            if firstByteMs == nil {
                firstByteMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            }
            if !line.isEmpty {
                body += line
                body += "\n"
            }
            linesRead += 1
            if body.count >= maxChars || linesRead >= maxLines {
                break
            }
        }
    } catch {
        if body.isEmpty {
            return (nil, firstByteMs)
        }
    }

    guard !body.isEmpty else {
        return (nil, firstByteMs)
    }
    return (String(body.prefix(maxChars)), firstByteMs)
}

private func score(evalCase: EvalCase, actualPayload: FoodAnalysisPayload?, hardGatesPassed: Bool) -> (status: String, score: Double?, threshold: Double?, components: ComponentScores, notes: [String]) {
    guard hardGatesPassed, let actualPayload else {
        return (
            status: "FAIL",
            score: nil,
            threshold: nil,
            components: ComponentScores(description: nil, itemExtraction: nil, categoryQuality: nil, servingQuality: nil),
            notes: ["Hard-gate failure blocks weighted scoring."]
        )
    }

    let expected = evalCase.expected
    let descriptionRatio = descriptionQuality(actual: actualPayload.description, expectation: expected?.description)
    let itemRatio = itemExtractionQuality(actual: actualPayload.foodItems, expected: expected?.foodItems)
    let categoryRatio = categoryQuality(actual: actualPayload.foodItems, expected: expected?.foodItems)
    let servingRatio = servingQuality(
        actual: actualPayload.foodItems,
        expected: expected?.foodItems,
        tolerance: expected?.servingsTolerance ?? 0.5
    )

    let weights: [(Double, Double?)] = [
        (20, descriptionRatio),
        (40, itemRatio),
        (30, categoryRatio),
        (10, servingRatio)
    ]

    let enabledWeight = weights.reduce(0.0) { partial, item in
        item.1 == nil ? partial : partial + item.0
    }
    let weightedSum = weights.reduce(0.0) { partial, item in
        guard let ratio = item.1 else { return partial }
        return partial + (item.0 * ratio)
    }

    let normalizedScore = enabledWeight > 0 ? (weightedSum / enabledWeight) * 100 : nil
    let roundedScore = normalizedScore.map { ($0 * 100).rounded() / 100 }
    let threshold = expected?.passThreshold ?? 75
    let status: String
    if let roundedScore {
        status = roundedScore >= threshold ? "PASS" : "WARN"
    } else {
        status = "WARN"
    }

    var notes: [String] = []
    if expected?.foodItems == nil {
        notes.append("Expected food_items omitted; extraction/category/serving components were skipped.")
    }

    return (
        status: status,
        score: roundedScore,
        threshold: threshold,
        components: ComponentScores(
            description: (descriptionRatio * 100).rounded() / 100,
            itemExtraction: itemRatio.map { ($0 * 100).rounded() / 100 },
            categoryQuality: categoryRatio.map { ($0 * 100).rounded() / 100 },
            servingQuality: servingRatio.map { ($0 * 100).rounded() / 100 }
        ),
        notes: notes
    )
}

private func descriptionQuality(actual: String, expectation: DescriptionExpectation?) -> Double {
    let trimmed = actual.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }

    let minSentences = expectation?.minSentences ?? 1
    let maxSentences = expectation?.maxSentences ?? 3
    let mustContain = expectation?.mustContain ?? []

    let sentenceCount = countSentences(in: trimmed)
    let sentenceScore = (minSentences...maxSentences).contains(sentenceCount) ? 1.0 : 0.5

    guard !mustContain.isEmpty else {
        return sentenceScore
    }

    let lower = trimmed.lowercased()
    let matched = mustContain.filter { lower.contains($0.lowercased()) }.count
    let coverage = Double(matched) / Double(mustContain.count)
    return (sentenceScore * 0.5) + (coverage * 0.5)
}

private func itemExtractionQuality(actual: [FoodAnalysisItem], expected: [ExpectedFoodItem]?) -> Double? {
    guard let expected else { return nil }

    let predicted = Set(actual.map { normalizeName($0.name) })
    let wanted = Set(expected.map { normalizeName($0.name) })

    if wanted.isEmpty && predicted.isEmpty {
        return 1
    }

    let overlap = predicted.intersection(wanted).count
    let precision = predicted.isEmpty ? 0 : Double(overlap) / Double(predicted.count)
    let recall = wanted.isEmpty ? 0 : Double(overlap) / Double(wanted.count)

    if precision + recall == 0 {
        return 0
    }
    return (2 * precision * recall) / (precision + recall)
}

private func categoryQuality(actual: [FoodAnalysisItem], expected: [ExpectedFoodItem]?) -> Double? {
    guard let expected else { return nil }
    if expected.isEmpty {
        return actual.isEmpty ? 1 : 0
    }

    let actualByName = Dictionary(uniqueKeysWithValues: actual.map { (normalizeName($0.name), $0) })
    let scores = expected.map { expectedItem -> Double in
        let key = normalizeName(expectedItem.name)
        guard let actualItem = actualByName[key] else {
            return 0
        }

        let expectedCategories = Set(expectedItem.categories)
        let actualCategories = Set(actualItem.categories)
        if expectedCategories.isEmpty && actualCategories.isEmpty {
            return 1
        }

        let overlap = expectedCategories.intersection(actualCategories).count
        let precision = actualCategories.isEmpty ? 0 : Double(overlap) / Double(actualCategories.count)
        let recall = expectedCategories.isEmpty ? 0 : Double(overlap) / Double(expectedCategories.count)
        if precision + recall == 0 {
            return 0
        }
        return (2 * precision * recall) / (precision + recall)
    }

    let total = scores.reduce(0, +)
    return total / Double(scores.count)
}

private func servingQuality(actual: [FoodAnalysisItem], expected: [ExpectedFoodItem]?, tolerance: Double) -> Double? {
    guard let expected else { return nil }
    if expected.isEmpty {
        return actual.isEmpty ? 1 : 0
    }

    let actualByName = Dictionary(uniqueKeysWithValues: actual.map { (normalizeName($0.name), $0) })
    let matches = expected.map { expectedItem -> Double in
        let key = normalizeName(expectedItem.name)
        guard let actualItem = actualByName[key] else {
            return 0
        }
        return abs(actualItem.servings - expectedItem.servings) <= tolerance ? 1 : 0
    }

    let total = matches.reduce(0, +)
    return total / Double(matches.count)
}

private func countSentences(in text: String) -> Int {
    let separators = CharacterSet(charactersIn: ".!?")
    let parts = text.components(separatedBy: separators)
    return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
}

private func normalizeName(_ name: String) -> String {
    let lowered = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let punctuation = CharacterSet.alphanumerics.inverted
    let words = lowered.components(separatedBy: punctuation).filter { !$0.isEmpty }
    return words.joined(separator: " ")
}

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
        let expectedItemKeys: Set<String> = ["name", "categories", "servings"]
        guard Set(item.keys) == expectedItemKeys else {
            return false
        }

        guard let name = item["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let categories = item["categories"] as? [String],
              !categories.isEmpty,
              let servings = item["servings"] as? Double,
              servings > 0 else {
            return false
        }

        for category in categories where !allowedCategories.contains(category) {
            return false
        }
    }

    return true
}

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
    print("Status: \(result.status)")
    if let score = result.score, let threshold = result.threshold {
        print("Score: \(score) / 100 (threshold \(threshold))")
    }
    print("Hard gates: http2xx=\(result.hardGates.http2xx) topLevelDecoded=\(result.hardGates.topLevelDecoded) contentJSONParsed=\(result.hardGates.contentJSONParsed) schemaConformant=\(result.hardGates.schemaConformant)")
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
