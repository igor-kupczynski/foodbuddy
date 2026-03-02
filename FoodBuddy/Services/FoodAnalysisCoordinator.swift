import Foundation

actor FoodAnalysisCoordinator {
    enum Error: Swift.Error, LocalizedError {
        case missingLocalImage(filename: String)

        var errorDescription: String? {
            switch self {
            case .missingLocalImage(let filename):
                return "Image file missing: \(filename)"
            }
        }
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
                let analysis = try await foodRecognitionService.analyze(
                    images: imageData,
                    notes: pendingMeal.notes
                )
                try await MainActor.run {
                    try modelStore.markCompletedWithFoodItems(
                        mealID: pendingMeal.mealID,
                        description: analysis.description,
                        foodItems: analysis.foodItems
                    )
                }
            } catch let error as FoodRecognitionServiceError {
                let details = buildErrorDetails(error: error, meal: pendingMeal)
                switch error {
                case .rateLimited(let telemetry):
                    try? await MainActor.run {
                        try modelStore.markPendingRetry(
                            mealID: pendingMeal.mealID,
                            errorDetails: details,
                            nextRetryAt: telemetry.nextEligibleRetryAt
                        )
                    }
                    return
                default:
                    try? await MainActor.run {
                        try modelStore.markFailed(mealID: pendingMeal.mealID, errorDetails: details)
                    }
                }
            } catch {
                let details = buildErrorDetails(error: error, meal: pendingMeal)
                try? await MainActor.run {
                    try modelStore.markFailed(mealID: pendingMeal.mealID, errorDetails: details)
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
        return imageData
    }

    private nonisolated func buildErrorDetails(error: Swift.Error, meal: PendingMealAnalysis) -> String {
        var lines: [String] = []

        lines.append("Error: \(error.localizedDescription)")
        lines.append("Type: \(type(of: error)).\(error)")

        if let httpError = error as? FoodRecognitionServiceError,
           case .httpError(let statusCode, let body, let telemetry) = httpError {
            appendHTTPDetails(
                lines: &lines,
                statusCode: statusCode,
                responseBody: body,
                responseTelemetry: telemetry
            )
        }

        if let rateLimitedError = error as? FoodRecognitionServiceError,
           case .rateLimited(let telemetry) = rateLimitedError {
            appendHTTPDetails(
                lines: &lines,
                statusCode: telemetry.statusCode,
                responseBody: telemetry.responseBody,
                responseTelemetry: telemetry.responseTelemetry
            )
            lines.append("Model: \(telemetry.model)")
            lines.append("AI Image Long Edge: \(telemetry.imageLongEdge)")
            lines.append("AI Image Quality: \(telemetry.imageQuality)")
            lines.append("Request Images: \(telemetry.requestImageCount)")
            if !telemetry.requestImageBytes.isEmpty {
                let imageBytes = telemetry.requestImageBytes
                    .enumerated()
                    .map { "image\($0.offset + 1)=\($0.element)B" }
                    .joined(separator: ", ")
                lines.append("Request Image Bytes: \(imageBytes)")
            }
            lines.append("Request Body Bytes: \(telemetry.requestBodyBytes)")
            lines.append("Attempts: \(telemetry.attemptCount)/\(telemetry.maxAttempts)")
            if !telemetry.appliedRetryDelayMs.isEmpty {
                let delayText = telemetry.appliedRetryDelayMs
                    .map { "\($0)ms" }
                    .joined(separator: ", ")
                lines.append("Retry Delays: \(delayText)")
            }
            if let retryAfterRawValue = telemetry.retryAfterRawValue {
                lines.append("Retry-After: \(retryAfterRawValue)")
            }
            lines.append("Next Eligible Retry: \(ISO8601DateFormatter().string(from: telemetry.nextEligibleRetryAt))")
        }

        lines.append("Meal ID: \(meal.mealID)")
        lines.append("Images: \(meal.imageFilenames.count)")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("Stack:")
        lines.append(contentsOf: Thread.callStackSymbols)

        return lines.joined(separator: "\n")
    }

    private nonisolated func appendHTTPDetails(
        lines: inout [String],
        statusCode: Int,
        responseBody: String?,
        responseTelemetry: HTTPResponseTelemetry?
    ) {
        lines.append("HTTP Status: \(statusCode)")

        if let responseTelemetry,
           !responseTelemetry.interestingHeaders.isEmpty {
            lines.append("Response Headers:")
            for header in responseTelemetry.interestingHeaders.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(header.key): \(header.value)")
            }
        }

        if let responseBody {
            lines.append("Response Body:\n\(responseBody)")
        }
    }
}
