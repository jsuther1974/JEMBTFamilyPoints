# JEMBT Family Points Tracker

Native SwiftUI starter for the Suguiluz family point system. The design replaces
the spreadsheet's expanding weekly columns with an auditable ledger: every
award, penalty, reward purchase, approval, parent-pot allocation, and weekly
settlement is a dated record.

## Project guidance

- Architecture and boundaries: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Architecture decisions: [`docs/decisions/README.md`](docs/decisions/README.md)
- Verified product behavior: [`docs/PRODUCT_RULES.md`](docs/PRODUCT_RULES.md)
- Test strategy and release matrix: [`docs/TESTING.md`](docs/TESTING.md)
- Human/agent collaboration: [`AGENTS.md`](AGENTS.md)
- Current temporary handoff: [`WORK_STATUS.md`](WORK_STATUS.md)
- Soundtrack provenance: [`SOUNDTRACK_PROVENANCE.md`](SOUNDTRACK_PROVENANCE.md)

## First-version behavior

- Supports iPhone and iPad with a shared SwiftUI codebase.
- Seeds Mateo, Emilio, Daddy, and Papa from the existing spreadsheet.
- Calculates each child's Saturday age and grants `age * 100` starting points.
- Lets children submit activities for parent approval.
- Lets parents approve, reject, or directly record entries.
- Treats parent penalties as a weekly pot divided evenly between the children.
- Records reward purchases as negative point entries.
- Prepares Sunday settlement drafts for parent confirmation.
- Converts positive points at `100 points = $1`.
- Carries a negative child balance into the following week as debt.
- Stores a settlement snapshot so historical results do not change when rules
  are edited later.

## Important implementation choice

SwiftData remains the durable offline ledger and keeps its existing `.automatic` CloudKit configuration for a person's own devices. Separate Apple IDs share a family through the explicit `FamilyCloudSharing` boundary instead of SwiftData automatic sync.

A family administrator creates a family-specific custom CloudKit zone and `CKShare`, then uses the system iCloud sharing controller to invite participants. The owner publishes a versioned, family-scoped snapshot containing rules, members, memberships, invitations, ledger/audit records, and confirmed settlement history. Participants accept the system invitation, synchronize the shared database into local SwiftData, sign in with Apple, and redeem the app role code. Change-tag conflicts require a fetch before retry rather than silently overwriting server data.

Production use still requires CloudKit schema deployment and signed physical-device verification with two different iCloud accounts. Automatic SwiftData private-database sync is not the cross-account sharing mechanism.

## Create the Xcode project on a Mac

1. In Xcode, create a new **Multiplatform App** named
   `JEMBTFamilyPointsTracker`.
2. Choose **SwiftUI**, **Swift**, and **SwiftData**.
3. Set the deployment targets to iOS/iPadOS 17 or later.
4. Delete the generated app, content-view, and item model files.
5. Add all `.swift` files under `JEMBTFamilyPointsTracker` to the app target.
6. Add `JEMBTFamilyPointsTrackerTests/PointsEngineTests.swift` to the unit-test
   target.
7. Under **Signing & Capabilities**, add iCloud, enable CloudKit, and select a
   development container.
8. Run first with CloudKit disabled or `.none` if the development container is
   not yet configured.

## CodeQL analysis

The CodeQL workflow uses `macos-15-intel`, pins Xcode 26.3, and manually builds
the shared `JEMBT Family Points Tracker` scheme for a generic iOS Simulator,
including its embedded watchOS app. This avoids the `preload_tracer` crash
observed on `macos-26-intel`; Xcode 27 / Swift 6.4 are not supported by CodeQL
traced extraction either.

The project uses the Xcode 16-compatible project format so the pinned toolchain
can open it. Analysis disables signing and overrides the iOS and watchOS
deployment targets to 26.2 to match the installed SDKs. These overrides apply
only to the CI build and do not change the app's shipping deployment settings.

## Rule catalog notes

The Word document contains rules whose final value depends on weekly counts,
duration, skipped rooms, meal quality, escalating offenses, or a parent's
judgment. The starter catalog preserves that guidance but deliberately allows
the recorder to override the calculated point value before submission.

Two prices were not available in the extracted document:

- Extra TV night
- Choice of the weekly movie-night selection

They are included as disabled placeholders and should be assigned prices in the
rules editor before use.

## Recommended next implementation sequence

1. Validate the CloudKit share lifecycle on two signed physical devices using separate Apple IDs.
2. Deploy the `SharedFamily` record schema to the production CloudKit environment.
3. Add remote-change notifications/background refresh if product policy should move beyond explicit Publish and Sync actions.
4. Add notifications for pending approvals and Sunday settlement review.
5. Add CSV import for historical weekly totals if that becomes useful.