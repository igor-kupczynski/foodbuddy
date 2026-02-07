# FoodBuddy Iteration 002 Plan (Meals + Metadata iCloud Sync)

## 1. Goal

Make meal logging faster and more structured by introducing meal containers, faster camera-first ingest, editable timestamps, and iCloud metadata sync.

## 2. Product Outcomes

- Capture-to-saved path is fast and optimized for repeat logging.
- User can correct date/time mistakes safely.
- History navigation scales with meal-first grouping.
- Metadata syncs across user devices via iCloud.

## 3. Scope

### In scope (002)

- New `Meal` + `MealEntry` data model (multiple entries per meal).
- Meal-first history navigation and meal detail drill-down.
- Camera-first happy path with default meal-type suggestion.
- Editable entry `loggedAt` date/time.
- Confirmation prompt when date/time edit would move entry to another meal.
- Meal type management: rename existing, add custom.
- iCloud metadata sync using SwiftData + CloudKit (private DB).
- Local-first behavior when iCloud is unavailable.

### Out of scope (moved to 003)

- Syncing full photo binaries via iCloud.
- Advanced conflict-resolution UI.
- Deleting/hiding/reordering meal types.
- Rich search semantics beyond baseline history improvements.

## 4. Core Decisions

- Persistence/sync default: `SwiftData + CloudKit`.
- Target platform: latest-only, `iOS 26`.
- Existing data migration risk: low (no real user data yet), but keep explicit bootstrap path.
- Meal semantics: one meal has exactly one meal type.
- Reassignment on time edit: prompt and apply to edited entry only.
- Metadata conflict policy: last-write-wins (`updatedAt`).
- Non-iCloud mode: continue fully local with clear status in UI.

## 5. Meal Types and Suggestions

### Default meal types

- Breakfast
- Lunch
- Dinner
- Afternoon Snack
- Snack
- Workout Fuel
- Protein Shake

### Default time windows (suggestion only)

- `< 11:00` -> Breakfast
- `11:00-14:59` -> Lunch
- `15:00-17:59` -> Afternoon Snack
- `18:00+` -> Dinner

Rules:

- Suggestions are defaults, not constraints.
- User can always assign any meal to any meal type (for example, 15:05 meal -> Lunch).
- `Snack` is always valid as catch-all.

## 6. Technical Architecture

### Data model

- `Meal`
  - `id: UUID`
  - `typeId: UUID` (references meal type)
  - `createdAt: Date`
  - `updatedAt: Date`
- `MealEntry`
  - `id: UUID`
  - `mealId: UUID`
  - `imageFilename: String`
  - `capturedAt: Date`
  - `loggedAt: Date` (user editable)
  - `updatedAt: Date`
- `MealType`
  - `id: UUID` (stable across rename)
  - `displayName: String`
  - `isSystem: Bool`
  - `createdAt: Date`
  - `updatedAt: Date`

### Services

- `MealService`
  - create/find meal for ingest
  - apply suggestion windows
  - reassign entry on timestamp edits (with confirmation decision from UI)
- `MealTypeService`
  - list, rename, create custom types

### Sync strategy (002)

- Use SwiftData CloudKit integration for metadata entities (`Meal`, `MealEntry`, `MealType`).
- Resolve collisions using `updatedAt` last-write-wins.
- Keep photo file persistence local in 002.

## 7. UX Flows

### Fast capture flow

1. User taps primary capture action.
2. Camera opens.
3. User captures photo.
4. App suggests meal type from time window.
5. User can accept or change meal type.
6. Save entry and attach to existing/new meal.
7. Return to ready-to-capture state quickly.

### Edit timestamp flow

1. User opens entry detail.
2. User edits `loggedAt`.
3. System checks whether the entry should move meals.
4. If move is needed, show confirmation dialog.
5. On confirm, move entry and persist updates.

### History flow

1. History displays meals (newest-first by meal time).
2. Meal row shows type, time span, entry count.
3. Tap meal to view contained entries.
4. Tap entry to full detail.

## 8. Milestones

### M1: Data model and bootstrap

- Add `Meal`, `MealEntry`, `MealType` models.
- Wire relationships and indexes.
- Add bootstrap path for default meal types.

### M2: Capture and meal association

- Implement suggestion windows.
- Attach captures to existing/new meals.
- Keep camera path optimized and minimal taps.

