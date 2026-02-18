import Foundation

struct DQSScoringEngine {
    struct DailyScore: Equatable {
        let date: Date
        let categoryBreakdowns: [CategoryBreakdown]
        let totalScore: Int

        var interpretation: String {
            switch totalScore {
            case ..<0:
                return "Low quality"
            case 0...10:
                return "Below average"
            case 11...20:
                return "Fairly high quality"
            case 21...29:
                return "High quality"
            default:
                return "Near-perfect"
            }
        }
    }

    struct CategoryBreakdown: Equatable {
        let category: DQSCategory
        let servings: Double
        let points: Int
    }

    func score(for date: Date, foodItems: [FoodItem]) -> DailyScore {
        var servingsByCategory: [DQSCategory: Double] = [:]

        for item in foodItems {
            servingsByCategory[item.category, default: 0] += item.servings
        }

        let breakdowns = DQSCategory.allCases.map { category in
            let servings = servingsByCategory[category, default: 0]
            return CategoryBreakdown(
                category: category,
                servings: servings,
                points: pointsForServings(category: category, servings: servings)
            )
        }

        let total = breakdowns.reduce(0) { $0 + $1.points }
        return DailyScore(date: date, categoryBreakdowns: breakdowns, totalScore: total)
    }

    func pointsForServings(category: DQSCategory, servings: Double) -> Int {
        let roundedServings = max(0, Int(servings.rounded(.toNearestOrAwayFromZero)))
        guard roundedServings > 0 else {
            return 0
        }

        let table = scoringTable(for: category)
        var total = 0

        for servingIndex in 0..<roundedServings {
            let tableIndex = min(servingIndex, table.count - 1)
            total += table[tableIndex]
        }

        return total
    }

    private func scoringTable(for category: DQSCategory) -> [Int] {
        switch category {
        case .fruits:
            return [2, 2, 2, 1, 0, 0]
        case .vegetables:
            return [2, 2, 2, 1, 0, 0]
        case .leanMeatsAndFish:
            return [2, 2, 1, 0, 0, -1]
        case .legumesAndPlantProteins:
            return [2, 2, 1, 0, 0, -1]
        case .nutsAndSeeds:
            return [2, 2, 1, 0, 0, -1]
        case .wholeGrains:
            return [2, 2, 1, 0, 0, -1]
        case .dairy:
            return [1, 1, 1, 0, -1, -2]
        case .refinedGrains:
            return [-1, -1, -2, -2, -2, -2]
        case .sweets:
            return [-2, -2, -2, -2, -2, -2]
        case .friedFoods:
            return [-2, -2, -2, -2, -2, -2]
        case .fattyProteins:
            return [-1, -1, -2, -2, -2, -2]
        }
    }
}
