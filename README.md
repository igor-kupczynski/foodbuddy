# FoodBuddy

<img src="FoodBuddy/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="FoodBuddy App Icon" />

FoodBuddy is an iOS meal logger with meal-first history, editable meal timestamps, and iCloud sync for both meal metadata and meal photos.

## Overview

FoodBuddy is currently focused on:

- Meal-first logging with multi-photo capture (`1..8` photos), note-only meals, and meal-type organization.
- AI-assisted meal analysis (Mistral) with user notes, background processing, and retry flow.
- Diet Quality Score (DQS) tracking with AI food categorization, in-app category/portion guidance, and manual add/edit/delete of food items.
- SwiftData persistence with CloudKit private-database sync behavior and local fallback.
- iPhone and iPad adaptive UI, with automated unit/UI regression coverage.

Major work items are tracked in `docs/NNN-plan-*.md` (latest completed: `docs/013-plan-ai-evals-sidecar-swiftpm.md`).

## Diet Quality Score Attribution

The DQS feature is inspired by *Racing Weight* by Matt Fitzgerald.

## Development Requirements

> `FoodBuddy.xcodeproj` is **not checked into git** — it is generated from `project.yml`. Run `xcodegen generate` after cloning or pulling.

### Required

- macOS with Xcode 26.2+
- Swift 6.2+ (bundled with Xcode)
- `xcodegen` (project generation)
- `make` (task runner; built into macOS)

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

## Local Workflow

### Task Runner

Common commands are available via `Makefile`:

```bash
make xcodegen
make launch-screen-guard
make test-core
make build-ios
make build-ios-dev
make ai-shared-test
make eval-build
make eval-run CASE=case-001
```

### Selective Verification Matrix

Run only what matches your changed scope:

- App source / `project.yml`: `make xcodegen`, `make launch-screen-guard`, `make test-core`
- App build/signing/capability changes: `make build-ios` (and `make build-ios-dev` when relevant)
- Shared AI package (`Packages/FoodBuddyAIShared`): `make ai-shared-test` and `make test-core`
- Evals sidecar only (`evals/`): `make eval-build` (plus `make eval-run CASE=...` for live checks)
- UI flow changes: run targeted `FoodBuddyUITests` suites via `xcodebuild test ... -only-testing:...`

If `xcbeautify` is installed, pipe the `xcodebuild` commands to it for cleaner output.

## AI Evals (SwiftPM Sidecar)

The eval harness is a separate Swift package under `evals/` and does not require opening Xcode UI.

### Setup

1. Add your local key:

```bash
cp evals/.env.example evals/.env
# then edit evals/.env and set MISTRAL_API_KEY
```

API key precedence:
- `--api-key` CLI flag
- `MISTRAL_API_KEY` environment variable
- `evals/.env`

2. Put case fixtures here:
- `evals/cases/case-001/images/01.jpg`
- `evals/cases/case-001/images/02.jpg`

3. (Optional but recommended) set expectations in `evals/cases/case-001/case.json`:
- `expected.description` constraints
- `expected.food_items` expected names/categories/servings

### Run

```bash
make eval-case-001
# or
make eval-run CASE=case-001
```

The run writes a JSON artifact to `evals/results/`.

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
- CLI option to seed Photos app: `xcrun simctl addmedia "iPhone 17" ~/Downloads/example1.png`.

## iPad Smoke Validation (Required Pre-Merge)

Run these checks on an iPad simulator before merge (portrait + landscape where noted):

1. Browse meals -> select meal -> select entry -> edit `loggedAt` -> save.
2. Switch meals and entries repeatedly in landscape split view; verify selection remains stable.
3. Delete an entry from detail and verify selection/navigation recovers cleanly.
4. Open **Photo Sync Details** and **Meal Types** from toolbar.
5. Complete one **Choose from Library** ingest flow end-to-end.
6. Trigger **Retry Photo Sync** on a failed asset (or verify retry control is hidden when no failures exist).


## Run on Your iPhone

Recommended default path uses scheme `FoodBuddyDev` (local-only mode, no CloudKit entitlement).

1. Regenerate/open:

```bash
xcodegen generate
open FoodBuddy.xcodeproj
```

2. In Xcode, select scheme `FoodBuddyDev` and your iPhone as destination.

3. In Xcode -> target `FoodBuddyDev` -> Signing & Capabilities:
- Enable **Automatically manage signing**.
- Select your Team (Personal Team works for local install).

4. Enable Developer Mode on iPhone (first time only):
- Try one run from Xcode first.
- On iPhone: `Settings -> Privacy & Security -> Developer Mode` -> enable, reboot, confirm.

5. Select your iPhone as destination and press `Cmd+R`.

Result: app runs on phone with local metadata fallback (no iCloud sync).

Suggested manual iPhone smoke checks:

1. Capture a meal with 1-2 photos and verify save completes.
2. Add a note-only meal (no photo) and verify it appears in History.
3. Open the day in History and confirm DQS badge + Daily DQS screen render.
4. Swipe-delete one meal in History and verify the list updates.
5. Add/edit/delete one manual food item and verify daily score updates each time.
6. Swipe-delete one food item from Daily DQS or Meal Detail and verify score updates.
7. If API key is configured in **AI Settings**, run note-only re-analysis and verify AI description + food items update.

Optional CloudKit-enabled phone run:

1. Use scheme `FoodBuddy` (production app target with CloudKit entitlement).
2. Configure signing for target `FoodBuddy` with your Team.
3. Ensure bundle/container identifiers remain consistent with the baseline in `AGENTS.md`.
4. Run on device and verify iCloud-backed sync behavior.

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
Packages/
  FoodBuddyAIShared/
FoodBuddyCoreTests/
FoodBuddyUITests/
evals/
  cases/
  results/
scripts/
docs/
```

## License

MIT. See `LICENSE`.