### M3: Edit and reassignment

- Add date/time edit UI on entry detail.
- Implement confirmation-gated meal reassignment.

### M4: History/navigation

- Build meal-first history list.
- Build meal detail view.
- Add date-jump navigation.

### M5: Meal type management

- Add settings/manage UI for meal types.
- Support rename of existing types.
- Support creation of new custom types.

### M6: Metadata sync

- Enable SwiftData CloudKit metadata sync.
- Add lightweight sync status/error UI.
- Validate local-first fallback when iCloud unavailable.

### M7: Verification and hardening

- Add/expand automated tests.
- Validate performance and sync behavior.
- Update docs (`README.md`, `AGENTS.md`) to reflect new behavior.

## 9. Acceptance Criteria

002 is complete when:

- App supports multiple entries per meal.
- Meal type defaults exist and suggestion windows are applied.
- User can override suggested meal type at save time.
- User can edit entry date/time.
- If a date/time edit would move meal association, app asks for confirmation.
- History is meal-first and supports drill-down to entries.
- User can rename meal types and add custom types.
- Metadata sync works via iCloud across at least two devices/simulators signed into same Apple ID.
- App continues operating locally when iCloud is not available.
- Automated test suite covering core 002 invariants passes.

## 10. Test Matrix (Automated)

### Unit tests

- Meal suggestion logic for boundary times (`10:59`, `11:00`, `14:59`, `15:00`, `17:59`, `18:00`).
- Entry-to-meal association behavior (new meal vs existing meal).
- Reassignment behavior for edited `loggedAt` values.
- Meal type rename/add validation and persistence.
- Conflict resolver (`updatedAt` last-write-wins) for metadata.

### Integration tests

- End-to-end ingest writes file + metadata row and links entry to meal.
- Meal-first history query ordering and grouping.
- Date edit + confirmation path updates model correctly.
- iCloud metadata sync smoke (if test environment allows).

### UI tests (targeted)

- Camera/library ingest path attaches to meal and appears in history.
- Entry timestamp edit shows confirmation when reassignment is required.
- Meal type rename/add is reflected in capture chooser and history.

## 11. Risks and Mitigations

- Sync edge cases with weak conflict semantics.
  - Mitigation: keep LWW policy simple in 002, instrument events, revisit in 003.
- Complexity increase from meal container model.
  - Mitigation: strict service boundaries (`MealService`, `MealTypeService`).
- iCloud account/runtime variability.
  - Mitigation: local-first mode always available and tested.

## 12. CI/CD Gate (002)

Recommended minimum gate:

- `xcodegen generate`
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`

Optional extended gate (when available):

- Targeted UI tests on iOS simulator.

## 13. Restart Checklist

When resuming 002 work:

1. Confirm this plan still matches product decisions.
2. Mark the active task `In Progress` in the status section.
3. Implement the next incomplete milestone in order.
4. Keep status and task log updated during execution.
5. Keep tests green and update docs as behavior changes.

## 14. Execution Status

Last updated: 2026-02-07

### Milestone Status

- M1 Data model and bootstrap: `Completed`
- M2 Capture and meal association: `Completed`
- M3 Edit and reassignment: `Completed`
- M4 History/navigation: `Completed`
- M5 Meal type management: `Completed`
- M6 Metadata sync: `Completed`
- M7 Verification and hardening: `Completed`

### Active Task Log

- [Completed] M1.1 Create `Meal`, `MealEntry`, and `MealType` models.
- [Completed] M1.2 Implement default meal-type bootstrap.
- [Completed] M2.1 Implement meal-type suggestion windows.
- [Completed] M2.2 Attach ingest flow to existing/new meals.
- [Completed] M3.1 Add entry date/time edit UI.
- [Completed] M3.2 Add confirmation-gated meal reassignment.
- [Completed] M4.1 Implement meal-first history UI.
- [Completed] M4.2 Implement meal detail drill-down.
- [Completed] M5.1 Implement meal type rename flow.
- [Completed] M5.2 Implement custom meal type creation.
- [Completed] M6.1 Enable SwiftData CloudKit metadata sync.
- [Completed] M6.2 Add sync status/error UX.
- [Completed] M7.1 Add tests for meal grouping and suggestion logic.
- [Completed] M7.2 Add tests for reassignment and sync conflict policy.
