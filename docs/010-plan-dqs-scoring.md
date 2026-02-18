# Plan 010: Diet Quality Score (DQS) Logging

Status: Completed on 2026-02-18.

## Context

FoodBuddy captures meal photos and generates AI text descriptions via Mistral. We want to expand the app to compute a **Diet Quality Score (DQS)** per day — a scoring system inspired by the book *Racing Weight* by Matt Fitzgerald. DQS is a simple daily metric: assign point values to every food you consume, then sum them up. Higher score = healthier diet. The system rewards *variety* of wholesome foods and penalizes overconsumption of any single category, even healthy ones.

DQS uses **11 food categories** (7 high-quality, 4 low-quality). Each meal contains multiple dishes (via photos + AI descriptions), so we break those down into categorized food items with serving counts, then aggregate into a daily score.

### DQS Food Categories

**High-quality categories:**

| Category | What counts | Serving size |
|----------|-------------|-------------|
| **Fruits** | Whole fresh fruit, canned/frozen fruit, 100% fruit juice | 1 medium piece; a big handful of berries; a glass of juice |
| **Vegetables** | Whole fresh vegetables (cooked or raw), canned/frozen vegetables, pureed/liquefied vegetables in soups and sauces | A fist-sized portion; 1/2 cup tomato sauce; a bowl of soup or salad |
| **Lean meats & fish** | All fish; meats <=10% fat; eggs | A palm-sized portion |
| **Legumes & plant proteins** | Beans, lentils, chickpeas, tofu, tempeh, edamame, hemp seeds, spirulina, high-protein plant foods >5g protein/serving. When using this category, legumes do not also count as vegetables | A fist-sized bowl of beans; a palm-sized block of tofu |
| **Nuts & seeds** | All common nuts and seeds, natural nut/seed butters (no added sugar) | A palmful; 1 heaping tbsp nut butter |
| **Whole grains** | Brown rice, 100% whole-grain breads, pastas, cereals | A fist-sized portion of rice; a bowl of cereal/pasta; 2 slices bread |
| **Dairy** | All milk-based products (cow, goat, sheep) — milk, cheese, yogurt, butter. Whole-milk and low-fat count the same | A glass of milk; 2 slices cheese; 1 yogurt tub |

**Low-quality categories:**

| Category | What counts | Serving size |
|----------|-------------|-------------|
| **Refined grains** | White rice, processed flours, breads/pastas/cereals not 100% whole grain | Same as whole grains |
| **Sweets** | Foods/drinks with large amounts of refined sugar; diet sodas count too. *Second-ingredient rule*: if any form of sugar (corn syrup, dextrose, fructose, sucrose, etc.) is the 1st or 2nd ingredient, it's a sweet. Exception: dark chocolate >=80% cacao in small amounts (<=100 cal) does NOT count | 1 small cookie; 12 oz soda; 1 serving candy; 1 slice cake; 1 scoop ice cream |
| **Fried foods** | All deep-fried foods; all snack chips (even baked or veggie-based). Does NOT include pan-fried foods (stir-fry, fried eggs) | 1 small bag of chips; 1 small order of fries; 3-4 wings; 1 donut |
| **Fatty proteins** | Meats >10% fat; farm-raised fish; processed meats (bacon, sausages, most cold cuts) | Same as lean meats |

### DQS Special Rules

The original DQS has some rules that produce standalone point penalties outside the 11-category system (e.g. condiment -1, latte -1/-2). Our implementation simplifies these by mapping everything to the nearest existing category — this is a DQS-inspired approximation, not a strict reproduction. The AI prompt below reflects these simplifications.

- **Double-counting**: Some foods belong to two categories simultaneously. Score them in both. Sweetened yogurt = 1 dairy + 1 sweet. Honey Nut Cheerios = 1 refined grain + 1 sweet. Ice cream = 1 dairy + 1 sweet. A food is a sweet *and* its primary category if sugar is a top-2 ingredient.
- **Condiments/sauces**: Used sparingly on high-quality foods — don't score. Used generously — classify as the nearest low-quality category (mayo → fatty_proteins, sugary BBQ sauce → sweets). Genuinely healthy condiments (homemade guacamole) — score as appropriate high-quality category.
- **Alcohol**: Moderate consumption (1 drink/day women, 2/day men) — don't score. Each drink beyond moderation — classify as sweets.
- **Coffee/tea**: Unsweetened or lightly sweetened — don't score. Lattes or heavily sweetened drinks — classify as sweets (and dairy if significant milk).
- **Sports nutrition during exercise**: Don't include in DQS at all. Energy bars eaten outside exercise — classify by primary ingredients (nuts_and_seeds + sweets, or whole_grains + sweets, etc.).
- **Combination foods**: Break into components. Pizza (2 slices) = 1 refined grains (crust) + 0.5–1 vegetables (sauce) + 1 dairy (cheese) + 1 fatty proteins (pepperoni).

