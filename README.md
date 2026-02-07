# FoodBuddy

FoodBuddy is an iOS MVP for meal photo logging.

## Current Status

Project bootstrap is in progress from `docs/001-plan.md`.

## Development Requirements

### Required

- macOS with Xcode 26.2 or newer (includes `xcodebuild` and iOS Simulator).
- Swift 6.2+ toolchain (bundled with Xcode 26.2+).

### Recommended Tools

- `xcodegen` for deterministic project generation from `project.yml`.
- `xcbeautify` for readable `xcodebuild` output.
- `gh` CLI for GitHub workflows.

### Verify Installed Tooling

```bash
xcodebuild -version
swift --version
gh --version
```

### Install Missing Tools (Homebrew)

```bash
brew install xcodegen xcbeautify gh
```

### Build/Test Baseline Commands

```bash
# Generate project (once project.yml exists)
xcodegen generate

# Run tests (example destination, adjust as needed)
xcodebuild test -scheme FoodBuddy -destination 'platform=iOS Simulator,name=iPhone 16'
```

## MVP Goals

- Capture a meal photo from camera.
- Choose a meal photo from photo library.
- Persist entries locally with timestamp.
- Show newest-first history.
- Open full-size detail view.
- Delete entries and clean up image files.
- Ship fast automated tests for core save/list/delete invariants.
