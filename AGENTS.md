# AGENTS

## Working Rules

- Keep `AGENTS.md` and `README.md` up to date throughout implementation work.
- Treat `docs/004-plan.md` as the active plan baseline (with `docs/003-plan.md` as implemented reference).
- Keep a current `Development Requirements` section in `README.md` (tooling, versions, setup commands).
- Keep `README.md` run guidance concise and current for local automated tests, simulator runs, and physical iPhone runs.
- For any active plan document, mark tasks `In Progress` when started.
- Keep active plan documents current with completed and blocked task status so work is resumable.
- Do not make changes outside this repository.
- Make small, focused git commits as milestones are completed.

## Rules of Engagement

- Before coding: run `xcodegen generate` to sync `FoodBuddy.xcodeproj` from `project.yml`.
- Metadata sync baseline is SwiftData + CloudKit private DB with local fallback; preserve this behavior unless the active plan says otherwise.
- Fast local verifier: run `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` (pipe to `xcbeautify` if installed).
- Iteration 004 pre-merge gate: complete `docs/004-plan.md` section 9 iPad manual smoke checklist and record pass/fail notes.
- Simulator run: open `FoodBuddy.xcodeproj`, select `FoodBuddy` scheme + iOS simulator, then `Cmd+R`.
- Physical iPhone run: if needed, enable code signing in `project.yml`, regenerate project, set Team in Xcode Signing & Capabilities, then run on device.
- When changing behavior, update/add tests first or in the same change and keep verifier green before finalizing.
- Do not commit secrets or private data to the repository. Assume we will opensource it soon.