## Goal

- Log DQS food items per meal with category and serving count
- Compute and display daily DQS score with category breakdown
- Enhance AI analysis to return structured food categorization alongside text descriptions
- Allow users to review and edit AI-suggested food items
- Allow manual food item entry
- Attribute DQS to *Racing Weight* in README and in the app UI

---

## Data Model

New `FoodItem` SwiftData model with a 1:N relationship from `Meal`. Each record represents one food item in one DQS category. Double-counted foods (e.g. sweetened yogurt = dairy + sweets) become two `FoodItem` records sharing the same name but different categories.

```swift
@Model
final class FoodItem: Identifiable, UpdatedAtVersioned {
    @Attribute(.unique) var id: UUID
    var mealId: UUID
    var name: String                    // "Sweetened yogurt"
    var categoryRawValue: String = DQSCategory.vegetables.rawValue  // property-level default for migration
    var servings: Double = 1.0
    var isManual: Bool = false          // true for user-created/user-edited items
    var createdAt: Date
    var updatedAt: Date

    @Relationship var meal: Meal?

    var category: DQSCategory {         // computed get/set, follows AIAnalysisStatus pattern
        get { DQSCategory(rawValue: categoryRawValue) ?? .vegetables }
        set { categoryRawValue = newValue.rawValue }
    }
}
```

On `Meal` (`FoodBuddy/Domain/Meal.swift`), add:
```swift
@Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
var foodItems: [FoodItem] = []          // property-level default per CLAUDE.md lessons
```
Add corresponding `foodItems` parameter (default `[]`) to `Meal.init`.

Existing meals get `foodItems: []` after migration — they won't have DQS data until re-analyzed or manually populated. This is fine.

Register `FoodItem.self` in `PersistenceController.swift`'s schema array.

### Meal lifecycle change

`MealService.deleteMealIfEmpty()` (`FoodBuddy/Services/MealService.swift:56`) currently deletes a meal when `entries.isEmpty`. This is called when an entry is deleted or reassigned to another meal (`MealEntryService` lines 247, 297, 338). With DQS, a meal can have zero photo entries but still hold manually-added food items. The guard must change to:
```swift
func deleteMealIfEmpty(_ meal: Meal) {
    if meal.entries.isEmpty && meal.foodItems.isEmpty {
        modelContext.delete(meal)
    }
}
```
Without this, deleting the last photo entry from a meal would cascade-delete its food items.

### DQSCategory enum

New file `FoodBuddy/Domain/DQSCategory.swift`. Follow the `AIAnalysisStatus` pattern (`FoodBuddy/Domain/AIAnalysisStatus.swift`) — enum with `rawValue: String`, stored as raw string on the model.

11 cases:
- **High-quality:** `fruits`, `vegetables`, `leanMeatsAndFish`, `legumesAndPlantProteins`, `nutsAndSeeds`, `wholeGrains`, `dairy`
- **Low-quality:** `refinedGrains`, `sweets`, `friedFoods`, `fattyProteins`

Computed properties: `displayName: String`, `isHighQuality: Bool`

---

## Scoring Engine

New file `FoodBuddy/Services/DQSScoringEngine.swift` — pure stateless struct, no dependencies, trivially testable.

Uses the **per-category scoring tables**:

