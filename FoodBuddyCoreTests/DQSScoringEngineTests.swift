import XCTest

final class DQSScoringEngineTests: XCTestCase {
    private let engine = DQSScoringEngine()

    func testPointsForServingsBoundariesForAllCategories() {
        let expectations: [DQSCategory: (zero: Int, one: Int, three: Int, five: Int, six: Int)] = [
            .fruits: (0, 2, 6, 7, 7),
            .vegetables: (0, 2, 6, 7, 7),
            .leanMeatsAndFish: (0, 2, 5, 5, 4),
            .legumesAndPlantProteins: (0, 2, 5, 5, 4),
            .nutsAndSeeds: (0, 2, 5, 5, 4),
            .wholeGrains: (0, 2, 5, 5, 4),
            .dairy: (0, 1, 3, 2, 0),
            .refinedGrains: (0, -1, -4, -8, -10),
            .sweets: (0, -2, -6, -10, -12),
            .friedFoods: (0, -2, -6, -10, -12),
            .fattyProteins: (0, -1, -4, -8, -10)
        ]

        XCTAssertEqual(expectations.count, DQSCategory.allCases.count)

        for category in DQSCategory.allCases {
            guard let expected = expectations[category] else {
                XCTFail("Missing expectation for \(category)")
                continue
            }

            XCTAssertEqual(engine.pointsForServings(category: category, servings: 0), expected.zero)
            XCTAssertEqual(engine.pointsForServings(category: category, servings: 1), expected.one)
            XCTAssertEqual(engine.pointsForServings(category: category, servings: 3), expected.three)
            XCTAssertEqual(engine.pointsForServings(category: category, servings: 5), expected.five)
            XCTAssertEqual(engine.pointsForServings(category: category, servings: 6), expected.six)
        }
    }

    func testScoreEmptyInputReturnsZeroAndAllCategories() {
        let date = Date(timeIntervalSince1970: 123)
        let score = engine.score(for: date, foodItems: [])

        XCTAssertEqual(score.date, date)
        XCTAssertEqual(score.totalScore, 0)
        XCTAssertEqual(score.interpretation, "Below average")
        XCTAssertEqual(score.categoryBreakdowns.count, DQSCategory.allCases.count)
        XCTAssertTrue(score.categoryBreakdowns.allSatisfy { $0.servings == 0 && $0.points == 0 })
    }

    func testScoreAggregatesServingsAcrossItemsAndCategories() {
        let date = Date(timeIntervalSince1970: 1000)
        let mealID = UUID()

        let items = [
            FoodItem(mealId: mealID, name: "Apple", categoryRawValue: DQSCategory.fruits.rawValue, servings: 1),
            FoodItem(mealId: mealID, name: "Orange", categoryRawValue: DQSCategory.fruits.rawValue, servings: 1),
            FoodItem(mealId: mealID, name: "Rice", categoryRawValue: DQSCategory.wholeGrains.rawValue, servings: 2),
            FoodItem(mealId: mealID, name: "Soda", categoryRawValue: DQSCategory.sweets.rawValue, servings: 1)
        ]

        let score = engine.score(for: date, foodItems: items)
        XCTAssertEqual(score.totalScore, 6)

        XCTAssertEqual(points(for: .fruits, in: score), 4)
        XCTAssertEqual(points(for: .wholeGrains, in: score), 4)
        XCTAssertEqual(points(for: .sweets, in: score), -2)
        XCTAssertEqual(servings(for: .fruits, in: score), 2)
    }

    func testPointsForServingsUsesHalfAwayFromZeroRounding() {
        XCTAssertEqual(engine.pointsForServings(category: .dairy, servings: 0.49), 0)
        XCTAssertEqual(engine.pointsForServings(category: .dairy, servings: 0.5), 1)
        XCTAssertEqual(engine.pointsForServings(category: .dairy, servings: 1.5), 2)
        XCTAssertEqual(engine.pointsForServings(category: .dairy, servings: 2.5), 3)
        XCTAssertEqual(engine.pointsForServings(category: .sweets, servings: 1.5), -4)
    }

    private func points(for category: DQSCategory, in score: DQSScoringEngine.DailyScore) -> Int {
        score.categoryBreakdowns.first(where: { $0.category == category })?.points ?? 0
    }

    private func servings(for category: DQSCategory, in score: DQSScoringEngine.DailyScore) -> Double {
        score.categoryBreakdowns.first(where: { $0.category == category })?.servings ?? 0
    }
}
