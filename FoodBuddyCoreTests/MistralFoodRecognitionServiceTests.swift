import Foundation
import XCTest

final class MistralFoodRecognitionServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testAnalyzeBuildsExpectedRequestJSONWithFoodSchema() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        var capturedRequest: URLRequest?
        URLProtocolStub.requestHandler = { request in
            capturedRequest = request
            let body = #"{"choices":[{"message":{"content":"{\"description\":\"Grilled salmon with rice\",\"food_items\":[{\"name\":\"Salmon\",\"categories\":[\"lean_meats_and_fish\"],\"servings\":1}]}"}}]}"#
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let firstImage = Data("first".utf8)
        let secondImage = Data("second".utf8)
        _ = try await service.analyze(images: [firstImage, secondImage], notes: "with lemon")

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let bodyData = try XCTUnwrap(extractBodyData(from: request))
        let bodyObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(bodyObject["model"] as? String, "mistral-large-latest")

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
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        var capturedRequest: URLRequest?
        URLProtocolStub.requestHandler = { request in
            capturedRequest = request
            let body = #"{"choices":[{"message":{"content":"{\"description\":\"Oatmeal with berries\",\"food_items\":[{\"name\":\"Oatmeal\",\"categories\":[\"whole_grains\"],\"servings\":1}]}"}}]}"#
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        _ = try await service.analyze(images: [], notes: "oatmeal with blueberries")

        let request = try XCTUnwrap(capturedRequest)
        let bodyData = try XCTUnwrap(extractBodyData(from: request))
        let bodyObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])

        XCTAssertEqual(userContent.count, 1)
        XCTAssertEqual(userContent[0]["type"] as? String, "text")
        XCTAssertEqual(userContent[0]["text"] as? String, "Meal note: oatmeal with blueberries")
    }

    func testAnalyzeParsesDescriptionAndFoodItems() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        URLProtocolStub.requestHandler = { request in
            let body = #"{"choices":[{"message":{"content":"{\"description\":\"Grilled salmon with rice\",\"food_items\":[{\"name\":\"Salmon\",\"categories\":[\"lean_meats_and_fish\"],\"servings\":1.0},{\"name\":\"Ice cream\",\"categories\":[\"dairy\",\"sweets\"],\"servings\":0.5}]}"}}]}"#
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.description, "Grilled salmon with rice")
        XCTAssertEqual(result.foodItems.count, 2)
        XCTAssertEqual(result.foodItems[0].categories, ["lean_meats_and_fish"])
        XCTAssertEqual(result.foodItems[1].categories, ["dairy", "sweets"])
    }

    func testAnalyzeHandlesEmptyFoodItems() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        URLProtocolStub.requestHandler = { request in
            let body = #"{"choices":[{"message":{"content":"{\"description\":\"Black coffee\",\"food_items\":[]}"}}]}"#
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.description, "Black coffee")
        XCTAssertEqual(result.foodItems, [])
    }

    func testAnalyzeSkipsItemsWithUnknownCategoryStrings() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        URLProtocolStub.requestHandler = { request in
            let body = #"{"choices":[{"message":{"content":"{\"description\":\"Snack\",\"food_items\":[{\"name\":\"Unknown\",\"categories\":[\"not_real\"],\"servings\":1},{\"name\":\"Apple\",\"categories\":[\"fruits\",\"not_real\"],\"servings\":1}]}"}}]}"#
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let result = try await service.analyze(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(result.foodItems.count, 1)
        XCTAssertEqual(result.foodItems.first?.name, "Apple")
        XCTAssertEqual(result.foodItems.first?.categories, ["fruits"])
    }

    func testDescribeDelegatesToAnalyze() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        URLProtocolStub.requestHandler = { request in
            let body = #"{"choices":[{"message":{"content":"{\"description\":\"Toast and eggs\",\"food_items\":[]}"}}]}"#
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let description = try await service.describe(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(description, "Toast and eggs")
    }

    func testAnalyzeDefensiveParsingFailuresThrowDecodingError() async throws {
        let failingBodies = [
            #"{"choices":[]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#,
            #"{"choices":[{"message":{"content":"not-json"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"x\"}"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"   \",\"food_items\":[]}"}}]}"#
        ]

        for body in failingBodies {
            let session = makeMockedSession()
            let service = MistralFoodRecognitionService(
                apiKeyStore: StaticAPIKeyStore(key: "test-key"),
                urlSession: session
            )

            URLProtocolStub.requestHandler = { request in
                try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
            }

            do {
                _ = try await service.analyze(images: [Data("image".utf8)], notes: nil)
                XCTFail("Expected decoding error")
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

    func testAnalyzeWithoutAPIKeyThrowsNoAPIKey() async {
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: nil),
            urlSession: makeMockedSession()
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
            urlSession: makeMockedSession()
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

    private func assertHTTPError(statusCode: Int) async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        URLProtocolStub.requestHandler = { request in
            try self.makeHTTPResponse(statusCode: statusCode, request: request, body: #"{"error":"x"}"#)
        }

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

    private func makeMockedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeHTTPResponse(
        statusCode: Int,
        request: URLRequest,
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(body.utf8))
    }

    private func extractBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }
}

private struct StaticAPIKeyStore: MistralAPIKeyStoring {
    let key: String?

    func apiKey() throws -> String? {
        key
    }

    func setAPIKey(_ key: String?) throws {}
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = URLProtocolStub.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
