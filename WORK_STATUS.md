# Current work status

Last verified against the working tree: 2026-11-14.

This is a temporary handoff, not a product specification. Replace completed items rather than accumulating history.

## Objective

Finish and verify deterministic UI-test isolation while preserving the recent soundtrack work and all production persistence behavior.

## Verified in the working tree

- `JEMBTFamilyPointsTrackerApp` recognizes `UITEST_ISOLATED_STORE=1` and then uses in-memory SwiftData with CloudKit disabled.
- Normal launches remain persistent with CloudKit `.automatic`.
- The shared iOS scheme serializes the UI-test target while unit tests remain parallelizable.
- `XCUIApplication.isolatedForTesting()` exists in the iOS UI-test source.
- The quick-award Ledger test now expands the captured day rows before asserting the laundry summary.
- Public-domain soundtrack resources, local rendering tools, provenance, and the soundtrack skill exist as uncommitted work.

## Still required

1. Replace direct UI-test `XCUIApplication()` construction with `XCUIApplication.isolatedForTesting()` where persistent state could affect behavior, including measured launches if isolation is intended there.
2. Run the focused `testFamilyQuickAwardSavesAndAppearsInWeeklyLedger()` regression.
3. Run the complete iPhone test plan twice.
4. Run the regular-width member-editor regression on an iPad destination.
5. Run Watch unit tests on a Watch destination and confirm the companion build.
6. Refresh Issue Navigator and distinguish stale issues from current failures.
7. Run `git diff --check` and review all uncommitted files.

## Last reported run from prior session context

A prior complete run was reported as 102 passed, 1 failed, and 1 expected iPad-only skip. That result predates the current ledger-test source adjustment and has not been reconfirmed in this handoff. Do not present it as the current result.

## Guardrails

- Do not change production CloudKit configuration to fix UI tests.
- Do not re-enable parallel UI tests while they depend on shared simulator resources or seeded role flows.
- Do not weaken the Ledger content assertion; make disclosure state deterministic.
- Do not commit or push unless explicitly requested.
