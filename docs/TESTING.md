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

## Shared iOS test plans

The shared `JEMBT Family Points Tracker` scheme uses these Xcode-managed plans:

| Plan | Enabled tests | Parallelization | Coverage | Use |
| --- | ---: | --- | --- | --- |
| `iOS Unit Fast` | 158 unit tests | Unit target parallelizable | Off | Fast local/CI logic validation |
| `iOS UI Functional` | 19 UI tests; `testLaunchPerformance` excluded | UI target serialized | Off | Stateful functional UI validation |
| `iOS Launch Performance` | `testLaunchPerformance` only | Serialized | Off | Normal persistent/CloudKit launch metric |
| `iOS Complete Release` | 178 tests: 158 unit + 20 UI | Unit target parallelizable; UI target serialized | On | Default complete iOS release gate |

Select the narrowest applicable plan in Xcode's test-plan picker. Keep `iOS Complete Release` as the shared scheme default and do not replace its release-gate role with a narrow plan.

### Watch tests

The Watch unit target verifies snapshot encoding and useful glance data. Watch UI tests exercise the companion presentation using deterministic sample data where configured.

## Isolation contract

Stateful UI tests must create the app with:

```swift
let app = XCUIApplication.isolatedForTesting()
```

That factory sets `UITEST_ISOLATED_STORE=1` and `UITEST_DISABLE_AUDIO=1`. The application then creates an in-memory SwiftData configuration with `cloudKitDatabase: .none` while normal launches remain persistent with CloudKit `.automatic`. The audio override suppresses simulator playback only for explicitly isolated launches; production audio preferences and audio unit coverage remain unchanged.

Post-onboarding tests may request `UITEST_SCENARIO=signed-in-demo-parent` or `UITEST_SCENARIO=signed-in-empty-administrator` through `isolatedForTesting(scenario:)`. Both use clearly synthetic `example.invalid` identities and establish a fully linked family, membership, profile, and session in the fresh in-memory store. Scenario and audio values are ignored unless `UITEST_ISOLATED_STORE=1` is also present.

Keep dedicated UI coverage for the real create-family, join-family, invitation, and Return-key flows; fixtures optimize only tests whose setup flow is not the assertion under test.

Do not set the isolation variable in production schemes. Do not remove production CloudKit behavior to make tests deterministic.

### Direct-construction exceptions

All stateful UI scenarios use `XCUIApplication.isolatedForTesting()`. The only direct `XCUIApplication()` construction is inside that factory and in `testLaunchPerformance()`, which intentionally measures the normal persistent/CloudKit-configured launch path rather than the test-only store.

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

## Household device matrix runner

Use `Tools/run_household_device_matrix.sh` when you need a repeatable cross-device pass that approximates a real family setup across iPhone, iPad, Watch, and local Mac Catalyst build coverage.

- Dry-run (print mapped destinations and commands): `Tools/run_household_device_matrix.sh --dry-run`
- Execute matrix commands: `Tools/run_household_device_matrix.sh --run`

The script chooses the nearest available simulator when an exact model string is unavailable:

- Parent 1: iPhone 18 Pro Max → `iPhone 18 Pro Max` (fallback `iPhone 17 Pro Max`), iPad Pro M5 → `iPad Pro 13-inch (M5)` (fallback `iPad Pro 11-inch (M5)`), Watch 12 46mm → `Apple Watch Series 12 (46mm)` (fallback `Apple Watch Series 11 (46mm)`).
- Parent 2: iPhone 16 Pro → `iPhone 16 Pro` (fallback `iPhone 15 Pro`), iPad Pro M4 → `iPad Pro 13-inch (M4)` (fallback `iPad Pro 11-inch (M4)`), no Watch destination by design.
- Child: iPad Pro 11-inch M1 → `iPad Pro (11-inch) (3rd generation)` (fallback `iPad Pro (11-inch) (4th generation)`), Watch SE 2 40mm → `Apple Watch SE (40mm) (2nd generation)` (fallback `Apple Watch SE 3 (40mm)`).

Runtime lanes remain explicit in reporting: one iOS lane (phone/tablet matrix by resolved simulator runtime) and one watchOS lane (Watch scheme on direct Watch destinations).

The script also includes one local build-only Catalyst lane on the current machine:

- `xcodebuild build -scheme "JEMBT Family Points Tracker" -destination "platform=macOS,variant=Mac Catalyst"`

Physical-Mac household coverage remains manual and should be reported separately:

- Parent 1 manual Macs: Mac Studio M4 Max and MacBook Pro M4.
- Parent 2 manual Mac: MacBook Air M1 (2020).

Keep Catalyst verification as:

- PR smoke: build-only Catalyst validation when desktop-affecting code changes.
- Pre-release manual sanity: launch/navigation pass on each household Mac before release candidates.

This runner keeps destination control in a script instead of an `.xctestplan` because Xcode test plans configure test selection/options, while destination matrices span two schemes (`JEMBT Family Points Tracker` and `Family Points Watch App Watch App`) and idiom-specific simulator choices.

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