| Category | 1st | 2nd | 3rd | 4th | 5th | 6th+ |
|----------|:---:|:---:|:---:|:---:|:---:|:----:|
| Fruits | +2 | +2 | +2 | +1 | 0 | 0 |
| Vegetables | +2 | +2 | +2 | +1 | 0 | 0 |
| Lean meats & fish | +2 | +2 | +1 | 0 | 0 | -1 |
| Legumes & plant proteins | +2 | +2 | +1 | 0 | 0 | -1 |
| Nuts & seeds | +2 | +2 | +1 | 0 | 0 | -1 |
| Whole grains | +2 | +2 | +1 | 0 | 0 | -1 |
| Dairy | +1 | +1 | +1 | 0 | -1 | -2 |
| Refined grains | -1 | -1 | -2 | -2 | -2 | -2 |
| Sweets | -2 | -2 | -2 | -2 | -2 | -2 |
| Fried foods | -2 | -2 | -2 | -2 | -2 | -2 |
| Fatty proteins | -1 | -1 | -2 | -2 | -2 | -2 |

Each category has a `scoringTable: [Int]` array (6 entries for 1st–6th+ serving). `pointsForServings(category:servings:)` iterates through whole servings summing per-serving points. Fractional servings use schoolbook rounding (0.5 rounds up): `Int(servings.rounded(.toNearestOrAwayFromZero))`. This avoids Swift's default banker's rounding which would round 0.5 to 0 and 2.5 to 2.

Score interpretation (for UI display):

| Range | Label |
|-------|-------|
| < 0 | Low quality |
| 0–10 | Below average |
| 11–20 | Fairly high quality |
| 21–29 | High quality |
| 30+ | Near-perfect |

Theoretical max (flexitarian): ~37. Practical target: 20+.

Input: array of `FoodItem` (all items from all meals on a given day). Engine groups by category, sums servings, applies per-category scoring table.

Returns:
```swift
struct DailyScore {
    let date: Date
    let categoryBreakdowns: [CategoryBreakdown]  // category + servings + points
    let totalScore: Int
}
struct CategoryBreakdown {
    let category: DQSCategory
    let servings: Double
    let points: Int
}
```

---

## AI Prompt and Schema

### Current state

`MistralFoodRecognitionService` (`FoodBuddy/Services/MistralFoodRecognitionService.swift`) calls the Mistral API via `FoodRecognitionService.describe()` protocol method. It sends meal photos with a system prompt and returns a text description via a strict JSON schema (`{"description": "..."}`). The schema is built from tightly-typed Swift structs (`DescriptionSchema`, `DescriptionProperties`, etc.).

### Enhanced system prompt

Replace the existing `Constants.systemPrompt` with:

```
You are a food-logging assistant. The user sends photos from a single meal, possibly with notes for context.

Return two things:
1. A 1-3 sentence description of the food and drink items visible
2. A structured list of individual food items for diet quality scoring

For descriptions:
- If a photo shows a nutrition label or restaurant menu, extract the relevant items and nutritional info instead of describing the image
- Incorporate the user's notes — they may correct, clarify, or add context the photos don't show
- Be concise and specific (e.g. "grilled chicken breast" not just "meat")

For food items, classify each into one or more Diet Quality Score (DQS) categories:

HIGH-QUALITY categories:
- fruits: Whole fresh/canned/frozen fruit, 100% fruit juice
- vegetables: Fresh/cooked/canned/frozen vegetables, pureed vegetables in soups and sauces
- lean_meats_and_fish: All fish, meats <=10% fat, eggs
- legumes_and_plant_proteins: Beans, lentils, chickpeas, tofu, tempeh, edamame, high-protein plant foods (>5g protein/serving)
- nuts_and_seeds: All nuts and seeds, natural nut/seed butters (no added sugar)
- whole_grains: Brown rice, 100% whole-grain breads/pastas/cereals
- dairy: All milk-based products (milk, cheese, yogurt, butter) — cow, goat, sheep

LOW-QUALITY categories:
- refined_grains: White rice, processed flours, breads/pastas/cereals not 100% whole grain
- sweets: Foods/drinks with large amounts of refined sugar, diet sodas. If any form of sugar is the 1st or 2nd ingredient, classify as sweets. Exception: dark chocolate >=80% cacao in small amounts does NOT count
- fried_foods: All deep-fried foods, all snack chips (even baked/veggie-based). Does NOT include pan-fried foods (stir-fry, fried eggs)
- fatty_proteins: Meats >10% fat, farm-raised fish, processed meats (bacon, sausages, cold cuts)

Serving size guidance:
- Fruit: 1 medium piece, a big handful of berries, a glass of juice
- Vegetables: a fist-sized portion, 1/2 cup sauce, a bowl of soup/salad
- Meats/fish: a palm-sized portion
- Grains: a fist-sized portion of rice, a bowl of cereal/pasta, 2 slices bread
- Dairy: a glass of milk, 2 slices cheese, 1 yogurt tub
- Nuts: a palmful, 1 heaping tbsp nut butter

Special rules:
- DOUBLE-COUNTING: A food can belong to TWO categories. Sweetened yogurt = dairy + sweets. Honey Nut Cheerios = refined_grains + sweets. Ice cream = dairy + sweets. If sugar is a top-2 ingredient, add sweets alongside the primary category.
- CONDIMENTS used sparingly: don't include. Used generously (e.g. mayo on fries, BBQ sauce smothered on ribs): include as a separate sweets or fatty_proteins item.
- ALCOHOL: moderate (1-2 drinks) don't include. Beyond that, classify each extra drink as sweets.
- COFFEE/TEA: unsweetened don't include. Lattes or heavily sweetened drinks: classify as sweets (and dairy if significant milk).
- COMBINATION FOODS: break into components. Pizza = refined_grains (crust) + vegetables (sauce) + dairy (cheese) + fatty_proteins (pepperoni).
```

