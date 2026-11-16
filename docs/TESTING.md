# Testing and verification

## Test targets

### iOS unit tests

`JEMBT Family Points TrackerTests` covers:

- `PointsEngine` date, accounting, settlement, debt, parent-pot, and ledger behavior.
- `RuleTemplate` calculation and eligibility.
- `StorefrontEngine` cart, inventory, eligibility, and affordability.
- `StatisticsEngine` trends and comparisons.
- `AppleIDManager` identity/member behavior using in-memory SwiftData.
- Soundtrack mapping and scene-stack behavior.

### iOS UI tests

`JEMBT Family Points TrackerUITests` covers sign-in/setup, family/member workflows, iPhone and iPad member controls, Family quick activity, Ledger, Store, Rules navigation, Stats, invitations, and role-specific presentation.

The UI-test target is intentionally serialized in the shared iOS scheme. Unit tests may remain parallelized.

### Watch tests

The Watch unit target verifies snapshot encoding and useful glance data. Watch UI tests exercise the companion presentation using deterministic sample data where configured.

## Isolation contract

Stateful UI tests must create the app with:

```swift
let app = XCUIApplication.isolatedForTesting()
```

That factory sets `UITEST_ISOLATED_STORE=1`. The application then creates an in-memory SwiftData configuration with `cloudKitDatabase: .none` while normal launches remain persistent with CloudKit `.automatic`.

Do not set the isolation variable in production schemes. Do not remove production CloudKit behavior to make tests deterministic.

### Current caveat

The helper exists in the UI-test source, but the current working tree still contains direct `XCUIApplication()` construction in the tests. Until those call sites use the factory, the intended isolation contract is not fully enforced. Track this in `WORK_STATUS.md` and do not claim the full suite is isolated until verified.

## Unit-test persistence

Any unit test that creates a `ModelContainer` should use:

```swift
ModelConfiguration(
    isStoredInMemoryOnly: true,
    cloudKitDatabase: .none
)
```

Include every model required by relationships or code paths under test. Avoid relying on the user's CloudKit account, simulator database, wall-clock locale, or prior test state.

## UI-test reliability rules

- Use stable accessibility identifiers for controls and dynamic rows.
- Prefer state predicates (`exists`, `isEnabled`, accessibility value) over fixed delays.
- A timeout is for asynchronous UI availability, not a substitute for diagnosing state.
- Do not assume content inside a collapsed `DisclosureGroup` exists in the accessibility hierarchy. Expand the correct group first.
- Do not tap every disclosure row blindly if a second pass could collapse an already expanded row. Track intended state or stop when the target becomes visible.
- Re-query dynamic collections after mutations when XCTest snapshots may be stale.
- Use unique simulator identities for tests that create families.
- Keep seeded-demo tests isolated from one another.
- Treat “passes individually, fails in the full suite” as evidence of shared state, ordering, simulator resources, or leaked presentation state.
- An iPad-only regression may skip on iPhone; report the skip as expected and run it on iPad before release.

## Focused verification matrix

| Change area | Required focused verification |
| --- | --- |
| `PointsEngine` or settlement | Relevant unit tests plus settlement/debt/minimum/fingerprint tests |
| Roles or authorization | Submission-policy tests, protected mutation tests, caregiver/child/parent UI checks |
| Family scoping | Two-family unit scenario proving no cross-family reads or writes |
| `RuleTemplate` | Rule calculation, age eligibility, minimum/maximum, and migration/default tests |
| Store | `StorefrontTests` plus cart checkout UI flow for affected role |
| Family quick activity | Quick award/penalty UI flow through resulting Ledger row |
| Ledger | Aggregation/sort/review unit tests and collapsed-day/edit UI flow |
| SwiftData schema/config | In-memory unit construction, production build, and existing-data/default reasoning |
| Cross-Apple-ID sharing | Snapshot round trip with full ledger/settlement audit, malformed two-family rejection before mutation, administrator and unauthorized roles, participant import, conflict propagation, app build, then two physical iCloud accounts |
| iPhone member editor | Keyboard focus/tab/date confirmation regressions |
| iPad member editor | Regular-width native role/date interaction regression on iPad |
| Watch snapshot | Watch unit tests, iPhone publish path, Watch build, cached/offline behavior |
| Soundtrack | Resource mapping/scene-stack tests, build, runtime logs, mute/restoration, `afclip` |
| Top-level navigation | Tab count/labels and single-back-button UI regression |

## Recommended test order

1. Refresh diagnostics for edited files.
2. Run the smallest directly affected test or test class.
3. Run the affected unit-test target.
4. Build the affected app/Watch target.
5. Run focused UI tests on the required device idiom.
6. Run the complete active test plan.
7. For reliability work, run the complete plan twice from clean isolated launches.
8. Review Issue Navigator/build logs for warnings and stale failures.
9. Run `git diff --check` and inspect repository status.

## Result reporting

Always state:

- Destination and OS/device class.
- Tests run and counts passed/failed/skipped.
- Whether the run was focused or complete.
- Expected versus unexpected skips.
- Build warnings relevant to the change.
- Any platform or scenario not run.

Never summarize a partially run matrix as “all tests pass.”

## Release gate

Before user testing or release:

- iPhone complete plan passes with only documented destination-specific skips.
- iPad-specific UI regressions pass on an iPad destination.
- Watch unit tests pass on a Watch destination and the companion builds/runs.
- Production configuration is not using the isolated in-memory test store.
- Family isolation and role authorization tests pass.
- No unresolved audio-resource, SwiftData, CloudKit, or navigation warnings remain.

## CloudKit sharing tests

`FamilyCloudSharingTests` use an injected `FamilyShareTransport` and in-memory SwiftData with CloudKit disabled. They do not contact iCloud. They verify deterministic payload mapping, exact family scoping, recorder/reviewer and settlement fingerprint preservation, unauthorized-role rejection, participant import, and conflict reporting.

Simulator/unit success is not end-to-end CloudKit proof. Before release, use two physical devices with different Apple IDs to verify share presentation and delivery, `userDidAcceptCloudKitShareWith`, shared-database visibility, explicit fetch/publish, offline edits, server-change conflicts, participant removal, and production CloudKit schema deployment.