# Work Status

## Current objective

Complete release-readiness hardening for compact Family layout, invitation authorization, CloudKit publication migration, signed capabilities, and Watch coverage.

## Implementation state

- `AppleIDManager.createInvitation` and `addFamilyMember` now require a complete `MutationSession` and enforce family-administration authorization at the mutation boundary.
- Invitation creation rejects child, caregiver, viewer, stale, mismatched, inactive-profile, and foreign-family sessions before mutation; administrator/owner flows remain supported.
- Invitation redemption remains a separate, narrowly scoped invitee path so authorized child/viewer redemption is preserved.
- Legacy boolean CloudKit dirty markers now persist the migrated monotonic generation before storing the generation-aware publication intent.
- Family-sharing recovery errors render after member sections so transient Cloud state cannot displace the primary Family activity surface.
- The compact Family UI test again enforces the original absolute `Children.frame.minY < 220` requirement.
- Debug signing now includes Sign in with Apple. Production SwiftData/CloudKit behavior and test-only in-memory isolation are unchanged.

## Verified

- iPhone 18 Pro simulator (iOS 27.0): `iOS Unit Fast` passed 158/158.
- iPhone 18 Pro simulator (iOS 27.0): compact Family regression passed three consecutive focused runs.
- iPhone 18 Pro simulator (iOS 27.0): `iOS Complete Release` passed 177, failed 0, with the expected iPad-only test skipped (178 total).
- iPad Pro 11-inch (M5) simulator (iOS 27.2): compact Family and regular-width Add Member regressions passed 2/2.
- Apple Watch SE 3 (40mm) simulator (watchOS 27.2): Watch build passed; Watch unit/UI tests passed 4/4 using the deterministic sample environment.
- Generic iOS device Debug build passed. Its processed entitlements contain Sign in with Apple, CloudKit, push, and the expected iCloud container.
- Signed Release archive passed. Its final signed entitlements contain Sign in with Apple, declared age range, CloudKit, push, and the expected iCloud container; the archive emitted only the expected no-AppIntents-dependency metadata warning.
- Invitation role/family/session matrix and legacy dirty-marker migration tests pass as part of the unit and complete plans.
- `WatchSyncBridge.swift` compiles in the main iOS application build.

## Still required before production release

1. On two signed physical devices with different Apple IDs, verify share creation/delivery, `userDidAcceptCloudKitShareWith`, every invitation role (especially Viewer), shared-database visibility, offline edits, foreground retry, both conflict choices, participant removal, re-invitation, and strict family isolation.
2. Verify production CloudKit `SharedFamily` schema/index deployment, permissions, push propagation, and realistic snapshot asset sizes.
3. Exercise an upgraded existing installation to verify the tested legacy boolean dirty-marker migration against real persisted `UserDefaults` state.
4. Verify paired iPhone/Watch delivery and cached offline display on physical hardware; simulator Watch build and deterministic unit/UI coverage are complete.
5. Run the final archive/export and App Store submission checks with the intended distribution profile and production CloudKit environment.

## Guardrails

- Do not change production CloudKit configuration to fix UI tests.
- Do not re-enable parallel UI tests while they depend on shared simulator resources or seeded role flows.
- Do not weaken the Ledger content assertion; keep disclosure expansion and dynamic re-query behavior deterministic.
- Do not commit or push unless explicitly requested.