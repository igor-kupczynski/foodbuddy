import Foundation

actor FoodAnalysisCoordinator {
    enum Error: Swift.Error {
        case missingImages
        case missingLocalImage(filename: String)
    }

    private let modelStore: FoodAnalysisModelStore
    private let imageStore: ImageStore
    private let foodRecognitionService: any FoodRecognitionService
    private let apiKeyStore: any MistralAPIKeyStoring

    init(
        modelStore: FoodAnalysisModelStore,
        imageStore: ImageStore,
        foodRecognitionService: any FoodRecognitionService,
        apiKeyStore: any MistralAPIKeyStoring
    ) {
        self.modelStore = modelStore
        self.imageStore = imageStore
        self.foodRecognitionService = foodRecognitionService
        self.apiKeyStore = apiKeyStore
    }

    func processPendingMeals() async {
        guard hasConfiguredAPIKey() else {
            return
        }

        while true {
            let pendingMeal: PendingMealAnalysis
            do {
                let claimed = try await MainActor.run(resultType: PendingMealAnalysis?.self) {
                    try modelStore.claimNextPendingMeal()
                }
                guard let claimed else {
                    return
                }
                pendingMeal = claimed
            } catch {
                return
            }

            do {
                let imageData = try loadImageData(filenames: pendingMeal.imageFilenames)
                let description = try await foodRecognitionService.describe(
                    images: imageData,
                    notes: pendingMeal.notes
                )
                try await MainActor.run {
                    try modelStore.markCompleted(mealID: pendingMeal.mealID, description: description)
                }
            } catch {
                try? await MainActor.run {
                    try modelStore.markFailed(mealID: pendingMeal.mealID)
                }
            }
        }
    }

    private func hasConfiguredAPIKey() -> Bool {
        let key = (try? apiKeyStore.apiKey())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    private func loadImageData(filenames: [String]) throws -> [Data] {
        var imageData: [Data] = []
        imageData.reserveCapacity(filenames.count)

        for filename in filenames {
            guard let data = imageStore.loadData(filename: filename) else {
                throw Error.missingLocalImage(filename: filename)
            }
            imageData.append(data)
        }

        guard !imageData.isEmpty else {
            throw Error.missingImages
        }

        return imageData
    }
}
