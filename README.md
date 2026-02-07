# FoodBuddy

FoodBuddy is an iOS MVP for meal photo logging.

## Current Status

MVP implementation from `docs/001-plan.md` is complete.

Implemented features:

- Add a meal entry from camera.
- Add a meal entry from photo library.
- Persist meal entries locally with SwiftData + image files.
- Show history newest-first.
- Open full-size entry detail.
- Delete entries from history and detail with image-file cleanup.
- Fast automated verifier for core invariants.

## Development Requirements

### Required

- macOS with Xcode 26.2+
- Swift 6.2+ (bundled with Xcode)
- `xcodegen` (project generation)

### Recommended

- `xcbeautify` (clean test/build logs)
- `gh` (GitHub workflows)

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
# Generate Xcode project
xcodegen generate

# Fast verifier tests (no simulator required)
xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64' | xcbeautify
```

What this runs:

- `FoodBuddyCoreTests` only (logic tests for `ImageStore` and `MealEntryService`).
- No iOS simulator boot required.

If you do not have `xcbeautify` installed, run:

```bash
xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'
```

## Run on iOS Simulator (Emulator)

1. Generate and open the project:

```bash
xcodegen generate
open FoodBuddy.xcodeproj
```

2. In Xcode, choose scheme `FoodBuddy` and a simulator device (for example, `iPhone 16`).
3. If no iOS simulator devices are available, install an iOS runtime from:
Xcode -> Settings -> Components.
4. Press `Cmd+R` to build and run.

Notes:

- The camera is typically unavailable in simulator; use **Choose from Library** there.
- You can drag an image file into the simulator Photos app to seed test data.

## Run on a Physical iPhone

This repo is configured for CI/local unsigned builds by default (`CODE_SIGNING_ALLOWED=NO`), so physical-device installs require a local signing change.

1. Enable code signing in `project.yml` for target `FoodBuddy`:

```yaml
targets:
  FoodBuddy:
    settings:
      base:
        CODE_SIGNING_ALLOWED: YES
        CODE_SIGNING_REQUIRED: YES
```

2. Regenerate and open:

```bash
xcodegen generate
open FoodBuddy.xcodeproj
```

3. In Xcode -> target `FoodBuddy` -> Signing & Capabilities:
- Set a Team (personal/free Apple ID is fine for local device testing).
- Ensure the bundle identifier is unique for your account/device.
4. Connect iPhone via USB (or same-network wireless debugging), unlock it, and trust the Mac.
5. On iPhone, enable Developer Mode if prompted.
6. Select your iPhone as run destination and press `Cmd+R`.

If iOS blocks first launch due to trust:

- On iPhone go to `Settings -> General -> VPN & Device Management`, trust your developer certificate, then relaunch.

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
```
