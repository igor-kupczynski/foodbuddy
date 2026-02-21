import XCTest
@testable import FoodBuddyAIShared

final class MistralStreamParserTests: XCTestCase {
    func testAccumulatorParsesStringContentChunksAndUsage() throws {
        var accumulator = MistralStreamAccumulator()

        try accumulator.consume(line: #"data: {"choices":[{"delta":{"content":"{"}}]}"#)
        try accumulator.consume(line: "")
        try accumulator.consume(line: #"data: {"choices":[{"delta":{"content":"\"description\":\"Soup\",\"food_items\":[]}"}}]}"#)
        try accumulator.consume(line: "")
        try accumulator.consume(line: #"data: {"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#)
        try accumulator.consume(line: "")
        try accumulator.consume(line: "data: [DONE]")
        try accumulator.consume(line: "")

        let result = try accumulator.finish()
        XCTAssertEqual(result.assistantContent, #"{"description":"Soup","food_items":[]}"#)
        XCTAssertEqual(
            result.usage,
            MistralStreamUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
        )
        XCTAssertTrue(result.receivedDone)
    }

    func testAccumulatorParsesArrayContentChunks() throws {
        var accumulator = MistralStreamAccumulator()

        try accumulator.consume(line: #"data: {"choices":[{"delta":{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world"}]}}]}"#)
        try accumulator.consume(line: "")
        try accumulator.consume(line: "data: [DONE]")
        try accumulator.consume(line: "")

        let result = try accumulator.finish()
        XCTAssertEqual(result.assistantContent, "Hello world")
    }

    func testAccumulatorRejectsMissingDone() throws {
        var accumulator = MistralStreamAccumulator()
        try accumulator.consume(line: #"data: {"choices":[{"delta":{"content":"x"}}]}"#)
        try accumulator.consume(line: "")

        XCTAssertThrowsError(try accumulator.finish()) { error in
            XCTAssertEqual(error as? MistralStreamParserError, .missingDone)
        }
    }

    func testAccumulatorSurfacesAPIError() throws {
        var accumulator = MistralStreamAccumulator()
        do {
            try accumulator.consume(line: #"data: {"error":{"message":"rate limited"}}"#)
            try accumulator.consume(line: "")
            XCTFail("Expected API error")
        } catch {
            XCTAssertEqual(error as? MistralStreamParserError, .apiError("rate limited"))
        }
    }
}
