import Foundation

struct HistorySelectionState: Equatable {
    var selectedMealID: UUID?
    var selectedEntryID: UUID?

    mutating func selectMeal(_ mealID: UUID?) {
        guard selectedMealID != mealID else {
            return
        }

        selectedMealID = mealID
        selectedEntryID = nil
    }

    mutating func selectEntry(_ entryID: UUID?) {
        selectedEntryID = entryID
    }

    func reconciled(
        meals: [Meal],
        autoSelectFirstMeal: Bool,
        autoSelectFirstEntry: Bool
    ) -> HistorySelectionState {
        guard !meals.isEmpty else {
            return HistorySelectionState()
        }

        let mealByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
        var nextMealID = selectedMealID
        if let currentMealID = nextMealID, mealByID[currentMealID] == nil {
            nextMealID = nil
        }

        if nextMealID == nil, autoSelectFirstMeal {
            nextMealID = meals.first?.id
        }

        guard let nextMealID, let selectedMeal = mealByID[nextMealID] else {
            return HistorySelectionState()
        }

        let entries = selectedMeal.entries.sorted(by: { $0.loggedAt > $1.loggedAt })
        let entryIDs = Set(entries.map(\.id))

        var nextEntryID = selectedEntryID
        if let currentEntryID = nextEntryID, !entryIDs.contains(currentEntryID) {
            nextEntryID = nil
        }

        if nextEntryID == nil, autoSelectFirstEntry {
            nextEntryID = entries.first?.id
        }

        return HistorySelectionState(selectedMealID: nextMealID, selectedEntryID: nextEntryID)
    }
}
