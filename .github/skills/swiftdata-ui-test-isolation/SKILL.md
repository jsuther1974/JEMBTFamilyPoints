---
name: swiftdata-ui-test-isolation
description: Create deterministic SwiftData unit and UI tests without changing production persistence or CloudKit behavior.
---

# SwiftData and UI-test isolation

Use this skill when adding tests, diagnosing full-suite-only failures, changing app container setup, or introducing test launch configuration.

## Production/test boundary

Normal launches must keep:

- Persistent SwiftData storage.
- `cloudKitDatabase: .automatic`.
- Normal seed/session behavior.

UI-test launches set `UITEST_ISOLATED_STORE=1`, which selects:

- `isStoredInMemoryOnly: true`.
- `cloudKitDatabase: .none`.
- Fresh seeded data for that application process.

Unit tests construct their own in-memory, non-CloudKit container.

## UI-test procedure

1. Create the application with `XCUIApplication.isolatedForTesting()`.
2. Add scenario-specific launch environment values to that returned app.
3. Launch only after all environment values are configured.
4. Use unique Apple ID values when a test creates its own family.
5. Keep stateful UI tests serialized.
6. Do not reuse a launched app between tests.

Audit direct construction with:

```bash
rg 'XCUIApplication\(\)' 'JEMBT Family Points TrackerUITests'
```

The centralized factory itself and deliberate non-stateful tooling are the only acceptable exceptions. Document exceptions.

## Diagnosing failures

When tests pass individually but fail together, investigate in this order:

1. Direct `XCUIApplication()` calls bypassing isolation.
2. UI-test target parallelization.
3. Reused simulator Apple IDs or persisted seeded data.
4. CloudKit/account side effects.
5. Leaked sheets, alerts, keyboard, or navigation state.
6. Collapsed disclosure groups and stale accessibility queries.
7. Destination-specific UI differences.

Do not first increase timeouts or weaken assertions.

## Unit-test containers

Use an in-memory configuration with CloudKit disabled. Include all models required by relationships and code paths. Construct fresh test data per test and inject deterministic dates/calendars when date behavior matters.

## Verification

1. Run the formerly failing test repeatedly.
2. Run a neighboring stateful UI test.
3. Run the complete plan twice.
4. Confirm the production scheme still creates a persistent automatic-CloudKit configuration when the environment variable is absent.
5. Report expected destination-specific skips separately.
