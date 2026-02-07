# FoodBuddy Iteration 004 Plan (iPad Readiness + Adaptive UI)

## 1. Goal

Make FoodBuddy feel native and reliable on iPad while preserving existing iPhone behavior and the 003 sync baseline.

## 2. Product Outcomes

- App is fully usable on iPad in portrait and landscape.
- iPad experience is optimized for browsing and editing existing entries.
- Primary navigation scales to regular-width layouts without awkward single-column stretching.
- New entry flow remains available on iPad as a secondary, reliable path.
- Capture and management flows present correctly on iPad (no modal/presentation crashes, no blocked flows).
- Existing photo sync and metadata behavior remains unchanged.

## 3. Scope

### In scope (004)

- Browse/edit-first iPad information architecture.
- Adaptive root navigation for iPhone vs iPad size classes.
- iPad-friendly presentation patterns for capture and management flows.
- Wide-layout improvements for history, meal detail, and entry detail screens, with editing ergonomics prioritized.
- iPad-focused validation and regression coverage.
- Documentation updates for iPad run/test guidance.

### Out of scope (for later)

- New product features unrelated to iPad adaptation.
- iPad multitasking-specific optimizations (Stage Manager tuning, multiwindow).
- Major visual redesign outside adaptive layout/readability improvements.

## 4. Current-State Gaps

- Root app shell is `NavigationStack` only, which scales poorly on regular-width iPad.
- Screen flows rely on stacked sheets and compact-style defaults not tuned for iPad ergonomics.
- Detail screens are optimized for phone-width vertical flow and need regular-width layout rules.
- iPad-specific verification is not part of current quality gates.

## 5. Core Decisions

- Keep one universal iOS target (`TARGETED_DEVICE_FAMILY: "1,2"`), no separate iPad app target.
- Preserve 003 storage/sync architecture (SwiftData + CloudKit metadata, CloudKit photo assets).
- Adaptive navigation contract:
  - Compact width: keep existing `NavigationStack` flow.
  - Regular width: use persistent `NavigationSplitView`.
- Regular-width iPad entry detail is two-column in 004:
  - Left: image/content pane.
  - Right: metadata and edit actions pane (`loggedAt`, save, retry sync, delete).
  - Fallback to single-column in compact width and accessibility-driven constrained layouts.
- iPad validation strategy in 004:
  - Keep existing automated gate (unit/integration on macOS destination).
  - Require manual iPad simulator smoke checklist before merge.
  - Defer in-repo iPad UI automation to 005.
- Make modal presentation explicit where needed for iPad safety and clarity.

## 6. UX Adaptation Plan

### Navigation and information architecture

- Regular width (`NavigationSplitView`) is browse/edit first:
  - Sidebar: meal history list and global actions.
  - Content: selected meal with entries.
  - Detail: selected entry details with edit controls.
- Keep meal-first browsing with fast drill-down from meals to entries to entry detail.
- Maintain current iPhone navigation flow to avoid regressions.

### Screen-level layout adjustments

- `HistoryView`: optimize list composition for wide widths and persistent selection.
- `MealDetailView`: ensure row density/spacing works on larger canvas and split content column.
- `EntryDetailView`: implement regular-width two-column composition with clear editing affordances.

### Modal and capture behavior

- Ensure capture source chooser, camera/library picker, meal type chooser, and diagnostics/management modals present safely on iPad.
- Treat new entry on iPad as secondary but fully supported.
- Standardize detents/sizing behavior where beneficial for large screens.

## 7. Milestones

### M1: iPad baseline and shell refactor

- Introduce adaptive root container (`compact` vs `regular` behavior).
- Add selection state plumbing required for split navigation.
- Keep iPhone push navigation intact.
- Deliverable: root app shell chooses `NavigationStack` (compact) or `NavigationSplitView` (regular) at runtime.

### M2: History + detail adaptive navigation

- Connect history selection to meal detail in regular-width layout.
- Preserve entry drill-down behavior and back-compat for compact width.
- Validate empty/loading/error states in both size classes.
- Deliverable: selecting a meal updates content column; selecting an entry updates detail column.

### M3: iPad-safe presentations and capture flow

- Audit and harden all `.sheet` / dialog presentation paths for iPad.
- Ensure camera/library flows remain functional and cancellable on iPad.
- Confirm management and diagnostics modals remain accessible in split layout.
- Deliverable: no presentation warnings/crashes across capture and management flows on iPad simulator.

### M4: Wide-layout polish

- Improve spacing, max widths, and visual hierarchy for large screens.
- Implement two-column `EntryDetailView` on regular width with image pane + edit pane.
- Resolve truncation/clipping issues under larger Dynamic Type sizes.
- Deliverable: browse/edit paths remain readable and efficient in portrait and landscape.

