# FoodBuddy

FoodBuddy is an iOS meal logger with meal-first history, editable meal timestamps, and iCloud sync for both meal metadata and meal photos.

## Current Status

Iteration `003` from `docs/003-plan.md` is complete.

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

## Run on a Physical iPhone

This repo defaults to unsigned local/CI builds (`CODE_SIGNING_ALLOWED=NO`). For physical-device installs, enable signing locally.

1. In `project.yml`, set the `FoodBuddy` target signing keys to `YES`:

```yaml
CODE_SIGNING_ALLOWED: YES
CODE_SIGNING_REQUIRED: YES
```

2. Regenerate and open:

```bash
xcodegen generate
open FoodBuddy.xcodeproj
```

3. In Xcode -> target `FoodBuddy` -> Signing & Capabilities:
- Set a Team.
- Keep bundle ID unique for your account/device.
- Ensure iCloud capability and container `iCloud.com.igorkupczynski.foodbuddy` are enabled for CloudKit sync validation.
4. Connect/select your iPhone and press `Cmd+R`.

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
