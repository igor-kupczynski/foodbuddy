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

    struct GuideContent: Sendable {
        let servingGuide: String
        let examples: [String]
    }

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

    var guideContent: GuideContent {
        switch self {
        case .fruits:
            return GuideContent(
                servingGuide: "1 medium piece, a big handful of berries, or 1 glass of 100% juice.",
                examples: ["Apples", "Bananas", "Berries", "Oranges", "100% orange juice"]
            )
        case .vegetables:
            return GuideContent(
                servingGuide: "1 fist-sized portion, 1/2 cup vegetable sauce, or a bowl of salad/soup.",
                examples: ["Leafy greens", "Broccoli", "Carrots", "Tomatoes", "Vegetable soup"]
            )
        case .leanMeatsAndFish:
            return GuideContent(
                servingGuide: "1 palm-sized portion.",
                examples: ["Chicken breast", "Turkey", "White fish", "Salmon", "Eggs"]
            )
        case .legumesAndPlantProteins:
            return GuideContent(
                servingGuide: "About 1/2-1 cup cooked or one palm-sized protein portion.",
                examples: ["Beans", "Lentils", "Chickpeas", "Tofu", "Tempeh"]
            )
        case .nutsAndSeeds:
            return GuideContent(
                servingGuide: "A palmful or 1 heaping tablespoon nut/seed butter.",
                examples: ["Almonds", "Walnuts", "Peanuts", "Chia seeds", "Natural peanut butter"]
            )
        case .wholeGrains:
            return GuideContent(
                servingGuide: "1 fist-sized portion of cooked grains, 1 bowl of whole-grain cereal/pasta, or 2 slices whole-grain bread.",
                examples: ["Brown rice", "Oats", "Quinoa", "100% whole-grain bread", "Whole-wheat pasta"]
            )
        case .dairy:
            return GuideContent(
                servingGuide: "1 glass of milk, 2 slices of cheese, or 1 yogurt tub.",
                examples: ["Milk", "Greek yogurt", "Cheddar cheese", "Cottage cheese", "Kefir"]
            )
        case .refinedGrains:
            return GuideContent(
                servingGuide: "Use the same portion references as grains (fist-sized cooked, bowl, or 2 slices bread).",
                examples: ["White rice", "White bread", "Regular pasta", "Sugary cereals", "Pastries"]
            )
        case .sweets:
            return GuideContent(
                servingGuide: "Treat one small dessert/drink portion as 1 serving.",
                examples: ["Candy", "Cake", "Sweetened soda", "Ice cream", "Sweetened yogurt"]
            )
        case .friedFoods:
            return GuideContent(
                servingGuide: "One side-sized serving (for example a small basket or handful).",
                examples: ["French fries", "Fried chicken", "Fried snacks", "Potato chips", "Tempura"]
            )
        case .fattyProteins:
            return GuideContent(
                servingGuide: "1 palm-sized portion.",
                examples: ["Bacon", "Sausage", "Pepperoni", "Marbled steak", "Processed deli meats"]
            )
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