### M5: Verification and regression hardening

- Add/update automated coverage for new adaptive shell logic.
- Add targeted iPad simulator validation checklist and execute it.
- Run full verifier and resolve behavior regressions.
- Deliverable: automated gate green + checklist pass evidence recorded in PR notes.

### M6: Documentation and rollout readiness

- Update `README.md` run guidance for iPad simulator validation.
- Keep `AGENTS.md` and `docs/004-plan.md` execution status current.
- Capture any deferred follow-ups for 005.
- Deliverable: docs describe required iPad validation steps and any deliberate 005 deferrals.

## 8. Acceptance Criteria

004 is complete when:

- App launches and is fully functional on iPad in portrait and landscape.
- Navigation is adaptive: compact behavior on iPhone, split-style behavior on regular-width iPad.
- iPad browse/edit flows are first-class: browse meals, open entries, edit `loggedAt`, save, delete, retry sync.
- `EntryDetailView` uses two-column layout on regular-width iPad and remains usable in compact/accessibility fallbacks.
- Capture, meal type selection, sync diagnostics, and management flows present correctly on iPad.
- History, meal detail, and entry detail are readable and usable without phone-style stretched layouts.
- 003 sync behavior remains intact (no metadata/photo sync regressions).
- Automated verifier passes and required iPad simulator smoke checks are documented/executed.

## 9. Test Matrix

### Unit / integration

- Adaptive navigation state transitions (selection, detail routing, fallback behavior).
- Existing ingest/edit/delete/sync tests remain green after shell changes.

### Required iPad manual smoke checklist

1. iPad portrait: browse meals -> select meal -> select entry -> edit `loggedAt` -> save.
2. iPad landscape: verify split navigation stays stable while switching meal and entry selections.
3. iPad portrait or landscape: delete entry from detail view and confirm navigation/selection recovers.
4. iPad portrait or landscape: open sync diagnostics and meal type management from toolbar.
5. iPad portrait or landscape: run one library ingest flow end-to-end (select photo, choose meal type, save).
6. iPad portrait or landscape: trigger retry for failed photo asset (or verify retry control hidden when not needed).

## 10. Risks and Mitigations

- Navigation state complexity across compact/regular modes.
  - Mitigation: isolate adaptive shell state and keep feature views reusable.
- iPad modal behavior inconsistencies.
  - Mitigation: explicit presentation rules and simulator verification for each flow.
- Regressions in existing iPhone UX.
  - Mitigation: keep compact path close to current implementation and rerun full verifier.

## 11. CI/CD Gate (004)

Minimum gate:

- `xcodegen generate`
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`

Required pre-merge manual gate:

- Complete section 9 iPad smoke checklist and record pass/fail notes in the PR description.

## 12. Finalized Decisions (Locked)

- Regular-width iPad uses persistent `NavigationSplitView` by default.
- iPad usage priority is browse/edit; entry creation remains secondary but fully supported.
- `EntryDetailView` is two-column on regular-width iPad in 004.
- iPad UI automation is deferred to 005; 004 requires documented manual iPad smoke validation.

## 13. Restart Checklist

When resuming 004 work:

1. Re-read locked decisions in section 12; do not reopen scope unless a blocker appears.
2. Mark the active task `In Progress` in section 14.
3. Implement milestones in order (`M1` -> `M6`) unless blocked.
4. Keep status/task log updated during execution.
5. Keep verifier green and update docs with user-visible behavior.

## 14. Execution Status

Last updated: 2026-02-07

### Milestone Status

- M1 iPad baseline and shell refactor: `Completed`
- M2 History + detail adaptive navigation: `Completed`
- M3 iPad-safe presentations and capture flow: `Completed`
- M4 Wide-layout polish: `Completed`
- M5 Verification and regression hardening: `In Progress`
- M6 Documentation and rollout readiness: `Completed`

### Active Task Log

- [Completed] M6.1 Draft and publish `docs/004-plan.md`.
- [Completed] M6.2 Finalize locked iPad scope decisions (section 12).
- [Completed] M1.1 Implement adaptive app shell for compact vs regular width.
- [Completed] M2.1 Wire meal selection state for split navigation.
- [Completed] M3.1 Harden capture and modal presentation paths on iPad.
- [Completed] M4.1 Polish history/detail layouts for wide screens.
- [Completed] M5.1 Add iPad validation coverage and rerun verifier.
- [Completed] M5.2 Add `HistorySelectionState` unit coverage for adaptive split selection behavior.
- [Blocked] M5.3 Execute section 9 iPad manual smoke checklist and record notes (requires interactive simulator run).
- [Completed] M6.3 Update `README.md` with explicit iPad smoke validation run guidance.
