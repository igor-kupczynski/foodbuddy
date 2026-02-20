import Foundation
import XCTest
@testable import FoodBuddyAIShared

final class FoodAnalysisResponseParserTests: XCTestCase {
    func testParseResponseDataParsesValidPayload() throws {
        let data = Data(
            #"{"choices":[{"message":{"content":"{\"description\":\"Grilled salmon with rice\",\"food_items\":[{\"name\":\"Salmon\",\"categories\":[\"lean_meats_and_fish\"],\"servings\":1.0}]}"}}]}"#
                .utf8
        )

        let result = try FoodAnalysisResponseParser.parseResponseData(data)
        XCTAssertEqual(result.payload.description, "Grilled salmon with rice")
        XCTAssertEqual(result.payload.foodItems.count, 1)
        XCTAssertEqual(result.payload.foodItems.first?.name, "Salmon")
    }

    func testParseResponseDataRejectsMalformedPayloads() throws {
        let bodies = [
            #"{"choices":[]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#,
            #"{"choices":[{"message":{"content":"not-json"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"x\"}"}}]}"#,
            #"{"choices":[{"message":{"content":"{\"description\":\"   \",\"food_items\":[]}"}}]}"#
        ]

        for body in bodies {
            XCTAssertThrowsError(try FoodAnalysisResponseParser.parseResponseData(Data(body.utf8))) { error in
                XCTAssertEqual(error as? FoodBuddyAISharedError, .decodingError)
            }
        }
    }
}
