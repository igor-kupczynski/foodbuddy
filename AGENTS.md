# AGENTS

## Planning

- All major work items require a plan document at `docs/<NNN>-plan-<slug>.md` (e.g. `docs/007-plan-ai-food-recognition.md`). Number sequentially; check existing docs to find the next free number.
- A plan document should describe the goal, approach, tasks with checkboxes, and acceptance criteria.
- Mark tasks `In Progress` when started; keep the document current with completed and blocked status so work is resumable across sessions.
- Before starting implementation, check the `docs/` directory for any active (incomplete) plan — resume it rather than duplicating work.

## Working Rules

- Keep `AGENTS.md` and `README.md` up to date throughout implementation work.
- Keep a current `Development Requirements` section in `README.md` (tooling, versions, setup commands).
- Keep `README.md` run guidance concise and current for local automated tests, simulator runs, and physical iPhone runs.
- Do not make changes outside this repository.
- Make small, focused git commits as milestones are completed.
- Do not commit secrets or private data to the repository. Assume we will opensource it soon.
- Communication baseline: repository owner is a Cloud SWE (not an Apple/iOS specialist). For Apple platform topics, explain assumptions explicitly, define Apple-specific terms, and prefer concrete step-by-step guidance over shorthand.
- We learn together: if an agent finds something especially interesting, unexpected, or a hard-won lesson, add it to the Lessons section so future runs benefit.

## Rules of Engagement

- Before coding: run `xcodegen generate` to sync `FoodBuddy.xcodeproj` from `project.yml`.
- Metadata sync baseline is SwiftData + CloudKit private DB with local fallback; preserve this behavior unless the active plan says otherwise.
- When changing behavior, update/add tests first or in the same change and keep the verifier green before finalizing.

### Running Tests

- **Fast local verifier (unit tests, macOS):** `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` (pipe to `xcbeautify` if installed).
- **iOS build check (no signing):** `xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- **UI tests (simulator):** `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddyUITests -destination 'platform=iOS Simulator,name=iPhone 17'`
- `FoodBuddyCoreTests` target is macOS-only (`SUPPORTED_PLATFORMS = macosx`). Run with `-destination 'platform=macOS'` or the `arch=x86_64` variant, not iOS Simulator destinations.

### Running the App

- **Simulator:** open `FoodBuddy.xcodeproj`, select `FoodBuddy` scheme + iOS simulator, then `Cmd+R`.
- **Physical iPhone:** follow the deterministic local phone flow in `README.md` and use `docs/APPLE_DEV_BASICS.md` for signing/capability background and troubleshooting.

## Identifier Baseline

- Keep identifier values explicit and consistent when editing signing/CloudKit settings.
- Production app bundle ID (`FoodBuddy` target): `com.igorkupczynski.foodbuddy`
- Local phone dev bundle ID (`FoodBuddyDev` target): `info.kupczynski.foodbuddy.dev`
- Test bundle ID: `com.igorkupczynski.foodbuddy.coretests`
- CloudKit container ID: `iCloud.info.kupczynski.foodbuddy` (must keep `iCloud.` prefix; container IDs are not bundle IDs)

## Lessons

- UI tests that depend on AI-off behavior should isolate keychain service name via launch environment; otherwise an existing local API key can silently change UI state and make tests flaky.
- For capture-flow UI tests, assert deterministic in-sheet state (photo count, save enabled, sheet dismissal) rather than post-save list text that can vary with async refresh timing.
- SwiftData schema evolution: when adding a new non-optional model field, give it a property-level default value (not just an init default) to reduce migration/load failures on existing stores. This applies equally to `@Relationship` arrays (e.g. `var entries: [MealEntry] = []`); the `@Model` macro requires property-level defaults to generate correct schema metadata.
- Keychain-backed settings should tolerate corrupted/non-UTF8 stored bytes by treating them as missing and self-healing the entry, rather than surfacing a generic save/load error to users.
- Simulator runtime behavior can differ from CI build flags: disable signing in CI commands via CLI override, but keep app target signing enabled by default so Keychain-backed features work during manual runs.
- When service-layer errors are caught and discarded (e.g. in a coordinator's `catch` block), persist a diagnostic string on the model so failures are debuggable. Include: error description, error type, HTTP status/response body if applicable, entity context (IDs, counts), timestamp, and `Thread.callStackSymbols`. Surface via a tappable "Show details" sheet with a Copy button to keep the default UI clean.
