# FoodBuddy Iteration 005 Plan (Viewport Reliability + Capture Presentation + Meal-Type Reassignment)

## 1. Goal

Fix three user-facing regressions observed on physical iPhone:

- App renders in a legacy-looking letterboxed viewport (black top/bottom bars, oversized UI scale).
- Camera capture UI appears partially hidden/cropped.
- Entry detail flow does not provide a direct way to move an existing entry to another meal type.

Also add automated guardrails so these regressions are caught before merge.

## 2. Why This Happened (Root Cause Context)

### A. Letterboxed / old-iPhone scale UI

Observed behavior matches iOS compatibility viewport mode:

- The app UI appears centered inside a smaller canvas.
- Top and bottom black bars are visible.
- Text and controls look scaled as if for much older device geometry.

Likely root cause in repo state:

- `FoodBuddy/App/Info.plist` does not define a launch screen key (`UILaunchStoryboardName` or modern `UILaunchScreen` dictionary).

Apple context:

- **Launch screen** is the startup interface metadata iOS uses to infer app window compatibility with modern device sizes.
- Without proper launch screen configuration, iOS can run the app in a compatibility viewport on some devices.

### B. Camera view partially hidden

Camera currently presents via `.fullScreenCover` (`FoodBuddy/Features/History/HistoryView.swift`).

Important behavior:

- `.fullScreenCover` can only fill the app window that owns it.
- If the app window is already letterboxed (A), camera also appears clipped inside that reduced window.

Possible secondary contributor:

- Presentation timing from a `confirmationDialog` to `fullScreenCover` transition can produce transient layout/presentation oddities; we should harden sequencing.

### C. No move-to-another-meal-type action for existing entries

Current entry editing supports:

- Date/time edit (`loggedAt`) with reassignment confirmation when day boundary changes.

Current limitation:

- Reassignment logic keeps meal type fixed and only changes meal/day grouping.
- No UI control in `EntryDetailView` for changing meal type.
- No explicit service method for cross-type moves.

## 3. Product Outcomes

- App always uses full native device viewport on modern iPhone/iPad (no compatibility letterboxing).
- Camera presentation is fully visible and cancellable.
- Users can move an existing entry to another meal type from entry detail.
- CI/local verifier includes automated checks that prevent launch-screen and capture-presentation regressions.

## 4. Scope

### In scope (005)

- Launch screen configuration hardening for both app targets.
- Capture presentation sequencing hardening (dialog -> modal presentation).
- Entry detail meal-type reassignment UX + service support.
- Automated static and UI checks to catch viewport/capture regressions.
- Documentation updates (`README.md`, plan status).

### Out of scope (later)

- Full camera stack rewrite to `AVCaptureSession`.
- iPad multitasking-specific camera behavior tuning.
- Broader visual redesign.

## 5. Assumptions and Terms (Apple-Specific)

- **Compatibility viewport mode**: iOS runs app content in a reduced legacy-sized window, often showing black bars.
- **`fullScreenCover`**: SwiftUI modal intended to occupy full app window.
- **Physical camera path**: real device only; iOS Simulator often lacks live camera capture.
- We keep current architecture (SwiftUI + SwiftData + CloudKit metadata/photo sync baseline from 003/004).

## 6. Milestones

### M1: Viewport compatibility fix

- Add launch screen configuration for app targets (production + dev).
- Regenerate project (`xcodegen generate`) and validate generated settings.
- Verify on physical iPhone that app content fills full screen.

Deliverable:

- No black bars; no legacy scaling on app launch.

### M2: Capture presentation hardening

- Keep capture presentation from stable presenter context.
- Ensure deterministic transition after source selection (avoid overlapping presenter states).
- Validate camera cancel/save paths remain functional.

Deliverable:

- Camera UI fully visible; no half-hidden presentation.

### M3: Entry meal-type reassignment feature

- Add meal-type selector in `EntryDetailView`.
- Add explicit service API to move entry across meal types while preserving timestamps and data integrity.
- Add confirmation UX for cross-type moves and handle meal cleanup when source meal becomes empty.

Deliverable:

- User can move existing entry to another meal type from detail screen.

### M4: Automation and regression guardrails

- Add static config test/script:
  - Assert launch screen key is present in app metadata for iOS targets.
  - Fail fast in verifier if missing.
- Add UI test seam for capture flow:
  - Inject mock camera view under UI-test launch argument.
  - Exercise Add -> Take Photo path without hardware camera dependency.
  - Assert presented capture view is full-window and primary controls are hittable.
- Add UI screenshot heuristic check (optional but recommended):
  - Fail when top/bottom black-bar ratio exceeds threshold in known light background screen.

Deliverable:

- Regression that reintroduces launch-screen omission or clipped capture is caught automatically.

### M5: Verification + docs

- Run fast verifier + new automated checks.
- Execute physical iPhone smoke checks for viewport and camera.
- Update `README.md` test guidance with new automated checks and mock-camera UI test path.

Deliverable:

- Repeatable local and CI steps that cover this regression class.

## 7. Test Matrix (005)

### Automated

- Existing:
  - `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`
- New:
  - Launch-screen config assertion test/script.
  - UI test: Add -> Take Photo using mock camera provider.
  - Unit tests for cross-type move behavior:
    - move to existing destination meal.
    - move to newly created destination meal.
    - source meal cleanup when empty.
    - no-op behavior when selecting same type.

### Manual (required)

1. iPhone portrait: launch app and verify no black bars.
2. iPhone portrait/landscape: open camera from Add and verify full visible preview + controls.
3. Move entry to another meal type in detail and verify history grouping updates correctly.
4. Re-run 004 iPad checklist section 9 to ensure no adaptive regressions.

## 8. Risks and Mitigations

- Risk: launch-screen changes differ between `FoodBuddy` and `FoodBuddyDev`.
  - Mitigation: automated per-target config assertions.
- Risk: camera flow test flakiness due to hardware dependency.
  - Mitigation: mock camera view under UI-test launch argument.
- Risk: reassignment introduces data integrity bugs.
  - Mitigation: unit tests at service layer + delete-empty-meal invariants.

## 9. CI/CD Gate (005)

Minimum gate:

- `xcodegen generate`
- macOS unit/integration verifier command from section 7
- new launch-screen config assertion step
- new UI test subset for capture presentation (mock camera path)

Required pre-merge manual gate:

- Physical iPhone smoke checks from section 7.

## 10. Execution Status

Last updated: 2026-02-08

### Milestone Status

- M1 Viewport compatibility fix: `Completed`
- M2 Capture presentation hardening: `Completed`
- M3 Entry meal-type reassignment feature: `Completed`
- M4 Automation and regression guardrails: `Completed`
- M5 Verification + docs: `In Progress`

### Active Task Log

- [Completed] M0.1 Document 005 root causes and remediation strategy.
- [Completed] M1.1 Add launch screen configuration and verify generated settings.
- [Completed] M2.1 Harden capture presentation sequencing.
- [Completed] M3.1 Add entry detail meal-type move action and service support.
- [Completed] M4.1 Add launch-screen config assertion automation.
- [Completed] M4.2 Add mock-camera UI regression test for capture presentation.
- [Completed] M5.1 Run verifier and record physical iPhone smoke results.
- [Blocked] M5.2 Execute physical iPhone smoke checklist from section 7 (requires local device/manual run).
