# 003: Isolated and serialized stateful UI tests

- Status: Accepted; adoption incomplete in the current working tree
- Date: 2026-11-14

## Context

Stateful UI tests shared a persistent SwiftData/CloudKit-backed simulator store and seeded identities. Tests that passed independently failed in the full suite because launches mutated shared data in parallel.

## Decision

- UI-test launches set `UITEST_ISOLATED_STORE=1` through a centralized `XCUIApplication.isolatedForTesting()` factory.
- The app responds only to that explicit variable by using in-memory SwiftData with CloudKit disabled.
- Normal launches remain persistent with CloudKit `.automatic`.
- The stateful iOS UI-test target is serialized.
- Unit tests remain parallelizable and use independent in-memory containers.

## Consequences

Direct UI-test `XCUIApplication()` calls are defects unless deliberately documented. Reliability fixes must address state/hierarchy causes before timeouts. The complete suite should be run twice after isolation changes.

## Current adoption note

The factory and app switch exist, and the scheme serializes UI tests, but direct constructors remain in the UI-test source. See `WORK_STATUS.md`.

## Enforced by

`JEMBTFamilyPointsTrackerApp.swift`, the iOS shared scheme, `JEMBT_Family_Points_TrackerUITests.swift`, and `.github/skills/swiftdata-ui-test-isolation/SKILL.md`.
