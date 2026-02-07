import Foundation
import XCTest

final class HistorySelectionStateTests: XCTestCase {
    func testReconcileAutoSelectsFirstMealAndEntry() {
        let mealA = makeMeal(updatedAt: Date(timeIntervalSince1970: 200), entryTimes: [120, 100])
        let mealB = makeMeal(updatedAt: Date(timeIntervalSince1970: 100), entryTimes: [80])

        let reconciled = HistorySelectionState()
            .reconciled(
                meals: [mealA, mealB],
                autoSelectFirstMeal: true,
                autoSelectFirstEntry: true
            )

        XCTAssertEqual(reconciled.selectedMealID, mealA.id)
        XCTAssertEqual(reconciled.selectedEntryID, mealA.entries.sorted(by: { $0.loggedAt > $1.loggedAt }).first?.id)
    }

    func testReconcileKeepsExistingValidSelection() {
        let meal = makeMeal(updatedAt: Date(timeIntervalSince1970: 200), entryTimes: [120, 100])
        let selectedEntryID = meal.entries[1].id
        let initial = HistorySelectionState(selectedMealID: meal.id, selectedEntryID: selectedEntryID)

        let reconciled = initial.reconciled(
            meals: [meal],
            autoSelectFirstMeal: true,
            autoSelectFirstEntry: true
        )

        XCTAssertEqual(reconciled.selectedMealID, meal.id)
        XCTAssertEqual(reconciled.selectedEntryID, selectedEntryID)
    }

    func testReconcileDropsInvalidEntryAndSelectsFirstAvailable() {
        let meal = makeMeal(updatedAt: Date(timeIntervalSince1970: 200), entryTimes: [120, 100])
        let initial = HistorySelectionState(
            selectedMealID: meal.id,
            selectedEntryID: UUID()
        )

        let reconciled = initial.reconciled(
            meals: [meal],
            autoSelectFirstMeal: true,
            autoSelectFirstEntry: true
        )

        XCTAssertEqual(reconciled.selectedMealID, meal.id)
        XCTAssertEqual(reconciled.selectedEntryID, meal.entries.sorted(by: { $0.loggedAt > $1.loggedAt }).first?.id)
    }

    func testReconcileClearsSelectionWhenMealsDisappear() {
        let initial = HistorySelectionState(
            selectedMealID: UUID(),
            selectedEntryID: UUID()
        )

        let reconciled = initial.reconciled(
            meals: [],
            autoSelectFirstMeal: true,
            autoSelectFirstEntry: true
        )

        XCTAssertNil(reconciled.selectedMealID)
        XCTAssertNil(reconciled.selectedEntryID)
    }

    func testSelectMealResetsEntrySelection() {
        var state = HistorySelectionState(
            selectedMealID: UUID(),
            selectedEntryID: UUID()
        )

        state.selectMeal(UUID())

        XCTAssertNil(state.selectedEntryID)
    }

    private func makeMeal(updatedAt: Date, entryTimes: [TimeInterval]) -> Meal {
        let meal = Meal(
            id: UUID(),
            typeId: UUID(),
            createdAt: updatedAt,
            updatedAt: updatedAt
        )

        meal.entries = entryTimes.map { time in
            MealEntry(
                id: UUID(),
                mealId: meal.id,
                imageFilename: "img-\(Int(time)).jpg",
                capturedAt: Date(timeIntervalSince1970: time),
                loggedAt: Date(timeIntervalSince1970: time),
                updatedAt: Date(timeIntervalSince1970: time),
                meal: meal
            )
        }

        return meal
    }
}
