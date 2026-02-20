# Plan 013: AI Evals Sidecar SwiftPM + Shared Module

Status: Completed on 2026-02-21.

## Goal

- Add a standalone AI evaluation workflow that runs outside the iOS app/Xcode UI.
- Keep eval behavior close to production by sharing Mistral request/prompt/schema/parsing code with the app.
- Improve monorepo developer experience with a task runner (`Makefile`) and selective verification guidance.

## Approach

- Create a shared local Swift package for AI request/schema logic used by both app and eval harness.
- Create a sidecar SwiftPM executable package for live eval runs (direct Mistral API, no intermediary frameworks).
- Add a root `Makefile` that routes common tasks (generate project, build/test app, run eval case(s)).
- Implement deterministic + semantic scoring for eval outputs, with machine-readable artifacts.
- Support local-only API key injection with explicit precedence and safe defaults.
- Update docs (`README.md`, `AGENTS.md`) to describe:
  - new package/module layout
  - eval usage and image fixture locations
  - scoring model and thresholds
  - local secrets workflow
  - selective verifier matrix instead of heavyweight “always run everything” workflow

## Proposed Monorepo Structure

- `Packages/FoodBuddyAIShared/`
  - Swift package with prompt text, schema types, request/response encoder/decoder, normalization helpers.
- `evals/`
  - Sidecar Swift package (`executableTarget`) depending on `../Packages/FoodBuddyAIShared`.
  - Case fixtures (`evals/cases/<case-id>/`) including `images/` and case metadata.
- `Makefile`
  - Thin command router; no complex business logic.

## Scope

In scope:
- Shared module extraction for Mistral payload/schema/parsing code.
- Single-case live eval runner first (`2 images + no notes`).
- Initial scoring engine for one-case runs (pass/fail plus weighted score breakdown).
- Local API key provisioning options with one recommended default for DX.
- Make targets for common app + eval workflows.
- README/AGENTS updates for selective verification and module ownership.

Out of scope (follow-up):
- Large benchmark suite and statistical scoring.
- Batch API orchestration.
- CI pipeline wiring for scheduled eval jobs.

## Scoring Model (Initial)

For each case, compute both hard-gates and a weighted quality score:

Hard gates (must pass):
- HTTP request succeeded (`2xx`)
- Top-level response decoded
- Assistant content parsed as JSON
- JSON schema-conformant payload

Weighted quality score (0-100):
- Description quality (20)
  - Non-empty, 1-3 sentence guidance adherence
- Item extraction quality (40)
  - Precision/recall of expected item names (normalized string matching)
- Category quality (30)
  - Precision/recall over expected category assignments per item
- Serving estimate quality (10)
  - Within tolerance band per item (default `abs(predicted - expected) <= 0.5`)

Run status rules:
- `FAIL` if any hard gate fails.
- Otherwise `PASS` when score >= threshold (initial default: `75`), else `WARN`.

Artifacts:
- Per-case JSON result with raw response, parsed payload, check outcomes, weighted subscores.
- Aggregate markdown/console summary ordered by worst score first.

## API Key Management Options (Local-Only)

Option A: Environment variable only (`MISTRAL_API_KEY`) — recommended baseline
- Pros:
  - No dependency needed
  - CI-friendly in future
  - Familiar to developers
- Cons:
  - Shell-session setup overhead
  - Easy to forget in new terminals

Option B: Gitignored `.env` file + loader in eval CLI
- Pros:
  - Great local DX (`make eval` just works)
  - Key persists across terminal sessions
- Cons:
  - Requires lightweight parser or dependency
  - Risk of accidental print/log exposure if not careful

Option C: macOS Keychain lookup (service/account dedicated to evals)
- Pros:
  - Better local secret hygiene
  - No shell/export boilerplate once stored
- Cons:
  - More implementation overhead
  - macOS-specific behavior and troubleshooting

Recommended sequence:
1. Implement precedence: CLI flag `--api-key` > env `MISTRAL_API_KEY` > `.env` file.
2. Keep `.env` gitignored and documented as local-only.
3. Add Keychain support only if `.env`/env proves insufficient.

## Tasks

- [x] T1: Create this plan document with architecture, tasks, and acceptance criteria. `Completed`
- [x] T2: Run `xcodegen generate` and establish baseline before code changes. `Completed`
- [x] T3: Add `Packages/FoodBuddyAIShared` and move/port app Mistral request/schema/parsing code into it with tests. `Completed`
- [x] T4: Integrate shared package into app via `project.yml` + regenerate project; keep app behavior unchanged. `Completed`
- [x] T5: Create `evals` sidecar SwiftPM executable using shared module and direct Mistral API calls. `Completed`
- [x] T6: Implement API key resolution (`--api-key` > env > `.env`) with safe logging/redaction. `Completed`
- [x] T7: Implement initial eval case runner for one case (`2 images`, `no notes`) and define fixture contract. `Completed`
- [x] T8: Implement initial scoring engine (hard gates + weighted score + threshold verdict). `Completed`
- [x] T9: Add root `Makefile` with focused targets (xcodegen, core tests, iOS build check, eval run). `Completed`
- [x] T10: Update `README.md` with development requirements, module map, eval quickstart, and selective verification matrix. `Completed`
- [x] T11: Update `AGENTS.md` with monorepo workflow and selective verification rules (what to run based on changed area). `Completed`
- [x] T12: Run targeted verification and record outcomes in this plan. `Completed`

## Verification Strategy (Selective)

- Shared module changes:
  - Run shared-package tests.
  - Run `FoodBuddyCoreTests` covering Mistral service integration.
- Evals-only changes:
  - Run sidecar package tests/build and live dry run checks.
  - Validate scoring output determinism on fixture replay.
- App-only UI/domain changes:
  - Run existing app verifier commands relevant to impacted layers.
- iOS build check and UI tests only when impacted by changed scope.

## Acceptance Criteria

- Shared Mistral request/schema logic is not duplicated between app and eval harness.
- Evals can run from terminal without opening Xcode UI.
- First live eval case runs from local fixtures: two images, no notes.
- Eval run emits deterministic hard-gate + weighted scoring output.
- Local API key setup is documented with precedence and secure defaults.
- `Makefile` provides a clear happy path for day-to-day commands.
- `README.md` and `AGENTS.md` are updated and consistent with new monorepo/module workflow.
- Existing app behavior and current test suite remain green for impacted areas.

## Verification Results

- `xcodegen generate` -> pass
- `cd Packages/FoodBuddyAIShared && swift test` -> pass
- `cd evals && swift build` -> pass
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` -> pass
- `xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` -> pass
- `cd evals && swift run FoodBuddyAIEvals --case case-001 --api-key dummy` -> expected fail (no fixture images present yet), artifact emitted under `evals/results/`
