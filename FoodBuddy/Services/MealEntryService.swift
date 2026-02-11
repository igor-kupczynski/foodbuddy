import Foundation
import SwiftData

@MainActor
protocol MealEntryIngesting {
    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry
}

enum LoggedAtUpdateResult: Equatable {
    case updatedWithoutReassignment
    case requiresMealReassignmentConfirmation
    case updatedWithReassignment
}

enum MealTypeReassignmentResult: Equatable {
    case noChange
    case moved
}

@MainActor
final class MealEntryService: MealEntryIngesting {
    private enum Constants {
        static let maxCapturePhotos = 8
    }

    enum Error: Swift.Error, Equatable {
        case missingMealType
        case missingMeal
        case emptyCaptureSession
        case capturePhotoLimitExceeded
    }

    private let modelContext: ModelContext
    private let imageStore: ImageStore
    private let imagePreprocessor: ImagePreprocessor
    private let mealService: MealService
    private let mealTypeService: MealTypeService
    private let nowProvider: () -> Date
    private let uuidProvider: () -> UUID

    init(
        modelContext: ModelContext,
        imageStore: ImageStore,
        imagePreprocessor: ImagePreprocessor = ImagePreprocessor(),
        mealService: MealService? = nil,
        mealTypeService: MealTypeService? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        uuidProvider: @escaping () -> UUID = UUID.init
    ) {
        self.modelContext = modelContext
        self.imageStore = imageStore
        self.imagePreprocessor = imagePreprocessor
        self.nowProvider = nowProvider
        self.uuidProvider = uuidProvider
        self.mealService = mealService ?? MealService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
        self.mealTypeService = mealTypeService ?? MealTypeService(
            modelContext: modelContext,
            nowProvider: nowProvider,
            uuidProvider: uuidProvider
        )
    }

    func bootstrapMealTypesIfNeeded() throws {
        try mealTypeService.bootstrapDefaultTypesIfNeeded()
    }