### Enhanced JSON response schema

Replace `ResponseFormat.strictDescriptionSchema` with a new schema. The current schema structs are tightly typed — generalize or replace them to support the nested structure:

```json
{
  "type": "json_schema",
  "json_schema": {
    "name": "food_analysis",
    "strict": true,
    "schema": {
      "type": "object",
      "properties": {
        "description": {
          "type": "string",
          "description": "1-3 sentence description of the food and drink items in the meal"
        },
        "food_items": {
          "type": "array",
          "description": "Individual food items identified, categorized for diet quality scoring",
          "items": {
            "type": "object",
            "properties": {
              "name": {
                "type": "string",
                "description": "Specific name of the food item"
              },
              "categories": {
                "type": "array",
                "description": "DQS categories (usually 1, sometimes 2 for double-counted foods)",
                "items": {
                  "type": "string",
                  "enum": [
                    "fruits", "vegetables", "lean_meats_and_fish",
                    "legumes_and_plant_proteins", "nuts_and_seeds",
                    "whole_grains", "dairy", "refined_grains",
                    "sweets", "fried_foods", "fatty_proteins"
                  ]
                }
              },
              "servings": {
                "type": "number",
                "description": "Estimated number of standard servings (0.5, 1, 1.5, 2, etc.)"
              }
            },
            "required": ["name", "categories", "servings"],
            "additionalProperties": false
          }
        }
      },
      "required": ["description", "food_items"],
      "additionalProperties": false
    }
  }
}
```

Note: the category enum values in the API use **snake_case** (`lean_meats_and_fish`) while the Swift `DQSCategory` enum uses camelCase (`leanMeatsAndFish`). The parsing layer needs to map between these (e.g. replace `_` with camelCase conversion, or use a lookup dictionary).

### Protocol changes

In `FoodBuddy/Services/FoodRecognitionService.swift`, add:

```swift
struct FoodAnalysisResult: Sendable {
    let description: String
    let foodItems: [AIFoodItem]
}
struct AIFoodItem: Sendable, Codable {
    let name: String
    let categories: [String]  // snake_case DQS category strings from API
    let servings: Double
}
```

Add to `FoodRecognitionService` protocol:
```swift
func analyze(images: [Data], notes: String?) async throws -> FoodAnalysisResult
```

Existing `describe()` delegates to `analyze()` and returns `.description` only.

Update `MockFoodRecognitionService` — add `analyze()` with a new `Behavior` case for configurable food items.

---

## Tasks

### Phase 1 (M1): Domain Model + Scoring Engine

