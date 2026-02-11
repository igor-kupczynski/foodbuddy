# FoodBuddy Iteration 008 Plan (AI Analysis Failure Details)

## 1. Goal

When AI meal analysis fails, capture comprehensive diagnostic information and let the user view and copy it — without cluttering the default UI.

## 2. Context

The `FoodAnalysisCoordinator` silently discards all errors. The user sees only "Analysis failed. Update notes and try again." with no way to debug the root cause. Possible failures include: no API key, network errors, HTTP errors (rate limits, auth failures, server errors), response decoding errors, and missing local images. Currently none of this context is preserved.

## 3. Design

### 3.1 Capture rich error diagnostics in the coordinator

In the `catch` block of `FoodAnalysisCoordinator.processPendingMeals()`, build a multi-line diagnostic string containing:

```
Error: <error type and description>
HTTP Status: <if applicable>
Response Body: <if applicable, first ~2000 chars>
Meal ID: <UUID>
Images: <count>
Timestamp: <ISO 8601>
Stack:
<Thread.callStackSymbols, joined by newlines>
```

This gives the user everything they need to file a bug or self-diagnose.

### 3.2 Preserve HTTP response body in error type

**File:** `FoodBuddy/Services/FoodRecognitionService.swift`

Change `httpError(statusCode: Int)` → `httpError(statusCode: Int, responseBody: String?)` so we capture the Mistral API error message (often contains rate-limit info, auth errors, etc.).

Add `LocalizedError` conformance with short `errorDescription` for each case.

**File:** `FoodBuddy/Services/MistralFoodRecognitionService.swift`

When building `httpError`, read the response body as a UTF-8 string (truncated to 2000 chars) and pass it along.

### 3.3 Add `aiAnalysisErrorDetails` field to Meal model

**File:** `FoodBuddy/Domain/Meal.swift`

Add `var aiAnalysisErrorDetails: String?` (new optional field — SwiftData handles lightweight migration automatically).

### 3.4 Thread error details through `markFailed`

**File:** `FoodBuddy/Services/FoodAnalysisModelStore.swift`

- `markFailed(mealID:errorDetails:)` — stores the diagnostic string
- `claimNextPendingMeal()` — clears `aiAnalysisErrorDetails` when transitioning to `.analyzing`
- `markCompleted()` — clears `aiAnalysisErrorDetails`

**File:** `FoodBuddy/Services/FoodAnalysisCoordinator.swift`

- Add `LocalizedError` conformance to `FoodAnalysisCoordinator.Error`
- In the `catch` block, build the diagnostic string and pass to `markFailed`

### 3.5 Tappable failure details in MealDetailView

**File:** `FoodBuddy/Features/History/MealDetailView.swift`

In the `.failed` branch of `aiDescriptionSection`:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Analysis failed. Update notes and try again.")
        .foregroundStyle(.secondary)
    Button("Show details") {
        isShowingFailureDetails = true
    }
    .font(.footnote)
}
```

Add a `.sheet` presenting the full error details in a scrollable `Text` view with a **Copy** button (using `UIPasteboard.general`). Use a simple sheet — not an alert — because the diagnostic text can be long.

### 3.6 Update tests

**File:** `FoodBuddyCoreTests/FoodAnalysisCoordinatorTests.swift`

- Assert `meal.aiAnalysisErrorDetails` is non-nil and contains the expected error description after failure
- Assert it's cleared after successful re-analysis

**File:** `FoodBuddyCoreTests/MistralFoodRecognitionServiceTests.swift`

- Update tests that check for `httpError` to account for the new `responseBody` associated value

## 4. Files to modify

| # | File | Change |
|---|------|--------|
| 1 | `FoodBuddy/Domain/Meal.swift` | Add `aiAnalysisErrorDetails: String?` |
| 2 | `FoodBuddy/Services/FoodRecognitionService.swift` | Add `responseBody` to `httpError`, add `LocalizedError` |
| 3 | `FoodBuddy/Services/MistralFoodRecognitionService.swift` | Capture response body on HTTP error |
| 4 | `FoodBuddy/Services/FoodAnalysisModelStore.swift` | Accept + store + clear error details |
| 5 | `FoodBuddy/Services/FoodAnalysisCoordinator.swift` | Build diagnostic string, `LocalizedError`, pass to `markFailed` |
| 6 | `FoodBuddy/Features/History/MealDetailView.swift` | "Show details" button + sheet with Copy |
| 7 | `FoodBuddyCoreTests/FoodAnalysisCoordinatorTests.swift` | Assert error details stored/cleared |
| 8 | `FoodBuddyCoreTests/MistralFoodRecognitionServiceTests.swift` | Update `httpError` assertions |

## 5. Verification

1. Build with `xcodebuild` — must succeed with zero warnings from changed files
2. Run `FoodBuddyCoreTests` — all tests pass
3. On simulator: set an invalid API key, trigger analysis, confirm:
   - "Analysis failed" with "Show details" button appears
   - Tapping opens sheet with full diagnostics (error type, HTTP status, response body, stack trace)
   - "Copy" button copies text to clipboard
   - Re-analyzing clears the old error details
