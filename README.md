# JEMBT Family Points Tracker

Native SwiftUI starter for the Suguiluz family point system. The design replaces
the spreadsheet's expanding weekly columns with an auditable ledger: every
award, penalty, reward purchase, approval, parent-pot allocation, and weekly
settlement is a dated record.

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

The source uses SwiftData for the local ledger and enables its CloudKit-backed
configuration. That is sufficient for a person's devices signed into the same
iCloud account. A family using separate Apple IDs needs a shared CloudKit zone
and `CKShare` invitation flow before production use. Keep the model and
`PointsEngine` unchanged; replace the persistence boundary with shared
CloudKit records or a Core Data `NSPersistentCloudKitContainer` sharing layer.

Do not ship the app assuming SwiftData's automatic private-database sync shares
records across separate family Apple IDs.

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

1. Open and run the local app in Xcode.
2. Add editing screens for family members and rule templates.
3. Add authentication/role selection for parent versus child mode.
4. Implement shared CloudKit-zone creation, `CKShare` invitations, and conflict
   handling for separate Apple IDs.
5. Add notifications for pending approvals and Sunday settlement review.
6. Add CSV import for historical weekly totals if that becomes useful.

