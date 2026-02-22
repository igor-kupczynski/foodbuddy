import Foundation
import FoodBuddyAIShared
import XCTest

final class MistralFoodRecognitionServiceTests: XCTestCase {

    func testAnalyzeBuildsExpectedRequestJSONWithFoodSchema() async throws {
        let mock = MockHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"description\":\"Grilled salmon with rice\",\"food_items\":[{\"name\":\"Salmon\",\"category\":\"lean_meats_and_fish\",\"servings\":1}]}"}}]}"#
        )
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let firstImage = Data("first".utf8)
        let secondImage = Data("second".utf8)
        _ = try await service.analyze(images: [firstImage, secondImage], notes: "with lemon")

        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.url, "https://api.mistral.ai/v1/chat/completions")
        XCTAssertEqual(request.header(named: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.header(named: "Accept"), "text/event-stream")

        let bodyObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(bodyObject["model"] as? String, "mistral-large-latest")
        XCTAssertEqual(bodyObject["stream"] as? Bool, true)
        XCTAssertEqual(bodyObject["max_tokens"] as? Int, 400)

        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)

        let systemContent = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(systemContent.contains("Return two things:"))
        XCTAssertTrue(systemContent.contains("DOUBLE-COUNTING"))

        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.count, 3)
        XCTAssertEqual(userContent[2]["text"] as? String, "Additional context: with lemon")

        let responseFormat = try XCTUnwrap(bodyObject["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")

        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "food_analysis")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)

        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["description"])
        XCTAssertNotNil(properties["food_items"])
    }

    func testAnalyzeBuildsNotesOnlyRequestPayload() async throws {
        let mock = MockHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"description\":\"Oatmeal with berries\",\"food_items\":[{\"name\":\"Oatmeal\",\"category\":\"whole_grains\",\"servings\":1}]}"}}]}"#
        )
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        _ = try await service.analyze(images: [], notes: "oatmeal with blueberries")

        let request = try XCTUnwrap(mock.requests.first)
        let bodyObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])

        XCTAssertEqual(userContent.count, 1)
        XCTAssertEqual(userContent[0]["type"] as? String, "text")
        XCTAssertEqual(userContent[0]["text"] as? String, "Meal note: oatmeal with blueberries")
    }

    func testAnalyzeParsesDescriptionAndFoodItems() async throws {
        let mock = MockHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"description\":\"Grilled salmon with rice\",\"food_items\":[{\"name\":\"Salmon\",\"category\":\"lean_meats_and_fish\",\"servings\":1.0},{\"name\":\"Ice cream\",\"category\":\"dairy\",\"servings\":0.5}]}"}}]}"#
        )
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.description, "Grilled salmon with rice")
        XCTAssertEqual(result.foodItems.count, 2)
        XCTAssertEqual(result.foodItems[0].category, "lean_meats_and_fish")
        XCTAssertEqual(result.foodItems[1].category, "dairy")
    }

    func testAnalyzeParsesStreamingSSEPayload() async throws {
        let content = #"{"description":"Grilled salmon with rice","food_items":[{"name":"Salmon","category":"lean_meats_and_fish","servings":1.0}]}"#
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let chunk = #"{"choices":[{"delta":{"content":"\#(escapedContent)"}}]}"#
        let body = [
            "data: \(chunk)",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")

        let mock = MockHTTPTransport(statusCode: 200, body: body)
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.description, "Grilled salmon with rice")
        XCTAssertEqual(result.foodItems.count, 1)
        XCTAssertEqual(result.foodItems[0].name, "Salmon")
        XCTAssertEqual(result.foodItems[0].category, "lean_meats_and_fish")
    }

    func testAnalyzeHandlesEmptyFoodItems() async throws {
        let mock = MockHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"description\":\"Black coffee\",\"food_items\":[]}"}}]}"#
        )
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.description, "Black coffee")
        XCTAssertEqual(result.foodItems, [])
    }

    func testAnalyzeSkipsItemsWithUnknownCategoryStrings() async throws {
        let mock = MockHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"description\":\"Snack\",\"food_items\":[{\"name\":\"Unknown\",\"category\":\"not_real\",\"servings\":1},{\"name\":\"Apple\",\"category\":\"fruits\",\"servings\":1}]}"}}]}"#
        )
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.foodItems.count, 1)
        XCTAssertEqual(result.foodItems.first?.name, "Apple")
        XCTAssertEqual(result.foodItems.first?.category, "fruits")
    }

    func testDescribeDelegatesToAnalyze() async throws {
        let mock = MockHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"{\"description\":\"Toast and eggs\",\"food_items\":[]}"}}]}"#
        )
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let description = try await service.describe(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(description, "Toast and eggs")
    }

    func testAnalyzeDefensiveParsingFailuresThrowDecodingError() async throws {
        let failingBodies = [
            #"{"choices":[]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#,
            #"{"choices":[{"message":{"content":"not-json"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"x\"}"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"   \",\"food_items\":[]}"}}]}"#,
        ]

        for body in failingBodies {
            let mock = MockHTTPTransport(statusCode: 200, body: body)
            let service = MistralFoodRecognitionService(
                apiKeyStore: StaticAPIKeyStore(key: "test-key"),
                transport: mock
            )

            do {
                _ = try await service.analyze(images: [Data("image".utf8)], notes: nil)
                XCTFail("Expected decoding error for body: \(body)")
            } catch let error as FoodRecognitionServiceError {
                XCTAssertEqual(error, .decodingError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAnalyzeHTTPErrorMapping() async throws {
        try await assertHTTPError(statusCode: 401)
        try await assertHTTPError(statusCode: 500)
    }

    func testAnalyzeRetriesTransientHTTPAndThenSucceeds() async throws {
        let mock = MockHTTPTransport()
        var attemptCount = 0
        mock.handler = {
            attemptCount += 1
            if attemptCount == 1 {
                return (502, #"{"error":"temporary"}"#)
            }
            return (200, #"{"choices":[{"message":{"content":"{\"description\":\"Retry recovered\",\"food_items\":[]}"}}]}"#)
        }
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.description, "Retry recovered")
        XCTAssertEqual(result.foodItems.count, 0)
        XCTAssertEqual(mock.requests.count, 2)
    }

    func testAnalyzeWithoutAPIKeyThrowsNoAPIKey() async {
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: nil),
            transport: MockHTTPTransport()
        )

        do {
            _ = try await service.analyze(images: [Data("image".utf8)], notes: nil)
            XCTFail("Expected noAPIKey error")
        } catch let error as FoodRecognitionServiceError {
            XCTAssertEqual(error, .noAPIKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnalyzeWithoutImagesAndNotesThrowsDecodingError() async {
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: MockHTTPTransport()
        )

        do {
            _ = try await service.analyze(images: [], notes: nil)
            XCTFail("Expected decodingError")
        } catch let error as FoodRecognitionServiceError {
            XCTAssertEqual(error, .decodingError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSharedCategoryIdentifiersMatchDQSCategoryIdentifiers() {
        let shared = Set(FoodAnalysisCategories.all)
        let app = Set(DQSCategory.allCases.map(\.apiIdentifier))

        XCTAssertEqual(shared, app)
        XCTAssertEqual(FoodAnalysisCategories.all.count, app.count)
    }

    // MARK: - Helpers

    private func assertHTTPError(statusCode: Int) async throws {
        let mock = MockHTTPTransport(statusCode: statusCode, body: #"{"error":"x"}"#)
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            transport: mock
        )

        do {
            _ = try await service.analyze(images: [Data("image".utf8)], notes: nil)
            XCTFail("Expected httpError")
        } catch let error as FoodRecognitionServiceError {
            switch error {
            case .httpError(let code, let body):
                XCTAssertEqual(code, statusCode)
                XCTAssertNotNil(body)
            default:
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test doubles

private struct StaticAPIKeyStore: MistralAPIKeyStoring {
    let key: String?

    func apiKey() throws -> String? {
        key
    }

    func setAPIKey(_ key: String?) throws {}
}

/// Simple mock that captures request parameters and returns canned responses.
/// Replaces URLProtocolStub — no global state, no URLSession configuration.
private final class MockHTTPTransport: MistralHTTPTransport, @unchecked Sendable {
    struct CapturedRequest {
        let url: String
        let headers: [(name: String, value: String)]
        let body: Data

        func header(named name: String) -> String? {
            headers.first(where: { $0.name == name })?.value
        }
    }

    private(set) var requests: [CapturedRequest] = []
    var handler: () -> (statusCode: Int, body: String)

    init(statusCode: Int = 200, body: String = "") {
        self.handler = { (statusCode, body) }
    }

    func streamingPOST(
        url: String,
        headers: [(name: String, value: String)],
        body: Data,
        timeoutSeconds: TimeInterval
    ) async throws -> (statusCode: Int, bodyLines: AsyncThrowingStream<String, Error>) {
        requests.append(CapturedRequest(url: url, headers: headers, body: body))
        let (statusCode, responseBody) = handler()
        let lines = responseBody.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (statusCode, stream)
    }
}
