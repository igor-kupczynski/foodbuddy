import Foundation
import XCTest
@testable import FoodBuddyAIShared

final class FoodAnalysisRequestFactoryTests: XCTestCase {
    func testMakeJSONDataBuildsExpectedPayload() throws {
        let data = try FoodAnalysisRequestFactory.makeJSONData(
            model: "mistral-large-latest",
            images: [Data("first".utf8), Data("second".utf8)],
            notes: "with lemon",
            categoryIdentifiers: ["fruits", "vegetables"]
        )

        let bodyObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(bodyObject["model"] as? String, "mistral-large-latest")

        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)

        let systemContent = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(systemContent.contains("Return two things:"))
        XCTAssertTrue(systemContent.contains("DOUBLE-COUNTING"))
        XCTAssertTrue(systemContent.contains("thin layer of jam"))
        XCTAssertTrue(systemContent.contains("do NOT add a separate sweets item"))

        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.count, 3)
        XCTAssertEqual(userContent[2]["text"] as? String, "Additional context: with lemon")

        let responseFormat = try XCTUnwrap(bodyObject["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "food_analysis")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
    }

    func testMakeJSONDataBuildsNotesOnlyPayload() throws {
        let data = try FoodAnalysisRequestFactory.makeJSONData(
            model: "mistral-large-latest",
            images: [],
            notes: "oatmeal with blueberries",
            categoryIdentifiers: ["whole_grains"]
        )

        let bodyObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.count, 1)
        XCTAssertEqual(userContent[0]["type"] as? String, "text")
        XCTAssertEqual(userContent[0]["text"] as? String, "Meal note: oatmeal with blueberries")
    }

    func testMakeJSONDataRejectsEmptyInput() throws {
        XCTAssertThrowsError(
            try FoodAnalysisRequestFactory.makeJSONData(
                model: "mistral-large-latest",
                images: [],
                notes: "   ",
                categoryIdentifiers: ["fruits"]
            )
        ) { error in
            XCTAssertEqual(error as? FoodBuddyAISharedError, .emptyInput)
        }
    }

    func testMakeJSONDataSupportsStreamingAndMaxTokens() throws {
        let data = try FoodAnalysisRequestFactory.makeJSONData(
            model: "mistral-large-latest",
            images: [Data("first".utf8)],
            notes: nil,
            categoryIdentifiers: ["fruits"],
            stream: true,
            maxTokens: 512
        )

        let bodyObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(bodyObject["stream"] as? Bool, true)
        XCTAssertEqual(bodyObject["max_tokens"] as? Int, 512)
    }
}