- [x] Create `FoodBuddy/Domain/DQSCategory.swift`
- [x] Create `FoodBuddy/Domain/FoodItem.swift`
- [x] Modify `FoodBuddy/Domain/Meal.swift` — add `foodItems` relationship + init parameter
- [x] Modify `FoodBuddy/Support/PersistenceController.swift` — add `FoodItem.self` to schema
- [x] Modify `FoodBuddy/Services/MealService.swift` — change `deleteMealIfEmpty` guard to `entries.isEmpty && foodItems.isEmpty` (see Meal lifecycle change above)
- [x] Create `FoodBuddy/Services/DQSScoringEngine.swift`
- [x] Create `FoodBuddyCoreTests/DQSScoringEngineTests.swift` — test every category at boundary servings (0, 1, 3, 5, 6+), empty input, multi-category aggregation, fractional servings rounding
- [x] Create `FoodBuddyCoreTests/MealServiceTests.swift` — verify `deleteMealIfEmpty` keeps meal when `foodItems` exist and deletes only when both `entries` and `foodItems` are empty
- [x] Extend `FoodBuddyCoreTests/MealEntryServiceTests.swift` (or equivalent integration test) — verify moving/deleting entries does not cascade-delete meal if it still has `foodItems`

### Phase 2 (M2): Enhanced AI Categorization

The existing AI pipeline: `FoodAnalysisCoordinator` (`FoodBuddy/Services/FoodAnalysisCoordinator.swift`) calls `FoodRecognitionService.describe()` → `MistralFoodRecognitionService` (`FoodBuddy/Services/MistralFoodRecognitionService.swift`) sends photos to Mistral → returns text description → `FoodAnalysisModelStore` (`FoodBuddy/Services/FoodAnalysisModelStore.swift`) saves it on `Meal.aiDescription`.

- [x] Modify `FoodBuddy/Services/FoodRecognitionService.swift` — add `FoodAnalysisResult`, `AIFoodItem` types, `analyze()` protocol method, update `MockFoodRecognitionService`
- [x] Modify `FoodBuddy/Services/MistralFoodRecognitionService.swift` — replace system prompt and JSON schema as specified above. Generalize the schema encoding structs to support the nested `food_items` array. Implement `analyze()` method with parsing. Make `describe()` delegate to `analyze()`.
- [x] Modify `FoodBuddy/Services/FoodAnalysisModelStore.swift` — add `markCompletedWithFoodItems(mealID:description:foodItems:)`:
  1. Sets `aiDescription` (existing behavior)
  2. Deletes existing `FoodItem` records where `isManual == false` for the meal (re-analysis preserves manual edits)
  3. Creates new `FoodItem` records — one per category per food (expanding double-counted items into separate records)
  4. Maps snake_case API category strings to `DQSCategory` enum values
- [x] Modify `FoodBuddy/Services/FoodAnalysisCoordinator.swift` — in `processPendingMeals()`, call `analyze()` instead of `describe()`, call `markCompletedWithFoodItems()` instead of `markCompleted()`
- [x] Extend `FoodBuddyCoreTests/MistralFoodRecognitionServiceTests.swift` — verify new schema in request JSON, parse response with `food_items`, handle empty food_items, skip items with unknown category strings
- [x] Extend `FoodBuddyCoreTests/FoodAnalysisCoordinatorTests.swift` — verify `FoodItem` records created after analysis, verify re-analysis replaces AI items but preserves manual items
- [x] Create/extend `FoodBuddyCoreTests/FoodAnalysisModelStoreTests.swift` — verify snake_case→`DQSCategory` mapping, double-count expansion (one input item -> multiple `FoodItem` rows), unknown category drop, and non-manual replacement semantics

### Phase 3 (M3): Daily DQS View + Food Item Editing UI

- [x] Create `FoodBuddy/Services/FoodItemService.swift` — CRUD service following `MealEntryService` pattern (`FoodBuddy/Services/MealEntryService.swift`): takes `ModelContext`, methods throw. Methods:
  - `createFoodItem(mealID:name:category:servings:isManual:)`
  - `updateFoodItem(_:name:category:servings:)` — sets `isManual = true`
  - `deleteFoodItem(_:)`
  - `foodItems(forMealIDs:)` — fetch for daily aggregation
- [x] Modify `FoodBuddy/Support/Dependencies.swift` — add `makeFoodItemService(modelContext:)` factory (follow existing `makeMealEntryService` pattern)
- [x] Create `FoodBuddy/Features/DQS/DailyScoreBadge.swift` — compact score view (colored number). Colors: green (>=21), yellow (11–20), orange (1–10), red (<=0).
- [x] Create `FoodBuddy/Features/DQS/DailyDQSView.swift` — reached via `NavigationLink` from day section header in HistoryView. Shows:
  - Date + total score with color + interpretation label
  - "High Quality" section: rows for each category with serving count + points
  - "Low Quality" section: same
  - "Food Items" section: grouped by meal (meal type name as sub-header), each item shows name + category pill + servings, tappable to edit
  - Footer: "Inspired by *Racing Weight* by Matt Fitzgerald"
