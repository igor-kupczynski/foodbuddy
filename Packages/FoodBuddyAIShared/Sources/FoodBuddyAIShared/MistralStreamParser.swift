import Foundation

public struct MistralStreamUsage: Codable, Equatable, Sendable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    public init(promptTokens: Int?, completionTokens: Int?, totalTokens: Int?) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct MistralStreamParseResult: Equatable, Sendable {
    public let assistantContent: String
    public let usage: MistralStreamUsage?
    public let receivedDone: Bool

    public init(assistantContent: String, usage: MistralStreamUsage?, receivedDone: Bool) {
        self.assistantContent = assistantContent
        self.usage = usage
        self.receivedDone = receivedDone
    }
}

public enum MistralStreamParserError: LocalizedError, Equatable {
    case malformedChunk
    case missingDone
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .malformedChunk:
            return "Malformed streaming chunk."
        case .missingDone:
            return "Stream ended without a [DONE] marker."
        case .apiError(let message):
            return "API error in stream: \(message)"
        }
    }
}

public struct MistralStreamAccumulator: Sendable {
    private var pendingDataLines: [String] = []
    private var content = ""
    private var usage: MistralStreamUsage?
    private var receivedDone = false

    public init() {}

    public mutating func consume(line: String) throws {
        if line.isEmpty {
            try flushEvent()
            return
        }

        guard line.hasPrefix("data:") else {
            return
        }

        // URLSession.AsyncBytes.lines may collapse empty separator lines.
        // Flush any pending event before consuming the next data line.
        if !pendingDataLines.isEmpty {
            try flushEvent()
        }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        pendingDataLines.append(payload)
    }

    public mutating func finish() throws -> MistralStreamParseResult {
        try flushEvent()
        guard receivedDone else {
            throw MistralStreamParserError.missingDone
        }

        return MistralStreamParseResult(
            assistantContent: content,
            usage: usage,
            receivedDone: receivedDone
        )
    }

    private mutating func flushEvent() throws {
        guard !pendingDataLines.isEmpty else {
            return
        }
        defer { pendingDataLines.removeAll(keepingCapacity: true) }

        let payload = pendingDataLines.joined(separator: "\n")
        if payload == "[DONE]" {
            receivedDone = true
            return
        }

        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw MistralStreamParserError.malformedChunk
        }

        if let errorObject = root["error"] as? [String: Any] {
            let message = (errorObject["message"] as? String) ?? "Unknown API error"
            throw MistralStreamParserError.apiError(message)
        }

        if let usageObject = root["usage"] as? [String: Any] {
            usage = MistralStreamUsage(
                promptTokens: usageObject["prompt_tokens"] as? Int,
                completionTokens: usageObject["completion_tokens"] as? Int,
                totalTokens: usageObject["total_tokens"] as? Int
            )
        }

        guard let choices = root["choices"] as? [[String: Any]] else {
            return
        }

        for choice in choices {
            if let delta = choice["delta"] as? [String: Any] {
                appendContent(from: delta["content"])
                continue
            }

            if let message = choice["message"] as? [String: Any] {
                appendContent(from: message["content"])
            }
        }
    }

    private mutating func appendContent(from value: Any?) {
        switch value {
        case let text as String:
            content += text
        case let object as [String: Any]:
            if let text = object["text"] as? String {
                content += text
            }
        case let array as [Any]:
            for item in array {
                appendContent(from: item)
            }
        default:
            break
        }
    }
}
