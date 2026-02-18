import Foundation

enum DQSCategory: String, Codable, CaseIterable, Sendable {
    case fruits
    case vegetables
    case leanMeatsAndFish
    case legumesAndPlantProteins
    case nutsAndSeeds
    case wholeGrains
    case dairy
    case refinedGrains
    case sweets
    case friedFoods
    case fattyProteins

    var displayName: String {
        switch self {
        case .fruits:
            return "Fruits"
        case .vegetables:
            return "Vegetables"
        case .leanMeatsAndFish:
            return "Lean Meats & Fish"
        case .legumesAndPlantProteins:
            return "Legumes & Plant Proteins"
        case .nutsAndSeeds:
            return "Nuts & Seeds"
        case .wholeGrains:
            return "Whole Grains"
        case .dairy:
            return "Dairy"
        case .refinedGrains:
            return "Refined Grains"
        case .sweets:
            return "Sweets"
        case .friedFoods:
            return "Fried Foods"
        case .fattyProteins:
            return "Fatty Proteins"
        }
    }

    var isHighQuality: Bool {
        switch self {
        case .fruits, .vegetables, .leanMeatsAndFish, .legumesAndPlantProteins, .nutsAndSeeds, .wholeGrains, .dairy:
            return true
        case .refinedGrains, .sweets, .friedFoods, .fattyProteins:
            return false
        }
    }

    var apiIdentifier: String {
        switch self {
        case .fruits:
            return "fruits"
        case .vegetables:
            return "vegetables"
        case .leanMeatsAndFish:
            return "lean_meats_and_fish"
        case .legumesAndPlantProteins:
            return "legumes_and_plant_proteins"
        case .nutsAndSeeds:
            return "nuts_and_seeds"
        case .wholeGrains:
            return "whole_grains"
        case .dairy:
            return "dairy"
        case .refinedGrains:
            return "refined_grains"
        case .sweets:
            return "sweets"
        case .friedFoods:
            return "fried_foods"
        case .fattyProteins:
            return "fatty_proteins"
        }
    }

    init?(apiIdentifier: String) {
        switch apiIdentifier {
        case "fruits":
            self = .fruits
        case "vegetables":
            self = .vegetables
        case "lean_meats_and_fish":
            self = .leanMeatsAndFish
        case "legumes_and_plant_proteins":
            self = .legumesAndPlantProteins
        case "nuts_and_seeds":
            self = .nutsAndSeeds
        case "whole_grains":
            self = .wholeGrains
        case "dairy":
            self = .dairy
        case "refined_grains":
            self = .refinedGrains
        case "sweets":
            self = .sweets
        case "fried_foods":
            self = .friedFoods
        case "fatty_proteins":
            self = .fattyProteins
        default:
            return nil
        }
    }
}
