# 006: Explicit CloudKit family-sharing boundary

- Status: Accepted
- Date: 2026-11-15

## Context

SwiftData's automatic CloudKit configuration synchronizes a private store for one iCloud account. It does not expose a family's records to separate Apple IDs, and changing the production store architecture would create migration risk.

## Decision

Keep the production SwiftData store and `.automatic` configuration unchanged. Add an explicit CloudKit custom-zone and `CKShare` boundary per family. A versioned `SharedFamily` root record carries a family-scoped snapshot as a `CKAsset`. The app validates the entire graph before reconciling it into offline SwiftData. The system acceptance callback grants transport access only; import additionally requires a complete active-family session, a signed-in Apple ID already present in the payload, or a matching unexpired role invitation code. Share creation requires administrator capability; all publication requires a complete, consistent active session. CloudKit change tags provide optimistic conflict detection, and conflicts require a fetch before retry.

The system iCloud invitation grants transport access only. App membership and role authorization remain controlled by Sign in with Apple plus the existing one-time family invitation code.

## Consequences

Existing stores require no model migration. Ledger attribution and confirmed settlement snapshots cross the sharing boundary without recalculation. Sharing is explicit rather than hidden behind SwiftData automatic sync. Whole-family snapshots provide atomic family validation but require explicit conflict recovery and are bounded by CloudKit asset limits. Production schema deployment, invitation delivery, participant removal, push behavior, and separate-account operation require physical-device verification.

## Enforced by

`FamilyCloudSharing.swift`, `FamilyCloudSharingTests.swift`, `JEMBTFamilyPointsTrackerApp.swift`, Family and sign-in sharing actions, `CKSharingSupported`, and the existing membership mutation policies.