    func listEntriesNewestFirst() throws -> [MealEntry] {
        let descriptor = FetchDescriptor<MealEntry>(
            sortBy: [SortDescriptor(\MealEntry.loggedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func listMealTypes() throws -> [MealType] {
        try mealTypeService.fetchAll()
    }

    func suggestedMealType(for date: Date) throws -> MealType? {
        try mealTypeService.suggestMealType(for: date)
    }

    @discardableResult
    func ingest(image: PlatformImage) throws -> MealEntry {
        let loggedAt = nowProvider()
        guard let mealType = try mealTypeService.suggestMealType(for: loggedAt)
            ?? mealTypeService.fetchFallbackSnackType() else {
            throw Error.missingMealType
        }

        return try ingest(image: image, mealTypeID: mealType.id, loggedAt: loggedAt)
    }

    @discardableResult
    func ingest(image: PlatformImage, mealTypeID: UUID, loggedAt: Date) throws -> MealEntry {
        let entries = try ingestEntries(
            images: [image],
            mealTypeID: mealTypeID,
            loggedAt: loggedAt,
            userNotes: nil,
            aiAnalysisStatus: .none
        )
        guard let entry = entries.first else {
            throw Error.emptyCaptureSession
        }
        return entry
    }

    @discardableResult
    func ingest(
        images: [PlatformImage],
        mealTypeID: UUID,
        loggedAt: Date,
        userNotes: String?,
        aiAnalysisStatus: AIAnalysisStatus
    ) throws -> [MealEntry] {
        try ingestEntries(
            images: images,
            mealTypeID: mealTypeID,
            loggedAt: loggedAt,
            userNotes: userNotes,
            aiAnalysisStatus: aiAnalysisStatus
        )
    }

    func updateMealNotes(_ notes: String?, for meal: Meal) throws {
        meal.userNotes = normalizedNotes(notes)
        mealService.touch(meal)
        try save()
    }

    func queueMealForAnalysis(_ meal: Meal) throws {
        meal.aiDescription = nil
        meal.aiAnalysisStatus = .pending
        mealService.touch(meal)
        try save()
    }

    private func ingestEntries(
        images: [PlatformImage],
        mealTypeID: UUID,
        loggedAt: Date,
        userNotes: String?,
        aiAnalysisStatus: AIAnalysisStatus
    ) throws -> [MealEntry] {
        guard !images.isEmpty else {
            throw Error.emptyCaptureSession
        }
        guard images.count <= Constants.maxCapturePhotos else {
            throw Error.capturePhotoLimitExceeded
        }

        let now = nowProvider()
        let capturedAt = now
        var storedImageFilenames: [String] = []
        var preparedPhotos: [(imageFilename: String, thumbnailFilename: String)] = []
        preparedPhotos.reserveCapacity(images.count)

        do {
            for image in images {
                let processed = try imagePreprocessor.preprocess(image)
                let imageFilename = try imageStore.saveJPEGData(processed.fullJPEGData)
                let thumbnailFilename = try imageStore.saveJPEGData(processed.thumbnailJPEGData)
                storedImageFilenames.append(imageFilename)
                storedImageFilenames.append(thumbnailFilename)
                preparedPhotos.append((imageFilename: imageFilename, thumbnailFilename: thumbnailFilename))
            }

            guard let mealType = try mealTypeService.fetchType(id: mealTypeID) else {
                throw Error.missingMealType
            }

            let meal = try mealService.meal(for: mealType.id, loggedAt: loggedAt)
            mealService.touch(meal)
            meal.userNotes = normalizedNotes(userNotes)
            meal.aiAnalysisStatus = aiAnalysisStatus
            if aiAnalysisStatus == .pending {
                meal.aiDescription = nil
            }

            var entries: [MealEntry] = []
            entries.reserveCapacity(preparedPhotos.count)

            for prepared in preparedPhotos {
                let entry = MealEntry(
                    id: uuidProvider(),
                    mealId: meal.id,
                    imageFilename: prepared.imageFilename,
                    capturedAt: capturedAt,
                    loggedAt: loggedAt,
                    updatedAt: now,
                    meal: meal
                )

                let photoAsset = EntryPhotoAsset(
                    id: entry.id,
                    entryId: entry.id,
                    fullImageFilename: prepared.imageFilename,
                    thumbnailFilename: prepared.thumbnailFilename,
                    state: .pending,
                    updatedAt: now,
                    entry: entry
                )
                entry.photoAsset = photoAsset
                entry.photoAssetId = photoAsset.id

                modelContext.insert(photoAsset)
                modelContext.insert(entry)
                entries.append(entry)
            }

            try save()
            return entries
        } catch {
            for filename in storedImageFilenames {
                try? imageStore.deleteImage(filename: filename)
            }
            throw error
        }
    }

    func delete(entry: MealEntry) throws {
        let meal: Meal?
        if let existingMeal = entry.meal {
            meal = existingMeal
        } else {
            meal = try mealService.fetchMeal(id: entry.mealId)
        }
        let filesToDelete = Set([
            entry.imageFilename,
            entry.photoAsset?.fullImageFilename,
            entry.photoAsset?.thumbnailFilename
        ].compactMap { $0 })

        for filename in filesToDelete {
            try imageStore.deleteImage(filename: filename)
        }

        modelContext.delete(entry)

        if let meal {
            mealService.touch(meal)
            mealService.deleteMealIfEmpty(meal)
        }

        try save()
    }

    func delete(entryID: UUID) throws {
        guard let entry = try fetchEntry(id: entryID) else {
            return
        }
        try delete(entry: entry)
    }

    func updateLoggedAt(
        entry: MealEntry,
        newLoggedAt: Date,
        allowMealReassignment: Bool
    ) throws -> LoggedAtUpdateResult {
        let resolvedMeal: Meal?
        if let existingMeal = entry.meal {
            resolvedMeal = existingMeal
        } else {
            resolvedMeal = try mealService.fetchMeal(id: entry.mealId)
        }

        guard let currentMeal = resolvedMeal else {
            throw Error.missingMeal
        }

        let needsReassignment = mealService.requiresReassignment(
            currentMeal: currentMeal,
            newLoggedAt: newLoggedAt
        )

        if needsReassignment, !allowMealReassignment {
            return .requiresMealReassignmentConfirmation
        }

        let now = nowProvider()
        entry.loggedAt = newLoggedAt
        entry.updatedAt = now

        if needsReassignment {
            let destination = try mealService.meal(for: currentMeal.typeId, loggedAt: newLoggedAt)
            if destination.id != currentMeal.id {
                entry.meal = destination
                entry.mealId = destination.id
                mealService.touch(destination)
            }
            mealService.touch(currentMeal)
            mealService.deleteMealIfEmpty(currentMeal)
            try save()
            return .updatedWithReassignment
        }

        mealService.touch(currentMeal)
        try save()
        return .updatedWithoutReassignment
    }

    func reassignMealType(entry: MealEntry, to mealTypeID: UUID) throws -> MealTypeReassignmentResult {
        let resolvedMeal: Meal?
        if let existingMeal = entry.meal {
            resolvedMeal = existingMeal
        } else {
            resolvedMeal = try mealService.fetchMeal(id: entry.mealId)
        }

        guard let currentMeal = resolvedMeal else {
            throw Error.missingMeal
        }

        guard try mealTypeService.fetchType(id: mealTypeID) != nil else {
            throw Error.missingMealType
        }

        if currentMeal.typeId == mealTypeID {
            return .noChange
        }

        let destinationMeal = try mealService.meal(for: mealTypeID, loggedAt: entry.loggedAt)
        if destinationMeal.id == currentMeal.id {
            return .noChange
        }

        entry.meal = destinationMeal
        entry.mealId = destinationMeal.id
        entry.updatedAt = nowProvider()

        mealService.touch(destinationMeal)
        mealService.touch(currentMeal)
        mealService.deleteMealIfEmpty(currentMeal)
        try save()

        return .moved
    }

    @discardableResult
    func createCustomMealType(named name: String) throws -> MealType {
        try mealTypeService.createCustomType(named: name)
    }

    func renameMealType(id: UUID, to name: String) throws {
        try mealTypeService.rename(typeID: id, to: name)
    }

    private func fetchEntry(id: UUID) throws -> MealEntry? {
        let targetID = id
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
