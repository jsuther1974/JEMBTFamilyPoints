# Current work status

Last verified against the working tree: 2026-11-15.

This is a temporary handoff, not a product specification. Replace completed items rather than accumulating history.

## Objective

Maintain deterministic UI-test isolation without changing production persistence, CloudKit sharing, or authorization behavior.

## Verified in the working tree

- `JEMBTFamilyPointsTrackerApp` uses in-memory SwiftData with CloudKit disabled only when `UITEST_ISOLATED_STORE=1`; normal launches remain persistent with CloudKit `.automatic`.
- The shared iOS scheme keeps the UI-test target serialized while unit tests remain parallelizable.
- `testFamilyQuickAwardSavesAndAppearsInWeeklyLedger()` launches through `XCUIApplication.isolatedForTesting()`.
- The quick-award line-420 failure was not a reward selector or Family-page rendering defect. The captured hierarchy remained on `Join a Family` and showed `This request requires an authenticated account`: the new join flow attempted an explicit CloudKit fetch before accepting the seeded local `DEMO-FAMILY` invitation.
- `AppleIDAuthenticationViews.joinFamily()` now skips remote fetch and publish only for the explicit isolated-store launch environment, then accepts the seeded invitation locally. Production sharing behavior is unchanged.
- On iPhone 17 / iOS 27.2, the formerly failing quick-award test passed 3 consecutive focused repetitions (3 passed, 0 failed, 0 skipped).
- On the same destination, the complete 122-test plan passed twice. Each run reported 121 passed, 0 failed, and 1 expected iPhone skip (`testRegularWidthAddMemberControlsRemainInteractiveAfterTextEntry()`, iPad-only).
- File diagnostics are clean for `AppleIDAuthenticationViews.swift` and the UI-test source. The latest build log contains no warnings.
- The stale line-420 assertion failure is gone from Issue Navigator. Current entries are UI-test main-thread responsiveness/audio-session warnings, including one for the quick-award test; no stale test failure remains.
- `git diff --check` passes. The working tree still contains unrelated pre-existing product, sharing, authorization, documentation, and soundtrack changes.

## Still required outside this task

1. Replace remaining direct stateful UI-test `XCUIApplication()` construction with `XCUIApplication.isolatedForTesting()` where isolation is intended; measured launches require an explicit decision.
2. Run the regular-width member-editor regression on an iPad destination.
3. Run Watch unit tests on a Watch destination and confirm the companion build.

## Guardrails

- Do not change production CloudKit configuration to fix UI tests.
- Do not re-enable parallel UI tests while they depend on shared simulator resources or seeded role flows.
- Do not weaken the Ledger content assertion; keep disclosure expansion and dynamic re-query behavior deterministic.
- Do not commit or push unless explicitly requested.