# AGENTS

## Working Rules

- Keep `AGENTS.md` and `README.md` up to date throughout implementation work.
- Treat `docs/007-plan-ai-food-recognition.md` as the active plan baseline (with `docs/006-plan-capture-sheet-blank-first-pick.md` as implemented reference).
- Keep a current `Development Requirements` section in `README.md` (tooling, versions, setup commands).
- Keep `README.md` run guidance concise and current for local automated tests, simulator runs, and physical iPhone runs.
- For any active plan document, mark tasks `In Progress` when started.
- Keep active plan documents current with completed and blocked task status so work is resumable.
- Do not make changes outside this repository.
- Make small, focused git commits as milestones are completed.
- Communication baseline: repository owner is a Cloud SWE (not an Apple/iOS specialist). For Apple platform topics, explain assumptions explicitly, define Apple-specific terms, and prefer concrete step-by-step guidance over shorthand.
- We learn together: if an agent finds something especially interesting, unexpected, or a hard-won lesson, add it here so future runs benefit.

## Rules of Engagement

- Before coding: run `xcodegen generate` to sync `FoodBuddy.xcodeproj` from `project.yml`.
- Metadata sync baseline is SwiftData + CloudKit private DB with local fallback; preserve this behavior unless the active plan says otherwise.
- Fast local verifier: run `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` (pipe to `xcbeautify` if installed).
- Iteration 007 automated gate: run `./scripts/assert-launch-screen-config.sh`, `xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`, `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`, and `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddyUITests -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FoodBuddyUITests/CapturePresentationUITests`.
- Iteration 007 manual gate: capture a meal on physical iPhone, verify AI description appears, edit notes, re-analyze, and record pass/fail notes. Real API-key validation is required for this gate.
- Simulator run: open `FoodBuddy.xcodeproj`, select `FoodBuddy` scheme + iOS simulator, then `Cmd+R`.
- Physical iPhone run: follow the deterministic local phone flow in `README.md` and use `docs/APPLE_DEV_BASICS.md` for signing/capability background and troubleshooting.
- When changing behavior, update/add tests first or in the same change and keep verifier green before finalizing.
- Do not commit secrets or private data to the repository. Assume we will opensource it soon.

## Identifier Baseline

- Keep identifier values explicit and consistent when editing signing/CloudKit settings.
- Current production app target bundle ID in `project.yml` (`FoodBuddy`): `com.igorkupczynski.foodbuddy`.
- Current local phone dev target bundle ID in `project.yml` (`FoodBuddyDev`): `info.kupczynski.foodbuddy.dev`.
- Current test bundle ID in `project.yml`: `com.igorkupczynski.foodbuddy.coretests`.
- Current CloudKit container ID: `iCloud.info.kupczynski.foodbuddy` (must keep `iCloud.` prefix; container IDs are not bundle IDs).


## Lessons
- Add notable discoveries and hard-won lessons here as short, practical notes.
- UI tests that depend on AI-off behavior should isolate keychain service name via launch environment; otherwise an existing local API key can silently change UI state and make tests flaky.
- For capture-flow UI tests, assert deterministic in-sheet state (photo count, save enabled, sheet dismissal) rather than post-save list text that can vary with async refresh timing.
- SwiftData schema evolution: when adding a new non-optional model field, give it a property-level default value (not just an init default) to reduce migration/load failures on existing stores. This applies equally to `@Relationship` arrays (e.g. `var entries: [MealEntry] = []`); the `@Model` macro requires property-level defaults to generate correct schema metadata.
- Keychain-backed settings should tolerate corrupted/non-UTF8 stored bytes by treating them as missing and self-healing the entry, rather than surfacing a generic save/load error to users.
- Simulator runtime behavior can differ from CI build flags: disable signing in CI commands via CLI override, but keep app target signing enabled by default so Keychain-backed features work during manual runs.
