# FoodBuddy Iteration 006 Plan (Capture Sheet Blank-on-First-Pick Fix)

## Problem Summary

Observed behavior:

- After selecting a photo (library or camera path), the next "Save Meal" step sometimes opens as a blank white sheet.
- Retrying immediately often works on the second attempt.

Impact:

- Intermittent ingest interruption on both simulator and physical iPhone.
- User sees an empty modal with no visible controls.

## Root Cause

This was a modal state race in capture presentation:

- Sheet visibility was driven by a boolean while payload data (`pendingImage`) was optional.
- During picker dismissal, the boolean could become active while payload was not safely bound to the sheet content.
- Result: the sheet was presented without renderable content.

## Solution

Implemented fixes:

1. Use payload-driven sheet presentation in `HistoryView`.
   - Replace boolean-based `sheet(isPresented:)` for meal-type selection with `sheet(item:)` bound to an explicit `PendingCapture`.
   - Ensure the sheet can only present when image+timestamp payload exists.

2. Sequence picker callbacks after dismiss.
   - Camera picker, library picker, and mock camera now dismiss first, then dispatch image callback on the next main-loop turn.
   - This prevents nested modal transitions from racing.

3. Add explicit regression coverage.
   - UI test verifies `Use Mock Photo` transitions to visible Save Meal controls (not a blank sheet).

## Verification

Automated checks run:

- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddyUITests -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FoodBuddyUITests/CapturePresentationUITests`
- `./scripts/assert-launch-screen-config.sh`

Manual follow-up:

- Re-run first-attempt ingest on physical iPhone (library and camera) and confirm Save Meal sheet renders controls on first try.
