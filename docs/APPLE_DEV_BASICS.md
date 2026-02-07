# Apple Dev Basics (iOS Local Runs, Signing, Capabilities)

This document is the detailed companion to `README.md` for running FoodBuddy on a physical iPhone.

## 1. Quick Mental Model (Cloud SWE Mapping)

Apple concepts are strict identity and policy checks at install time and runtime.

1. Team ID: account/tenant owner in Apple Developer Program.
2. Bundle ID (`CFBundleIdentifier`): app identity key, for example `com.igorkupczynski.foodbuddy`.
3. Certificate: signing key material proving who built the binary.
4. Provisioning profile: policy bundle that binds Team + Bundle ID + certificate + devices + capabilities.
5. Entitlements: capability claims embedded in the signed app (iCloud, push, app groups, etc.).
6. CloudKit container ID: cloud data namespace, for example `iCloud.info.kupczynski.foodbuddy`.

If these do not align, install fails, launch fails, or cloud APIs fail at runtime.

## 2. FoodBuddy Identifier Baseline

Current repo baseline:

1. App target bundle ID in `project.yml`: `com.igorkupczynski.foodbuddy`.
2. Local phone dev guidance in `README.md`: override bundle ID to `info.kupczynski.foodbuddy.dev`.
3. CloudKit container ID: `iCloud.info.kupczynski.foodbuddy`.

CloudKit container references in this repo:

- `FoodBuddy/App/FoodBuddy.entitlements`
- `FoodBuddy/Support/Dependencies.swift`
- `FoodBuddy/Support/PersistenceController.swift`

Rules:

- Container IDs must keep the `iCloud.` prefix.
- Bundle ID and container ID are different namespaces.
- One container can be shared by multiple bundle IDs if entitlements and Team ownership allow it.

## 3. Local Team Setups

Local-only phone debugging (fastest path):

- Team: Personal Team or org team.
- Signing: automatic in Xcode.
- Entitlements: none (set `CODE_SIGN_ENTITLEMENTS:` blank for local-only mode in this repo).
- Outcome: app installs quickly; CloudKit is disabled; metadata falls back locally.

CloudKit-enabled phone debugging:

- Team: must have access to `iCloud.info.kupczynski.foodbuddy`.
- Signing: automatic or manual.
- Entitlements: include `FoodBuddy/App/FoodBuddy.entitlements`.
- Outcome: CloudKit metadata/photo sync path is exercised.

## 4. When Signing Is Required

Signing required:

- Running on physical iPhone/iPad.
- TestFlight uploads/installations.
- App Store distribution.

Signing not required:

- iOS Simulator runs.
- Current macOS unit-test verifier flow used by this repo.

## 5. How You Get Signing Material

Recommended path (automatic):

1. Add Apple ID in Xcode (`Xcode -> Settings -> Accounts`).
2. Enable "Automatically manage signing" in the target.
3. Select Team.
4. Xcode creates or updates development certificates/profiles.

Notes:

- Private keys are stored in macOS Keychain.
- Manual certificate/profile management is usually unnecessary for local single-machine development.

Manual path (only when needed):

1. Generate CSR in Keychain Access.
2. Create/download certificates in Apple Developer portal.
3. Install cert + private key.
4. Create provisioning profile for Bundle ID, devices, and capabilities.

## 6. Enable iPhone Developer Mode (iOS 16+)

1. Connect iPhone to Mac and trust the computer.
2. Attempt one run from Xcode.
3. On iPhone: `Settings -> Privacy & Security -> Developer Mode`.
4. Enable toggle, reboot, confirm.
5. Re-run from Xcode.

If Developer Mode toggle is missing, step 2 is usually the missing prerequisite.

## 7. Typical Path: Dev -> Beta Users -> App Store

Recommended flow for this repo:

1. Local dev (Debug):
   - Use dev bundle ID (`info.kupczynski.foodbuddy.dev`) for phone debugging.
   - Start with local-only mode (blank entitlements) to unblock install/run quickly.
   - Enable CloudKit entitlements when you need cloud behavior validation.
2. Pre-beta hardening:
   - Switch to release identity (production bundle ID for distribution app record).
   - Validate signing, capabilities, and runtime behavior in Release builds.
   - If CloudKit schema changed, deploy schema/indexes from CloudKit Development to CloudKit Production.
3. Internal beta (TestFlight internal testers):
   - Archive in Xcode (`Release`), upload to App Store Connect.
   - Add internal testers (App Store Connect users).
4. External beta (TestFlight external testers):
   - Submit build for Beta App Review.
   - After approval, invite external testers and monitor feedback/crash reports.
5. App Store release:
   - Submit production build for App Review.
   - Choose manual or phased release after approval.

Operational guidance:

- Keep dev and release bundle IDs separate.
- Keep release/TestFlight builds on the production bundle ID.
- Do not treat a last-minute identifier rename as a release step; bake identifiers into configurations early.

## 8. Troubleshooting Quick Map

"Signing for FoodBuddy requires a development team":

- Select Team in target Signing settings.

"No profiles for ... were found":

- Turn on automatic signing, verify Bundle ID uniqueness, reconnect device.

"Provisioning profile doesn't include iCloud capability":

- Use local-only mode (blank entitlements), or reconfigure container/capability for your Team.

"Unable to install app on device":

- Confirm Developer Mode is enabled and device is unlocked/trusted.

"CloudKit calls fail at runtime":

- Verify iCloud capability + container entitlement + Team/container ownership alignment.

## 9. Practical Default for This Repo

For "just run on my phone now":

1. Use bundle ID `info.kupczynski.foodbuddy.dev` in Xcode Signing.
2. Keep signing automatic with your Team.
3. Clear entitlements (`CODE_SIGN_ENTITLEMENTS:` blank).
4. Run `xcodegen generate`.
5. Run from Xcode on iPhone.

Then re-enable CloudKit entitlements only when you specifically need CloudKit validation.
