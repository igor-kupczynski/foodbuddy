# Apple Dev Basics (iOS Local Runs, Signing, Capabilities)

This document is the detailed companion to `README.md` for running FoodBuddy on a physical iPhone.

## 1. Core Concepts

Apple installability depends on four things matching:

1. Bundle ID: app identity (`CFBundleIdentifier`), e.g. `info.kupczynski.foodbuddy.dev`.
2. Certificate: who signed the app (Apple Development, Apple Distribution).
3. Provisioning profile: authorization tuple (Team + Bundle ID + cert + device list + capabilities).
4. Entitlements: capability claims baked into the signed app (iCloud, push, app groups, etc.).

If one of these mismatches, install or launch fails.

## 2. Bundle ID: What It Is and How to Choose It

- It is the global identity key for the app in Apple ecosystems.
- Use reverse-DNS from a domain you control.
- Good production pattern: `info.kupczynski.foodbuddy`.
- Good local/dev pattern: `info.kupczynski.foodbuddy.dev`.

Guidelines:

- Keep production Bundle ID stable once users/data matter.
- Use separate IDs for environments with different backends/capabilities.
- Do not reuse one Bundle ID for multiple products.

## 3. Typical Team Setups

Local-only phone debugging (recommended first path):

- Team: Personal Team or org team.
- Signing: automatic in Xcode.
- Entitlements: none (for this repo, set `CODE_SIGN_ENTITLEMENTS:` blank).
- Outcome: fast local install, CloudKit disabled, app falls back to local metadata storage.

CloudKit-enabled phone debugging:

- Team: must own access to target iCloud container.
- Signing: automatic or manual.
- Entitlements: include iCloud entitlement file.
- Outcome: CloudKit metadata/photo sync validation possible.

CI/release distribution:

- Usually uses distribution certs and release provisioning, never personal-team local setup.

## 4. When Signing Is Required

Signing required:

- Running on a physical iPhone/iPad.
- TestFlight or App Store submission.
- Ad hoc or enterprise installs.

Signing not required:

- iOS simulator runs.
- Current macOS unit-test verifier flow used by this repo.

## 5. How You "Get a Key"

Recommended (automatic):

1. Add Apple ID in Xcode (`Xcode -> Settings -> Accounts`).
2. Enable "Automatically manage signing" in target settings.
3. Select Team.
4. Xcode creates/installs the needed development certificate and profile.

Notes:

- The private key is stored in your macOS Keychain.
- You usually do not manually export/import keys for local single-machine dev.

Manual path (only when needed):

1. Generate CSR in Keychain Access.
2. Create/download cert from Apple Developer portal.
3. Install cert into keychain with private key.
4. Create provisioning profile for the Bundle ID, devices, and capabilities.

## 6. Enabling iPhone Developer Mode

For iOS 16+:

1. Connect iPhone to Mac and trust the computer.
2. Attempt a run from Xcode once.
3. On iPhone: `Settings -> Privacy & Security -> Developer Mode`.
4. Enable toggle, reboot when prompted.
5. Confirm enablement after reboot.
6. Re-run from Xcode.

If Developer Mode toggle is missing, step 2 is usually the missing prerequisite.

## 7. CloudKit-Specific Notes for FoodBuddy

FoodBuddy currently references `iCloud.com.igorkupczynski.foodbuddy` in:

- `FoodBuddy/App/FoodBuddy.entitlements`
- `FoodBuddy/Support/Dependencies.swift`
- `FoodBuddy/Support/PersistenceController.swift`

If you change container name/team mapping, update all three together.

If CloudKit setup is incomplete, local-only run with blank entitlements is the fastest unblocked path.

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

- Verify iCloud capability + container entitlements + Team/container ownership alignment.

## 9. Practical Default for This Repo

For "just run on my phone now":

1. Use Bundle ID `info.kupczynski.foodbuddy.dev`.
2. Enable signing in `project.yml`.
3. Clear entitlements (`CODE_SIGN_ENTITLEMENTS:` blank).
4. Regenerate project and run from Xcode on device.

Then re-enable CloudKit entitlements only when you specifically need CloudKit behavior validation.
