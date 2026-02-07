# FoodBuddy Iteration 003 Plan (iCloud Photo Sync + Reliability)

## 1. Goal

Complete cross-device parity by syncing meal photos to iCloud, while controlling storage costs and improving sync reliability.

## 2. Product Outcomes

- User sees meal photos on all signed-in devices.
- Sync behavior is resilient to offline, retries, and partial failures.
- Cloud storage usage is reasonable through controlled image sizing.

## 3. Scope

### In scope (003)

- iCloud sync for photos (binaries), not just metadata.
- Dedicated photo sync pipeline with retry/error handling.
- Photo preprocessing with downscale + compression before upload.
- Thumbnail generation for faster history rendering.
- Recovery flows for missing/stale cloud assets.
- Sync diagnostics/status improvements.

### Out of scope (for later)

- Multi-user/shared meal logs.
- Rich manual conflict resolution UX.
- Advanced media editing pipeline.

## 4. Core Decisions

- Keep metadata sync in SwiftData + CloudKit (from 002).
- Store photo payloads as separate CloudKit-backed photo asset records (decoupled from entry metadata).
- Use deterministic link between `MealEntry` and photo asset record.
- Keep local cache for offline rendering.

## 5. Photo Storage Strategy

### Upload format

- Resize full image to max long edge `1600px`.
- Encode as JPEG quality `~0.75` (tunable).
- Generate thumbnail variant (for example `320px` long edge).

### Why this strategy

- Materially reduces iCloud storage and bandwidth.
- Preserves enough visual quality for meal-log use.
- Keeps list performance high via thumbnails.

### Data model additions

- `EntryPhotoAsset`
  - `id: UUID`
  - `entryId: UUID`
  - `fullAssetRef` (CloudKit asset reference)
  - `thumbAssetRef` (CloudKit asset reference)
  - `state` (pending/uploaded/failed/deleted)
  - `lastError: String?`
  - `updatedAt: Date`

## 6. Sync Workflow

### Upload path

1. User captures/selects photo.
2. App preprocesses image (downscale/compress + thumbnail).
3. Local metadata saved immediately (local-first).
4. Background sync uploads assets.
5. Entry state transitions to synced when upload succeeds.

### Download path

1. Metadata arrives from cloud.
2. If local photo missing, enqueue asset download.
3. Show placeholder/thumbnail while full asset downloads.
4. Persist downloaded files to local cache and update state.

### Failure/retry path

- Exponential backoff retries for transient failures.
- Permanent failures shown in sync diagnostics with retry action.
- Preserve user-visible metadata even if photo transfer fails.

## 7. Milestones

### M1: Photo asset model + migration wiring

- Add `EntryPhotoAsset` model and relation to `MealEntry`.
- Add bootstrap/migration path from local-only photos.

### M2: Preprocessing pipeline

- Implement deterministic resize/compress pipeline.
- Implement thumbnail generation and storage.
- Add tests for dimension and file-size bounds.

### M3: Upload pipeline

- Queue-based uploader for pending assets.
- Retry policy and error state transitions.
- Upload status propagation to UI.

### M4: Download and hydration

- Fetch missing assets for entries synced from other devices.
- Progressive rendering (placeholder -> thumbnail -> full).

### M5: Diagnostics and recovery UX

- Add sync diagnostics surface for failed uploads/downloads.
- Add explicit retry controls.
- Add lightweight stale-asset repair routine.

### M6: Performance and hardening

- Validate memory and CPU behavior for batch sync.
- Tune cache eviction and thumbnail strategy.
- Extend automated tests and stability checks.

## 8. Acceptance Criteria

003 is complete when:

- New photos sync across at least two devices on same iCloud account.
- Existing entries from another device can hydrate missing local images.
- Photos are uploaded using constrained resolution/compression.
- History renders quickly using thumbnails.
- Sync failures are visible and retryable.
- Offline capture still works and syncs when connectivity returns.
- Automated tests for preprocessing, sync state transitions, and failure recovery pass.

## 9. Test Matrix (Automated)

### Unit tests

- Image preprocessing keeps max long edge at `1600px`.
- Compression outputs valid JPEG and expected size envelope.
- Thumbnail generation dimensions are correct.
- Sync state machine transitions (`pending -> uploaded`, `pending -> failed`, retry to success).

### Integration tests

- Local ingest to pending upload queue.
- Simulated upload success updates record state and references.
- Simulated transient failures retry with backoff.
- Metadata-only synced entry triggers download hydration.

### UI tests (targeted)

- History renders placeholder/thumbnail/full progression.
- Failed sync displays status and manual retry control.

## 10. Risks and Mitigations

- CloudKit asset upload variability (network/account).
  - Mitigation: robust retry queue, local-first writes, visible sync status.
- Storage growth over time.
  - Mitigation: controlled resolution, compression, and cache policy.
- Orphaned metadata/photo links.
  - Mitigation: periodic repair pass and integrity checks.

## 11. CI/CD Gate (003)

Minimum gate:

- `xcodegen generate`
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`

Optional extended gate:

- Targeted iOS simulator UI tests for sync status UX.

## 12. Restart Checklist

When resuming 003 work:

1. Confirm 002 metadata sync is stable and merged.
2. Mark active 003 task `In Progress` in status section.
3. Implement milestones in order (`M1` -> `M6`).
4. Keep task log and milestone statuses current.
5. Keep tests green and update docs for user-visible behavior.

## 13. Execution Status

Last updated: 2026-02-07

### Milestone Status

- M1 Photo asset model + migration wiring: `Completed`
- M2 Preprocessing pipeline: `Completed`
- M3 Upload pipeline: `Completed`
- M4 Download and hydration: `Completed`
- M5 Diagnostics and recovery UX: `Completed`
- M6 Performance and hardening: `Completed`

### Active Task Log

- [Completed] M1.1 Add `EntryPhotoAsset` model and relationships.
- [Completed] M1.2 Add local-photo migration/bootstrap behavior.
- [Completed] M2.1 Implement resize/compress pipeline.
- [Completed] M2.2 Implement thumbnail generation and cache writes.
- [Completed] M3.1 Implement upload queue and worker.
- [Completed] M3.2 Implement retry/backoff + error persistence.
- [Completed] M4.1 Implement missing-asset download queue.
- [Completed] M4.2 Implement progressive render state updates.
- [Completed] M5.1 Implement sync diagnostics screen/section.
- [Completed] M5.2 Add user-triggered retry actions.
- [Completed] M6.1 Add preprocessing/state-machine automated tests.
- [Completed] M6.2 Add sync recovery integration tests.
