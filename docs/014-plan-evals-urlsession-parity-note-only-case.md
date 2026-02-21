# Plan 014: Evals URLSession Parity + Note-Only Case

Status: Completed on 2026-02-21.

## Goal

- Remove eval transport fallback behavior so eval calls use the same primary URLSession path as the app.
- Add a simpler eval case that uses a single note and no images.

## Approach

- Update eval runner networking to report URLSession failures directly without retrying via `curl`.
- Update case validation so a case is valid when it has at least one input source: image(s) or non-empty notes.
- Add a new notes-only fixture under `evals/cases/case-002/`.
- Update docs to match new behavior and fixture set.

## Tasks

- [x] T1: Confirm no active eval-specific plan to resume; create this plan. `Completed`
- [x] T2: Remove `curl` fallback path from `evals/Sources/FoodBuddyAIEvals/main.swift`; keep actionable URLSession diagnostics. `Completed`
- [x] T3: Update case validation to allow note-only cases (no images if notes are provided). `Completed`
- [x] T4: Add new eval fixture `evals/cases/case-002/case.json` for single-note input. `Completed`
- [x] T5: Update docs (`README.md`, `AGENTS.md`, and eval runner usage helpers if needed) to reflect URLSession-only behavior and new case. `Completed`
- [x] T6: Run targeted verification (`cd evals && swift build`) and record result. `Completed`

## Acceptance Criteria

- Evals do not execute `curl` fallback and rely on URLSession transport only.
- Timeout/cancellation/network failures are still visible in notes/artifacts.
- Case files with empty `images` are accepted when `notes` is non-empty.
- `case-002` note-only fixture is available and runnable via `make eval-run CASE=case-002`.
- Docs accurately describe the new behavior.

## Verification Results

- `cd evals && swift build` -> pass
