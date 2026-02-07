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

## Build and Test

```bash
# Generate Xcode project
xcodegen generate

# Fast verifier tests (no simulator required)
xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64' | xcbeautify
```

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