- [x] Create `FoodBuddy/Features/DQS/FoodItemEditView.swift` — reusable edit form presented from food-item rows. Fields: name (TextField), category (Picker over all DQSCategory cases), servings (Stepper, 0.5 increments, min 0.5), delete button with confirmation.
- [x] Modify `FoodBuddy/Features/History/HistoryView.swift` — refactor the flat meal list into day-grouped sections. Currently `compactHistoryView` and `regularHistoryView` use `ForEach(meals)`. Change to:
  - Compute day groups from `meals` using `Calendar.current.startOfDay(for: meal.createdAt)` (matches existing `MealService` day logic)
  - `ForEach(dayGroups)` → Section with header showing date + `DailyScoreBadge` as `NavigationLink` to `DailyDQSView` → inner `ForEach(mealsInDay)` with existing `MealRowView`
- [x] Modify `FoodBuddy/Features/History/MealDetailView.swift` — add "Food Items" section below AI description. Shows food items for this meal, grouped by name for double-counted items:
  ```
  FOOD ITEMS
  Oatmeal           Whole Grains   1 srv
  Banana            Fruits         1 srv
  Sweetened yogurt
    Dairy                          1 srv
    Sweets                         1 srv
                       [+ Add Item]
  ```
  Each row tappable → `FoodItemEditView` sheet.
- [x] Add deterministic accessibility identifiers for DQS surfaces (day score badge/link, category rows, food item rows, add/edit/save/delete actions) so UI tests can drive and assert behavior without label-string coupling
- [x] Create `FoodBuddyUITests/DQSFlowUITests.swift` — with mock food recognition enabled, verify history day header shows score badge, navigation to `DailyDQSView`, and category/total rendering for known fixture data

### Phase 4 (M4): Manual Entry + Polish + Attribution

- [x] Create `FoodBuddy/Features/DQS/ManualFoodItemSheet.swift` — add food item without photos: name, category, servings. When navigated from MealDetailView, attach to that meal. When from DailyDQSView, show meal type picker and use/create meal for that day+type (follow `MealService.meal(for:loggedAt:)` pattern in `FoodBuddy/Services/MealService.swift`).
- [x] Add "+ Add Food Item" button to `DailyDQSView` and `MealDetailView` food items section
- [x] Extend `FoodBuddyUITests/DQSFlowUITests.swift` — verify add/edit/delete food item flows and that daily total updates after each mutation
- [x] Add UI-test fixture controls (launch arguments/env) to seed deterministic DQS sample data and isolate keychain/service state per test run
- [x] Update `README.md` — add DQS feature description with Racing Weight attribution
- [x] Update `AGENTS.md` with any lessons learned

## Acceptance Criteria

- [x] `FoodItem` model persists via SwiftData, syncs via CloudKit, cascade-deletes with Meal
- [x] DQS scoring engine correctly computes scores for all 11 categories per the scoring table
- [x] AI analysis returns structured food items alongside text description
- [x] Daily DQS score displayed in HistoryView section headers, with detailed breakdown in DailyDQSView
- [x] Users can edit food item name, category, and servings
- [x] Users can manually add food items
- [x] Re-analysis replaces AI items but preserves manual edits
- [x] Racing Weight attribution visible in app and README
- [x] All existing + new unit tests pass on macOS
- [x] DQS UI flows (view, add, edit, delete, score recompute) are covered by simulator UI tests and pass in CI/local automation
- [x] iOS build succeeds with `CODE_SIGNING_ALLOWED=NO`
- [x] No blocking acceptance gate requires manual simulator interaction; manual runs are exploratory only

## Verification

1. `xcodegen generate`
2. `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` — all tests pass
3. `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddyUITests -destination 'platform=iOS Simulator,name=iPhone 17'` — UI tests pass, including `DQSFlowUITests`
4. `xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` — build succeeds
5. `rg "Racing Weight" README.md FoodBuddy/Features/DQS` — attribution present in docs and app code
6. Optional exploratory simulator pass: capture meal → AI returns food items → daily score computed → edit food items → score updates → manual entry works
