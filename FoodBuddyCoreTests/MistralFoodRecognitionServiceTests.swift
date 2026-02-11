import Foundation
import XCTest

final class MistralFoodRecognitionServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testDescribeBuildsExpectedRequestJSON() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        var capturedRequest: URLRequest?
        URLProtocolStub.requestHandler = { request in
            capturedRequest = request
            let body = """
            {"choices":[{"message":{"content":"{\\"description\\":\\"Grilled salmon with rice\\"}"}}]}
            """
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let firstImage = Data("first".utf8)
        let secondImage = Data("second".utf8)
        _ = try await service.describe(images: [firstImage, secondImage], notes: "with lemon")

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let bodyData = try XCTUnwrap(extractBodyData(from: request))
        let bodyObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(bodyObject["model"] as? String, "mistral-large-latest")

        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "user")

        let systemContent = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(systemContent.contains("food-logging assistant"))

        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.count, 3)
        XCTAssertEqual(userContent[0]["type"] as? String, "image_url")
        XCTAssertEqual(userContent[1]["type"] as? String, "image_url")
        XCTAssertEqual(userContent[2]["type"] as? String, "text")
        XCTAssertEqual(userContent[2]["text"] as? String, "Additional context: with lemon")

        let responseFormat = try XCTUnwrap(bodyObject["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
    }

    func testDescribeParsesValidResponseDescription() async throws {
        let session = makeMockedSession()
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: "test-key"),
            urlSession: session
        )

        URLProtocolStub.requestHandler = { request in
            let body = """
            {"choices":[{"message":{"content":"{\\"description\\":\\"Grilled salmon with rice\\"}"}}]}
            """
            return try self.makeHTTPResponse(statusCode: 200, request: request, body: body)
        }

        let description = try await service.describe(images: [Data("image".utf8)], notes: nil)
        XCTAssertEqual(description, "Grilled salmon with rice")
    }

    func testDescribeDefensiveParsingFailuresThrowDecodingError() async throws {
        let failingBodies = [
            #"{"choices":[]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#,
            #"{"choices":[{"message":{"content":"not-json"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"notDescription\":\"x\"}"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"   \"}"}}]}"#
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
                _ = try await service.describe(images: [Data("image".utf8)], notes: nil)
                XCTFail("Expected decoding error")
            } catch let error as FoodRecognitionServiceError {
                XCTAssertEqual(error, .decodingError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDescribeHTTPErrorMapping() async throws {
        try await assertHTTPError(statusCode: 401)
        try await assertHTTPError(statusCode: 500)
    }

    func testDescribeWithoutAPIKeyThrowsNoAPIKey() async {
        let service = MistralFoodRecognitionService(
            apiKeyStore: StaticAPIKeyStore(key: nil),
            urlSession: makeMockedSession()
        )

        do {
            _ = try await service.describe(images: [Data("image".utf8)], notes: nil)
            XCTFail("Expected noAPIKey error")
        } catch let error as FoodRecognitionServiceError {
            XCTAssertEqual(error, .noAPIKey)
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
            _ = try await service.describe(images: [Data("image".utf8)], notes: nil)
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
