# FoodBuddy

FoodBuddy is an iOS meal logger with meal-first history, editable meal timestamps, and iCloud sync for both meal metadata and meal photos.

## Current Status

Iteration `003` from `docs/003-plan.md` is complete.
Iteration `004` implementation is active in `docs/004-plan.md` (iPad readiness + adaptive UI); manual iPad smoke validation remains required before merge.

Implemented features:

- Meal container model (`Meal`, `MealEntry`, `MealType`) with multiple entries per meal.
- Camera/library ingest with suggested meal type and user override before save.
- Photo preprocessing pipeline (max long edge `1600px`, JPEG compression, generated `320px` thumbnail).
- `EntryPhotoAsset` sync model with deterministic entry linkage, retry metadata, and failure state.
- Queue-based photo upload/download pipeline with exponential backoff retry handling.
- Missing-photo hydration flow for metadata-only synced entries (placeholder -> thumbnail -> full image).
- Editable `loggedAt` timestamp with confirmation when reassignment would move to another meal.
- Meal-first history navigation with meal detail drill-down.
- Meal type management (rename existing, add custom).
- SwiftData metadata sync configured for CloudKit private DB with automatic local fallback.
- CloudKit-backed photo asset store integration and sync diagnostics UI with manual retry controls.
- Adaptive navigation shell: `NavigationStack` on compact width and `NavigationSplitView` on regular width.
- Regular-width `EntryDetailView` two-column layout (image/content pane + metadata/actions pane).
- Automated verifier covering preprocessing bounds, ingest-to-pending queue behavior, upload state transitions, retry recovery, and hydration.

## Development Requirements

### Required

- macOS with Xcode 26.2+
- Swift 6.2+ (bundled with Xcode)
- `xcodegen` (project generation)

### Recommended

- `xcbeautify` (clean test/build logs)
- `gh` (GitHub workflows and PR operations)

### Install Tooling (Homebrew)

```bash
brew install xcodegen xcbeautify gh
```

### Verify Tooling

```bash
xcodebuild -version
swift --version
xcodegen --version
gh --version
```

## Local Test Workflow

```bash
# Regenerate project from project.yml
xcodegen generate

# Fast verifier tests (no iOS simulator required)
xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64' | xcbeautify
```

If `xcbeautify` is not installed, run the same `xcodebuild test` command without the pipe.

## Run on iOS Simulator

1. Generate and open the project:

```bash
xcodegen generate
open FoodBuddy.xcodeproj
```

2. In Xcode, choose scheme `FoodBuddy` and an iOS simulator device.
3. Press `Cmd+R`.

Notes:

- Camera is usually unavailable in simulator; use **Choose from Library**.
- Drag image files into the simulator Photos app to seed test data.

## iPad Smoke Validation (Required for 004)

Run these checks on an iPad simulator before merge (portrait + landscape where noted):

1. Browse meals -> select meal -> select entry -> edit `loggedAt` -> save.
2. Switch meals and entries repeatedly in landscape split view; verify selection remains stable.
3. Delete an entry from detail and verify selection/navigation recovers cleanly.
4. Open **Photo Sync Details** and **Meal Types** from toolbar.
5. Complete one **Choose from Library** ingest flow end-to-end.
6. Trigger **Retry Photo Sync** on a failed asset (or verify retry control is hidden when no failures exist).

## Run on Your iPhone (Local Install Only)

Recommended first-run path (least friction): local-only mode on your device, no CloudKit entitlement.

1. In `project.yml`, set local phone signing values:

```yaml
CODE_SIGNING_ALLOWED: YES
CODE_SIGNING_REQUIRED: YES
CODE_SIGN_ENTITLEMENTS:
```

2. Regenerate/open:

```bash
xcodegen generate
open FoodBuddy.xcodeproj
```

3. In Xcode -> target `FoodBuddy` -> Signing & Capabilities:
- Enable **Automatically manage signing**.
- Select your Team (Personal Team works for local install).
- Set bundle ID to `info.kupczynski.foodbuddy.dev`.

4. Enable Developer Mode on iPhone (first time only):
- Try one run from Xcode first.
- On iPhone: `Settings -> Privacy & Security -> Developer Mode` -> enable, reboot, confirm.

5. Select your iPhone as destination and press `Cmd+R`.

Result: app runs on phone with local metadata fallback (no iCloud sync).

Optional CloudKit-enabled phone run:

1. Restore `CODE_SIGN_ENTITLEMENTS: FoodBuddy/App/FoodBuddy.entitlements`.
2. Keep Team/bundle ID consistent with your iCloud container setup.
3. If you change container from `iCloud.com.igorkupczynski.foodbuddy`, update:
- `FoodBuddy/App/FoodBuddy.entitlements`
- `FoodBuddy/Support/Dependencies.swift`
- `FoodBuddy/Support/PersistenceController.swift`

For signing/cert/profile details, see `docs/APPLE_DEV_BASICS.md`.

## Project Layout

```text
FoodBuddy/
  App/
  Domain/
  Features/
  Services/
  Storage/
  Support/
FoodBuddyCoreTests/
docs/
```
