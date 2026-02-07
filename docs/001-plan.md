# FoodBuddy MVP Plan (v1)

## 1. Goal

Build a minimal iOS food logger where the user can:

- Capture a new meal photo from camera.
- Pick an existing photo from iOS photo library.
- See all saved entries in history.
- View a full-size image for an entry.
- Delete an entry from history/details.

No manual metadata input in MVP (no title, no calories, no notes).

## 2. Product Scope

### In scope (MVP)

- SwiftUI iOS app.
- Single entry type: meal photo + timestamp.
- Local-only storage on device.
- History list sorted newest first.
- Detail view for single entry.
- Delete from history or detail view.
- Fast automated verification suite (unit/integration style, no UI automation).

### Out of scope (for later)

- Cloud sync.
- User authentication.
- OCR/nutrition analysis.
- Edit entry metadata.
- Search/filter.
- Albums/tags.
- Share/export.

## 3. UX Flow

### Primary flow

1. User opens app and lands on `History`.
2. User taps `Add`.
3. Action sheet shows:
   - `Take Photo`
   - `Choose from Library`
4. User captures/selects an image.
5. App saves image + metadata.
6. History updates immediately with new entry at top.

### Secondary flows

- Tap history row -> open detail with full image and date/time.
- Swipe delete in list (or trash in detail) -> entry removed.

## 4. Technical Architecture

Use a simple layered architecture with clear boundaries:

- `UI` layer (SwiftUI Views):
  - `HistoryView`
  - `EntryDetailView`
  - `CaptureActionSheet` / picker presentation logic
- `Application` layer:
  - `MealEntryService` (single entry point for ingest/list/delete)
- `Persistence` layer:
  - SwiftData model + repository wrapper
- `File storage` layer:
  - `ImageStore` for image file write/read/delete

Key rule: camera and library paths must both use the same ingest service method.

## 5. Data Model

### SwiftData entity

`MealEntry`

- `id: UUID`
- `createdAt: Date`
- `imageFilename: String`

### File storage

- Store JPEG files in app `Documents` (or app-specific subfolder, e.g. `Documents/MealImages`).
- Keep file names unique (UUID-based).
- Persist only file name/path reference in SwiftData.

## 6. Capture Strategy

- Camera: `UIImagePickerController` (wrapped with `UIViewControllerRepresentable`).
- Library: `PhotosPicker` (preferred modern SwiftUI API) or `UIImagePickerController` fallback if needed.
- Normalize to `UIImage` (or data) before ingest.
- Compress to JPEG with reasonable quality (e.g. 0.8) for size/performance balance.

## 7. Permissions

Required `Info.plist` keys:

- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

If saving back to the library is introduced later, add `NSPhotoLibraryAddUsageDescription`.

## 8. Automated Verification (Fast Core Verifier)

### Objective

Create a cheap, fast suite that catches core regressions in save/history/delete behavior.

### Scope

Test app core logic without simulator UI flows:

- Ingest creates file + DB row.
- History query returns newest-first.
- Delete removes DB row and image file.
- Delete is resilient when file is already missing.
- Camera path and library path both call the same ingest method.

### Design

- Use in-memory SwiftData container for tests.
- Use temporary directory for image files.
- Inject dependencies (`Clock`, `UUID provider`, file system paths) to make tests deterministic.
- No network.
- No UI tests in gating pipeline.

### Performance target

- Total verifier runtime under ~10 seconds on typical CI macOS runner.

### Suggested test groups

- `MealEntryServiceTests`
- `ImageStoreTests`
- Optional small integration tests wiring service + in-memory persistence + temp files

## 9. Folder/Module Layout (proposed)

```text
FoodBuddy/
  App/
    FoodBuddyApp.swift
  Features/
    History/
      HistoryView.swift
      EntryRowView.swift
    EntryDetail/
      EntryDetailView.swift
    Capture/
      CaptureSourceSheet.swift
      CameraPicker.swift
      LibraryPicker.swift
  Domain/
    MealEntry.swift
  Services/
    MealEntryService.swift
  Storage/
    MealEntryRepository.swift
    ImageStore.swift
  Support/
    Dependencies.swift
```

Tests:

```text
FoodBuddyTests/
  MealEntryServiceTests.swift
  ImageStoreTests.swift
```

## 10. Milestones

### M1: Project scaffold

- Create SwiftUI app target and basic navigation.
- Add History screen placeholder and `Add` button.

### M2: Storage foundation

- Implement SwiftData `MealEntry`.
- Implement `ImageStore`.
- Implement `MealEntryService`.

### M3: Capture integration

- Add action sheet with camera/library options.
- Wire camera and library outputs to shared ingest path.

### M4: History + detail + delete

- Render list from persisted data.
- Implement detail screen.
- Implement delete from list/detail including file cleanup.

### M5: Fast verifier

- Add automated tests for core invariants.
- Ensure CI command is stable and fast.

## 11. Acceptance Criteria

MVP is complete when:

- User can add an entry via camera.
- User can add an entry via photo library.
- New entries appear in history immediately and persist across relaunch.
- User can open full image per entry.
- User can delete entries and they are removed from history and file storage.
- Fast verifier passes and runs quickly in CI.

## 12. Risks and Mitigations

- Permission denial flows:
  - Mitigation: Show clear empty/error state and allow retry.
- File/db inconsistency:
  - Mitigation: Service owns write/delete transaction logic and handles partial failures gracefully.
- Large image memory usage:
  - Mitigation: Compress and optionally downscale before storing.

## 13. CI/CD Integration (initial)

Recommended gate command (once project exists):

- `xcodebuild test -scheme FoodBuddy -destination 'platform=iOS Simulator,name=iPhone 16'`

Keep this gate limited to the fast verifier tests only.

## 14. Restart Checklist

When resuming work, do this first:

1. Confirm this file still matches current scope.
2. Build M1 scaffold if missing.
3. Implement M2 storage/service.
4. Add M5 tests early (or alongside M2/M3).
5. Finish M3 + M4 UI wiring.
6. Validate acceptance criteria and keep verifier green.

## 15. Execution Status

Last updated: 2026-02-07

### Milestone Status

- M1 Project scaffold: `In Progress`
- M2 Storage foundation: `Pending`
- M3 Capture integration: `Pending`
- M4 History + detail + delete: `Pending`
- M5 Fast verifier: `Pending`

### Active Task Log

- [In Progress] M1.1 Create SwiftUI app target and basic navigation.
- [Pending] M1.2 Add History screen placeholder and `Add` button.
