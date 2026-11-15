---
applyTo: "**/*Tests/**/*.swift"
---

# Test instructions

- Follow `docs/TESTING.md` and `.github/skills/swiftdata-ui-test-isolation/SKILL.md`.
- Unit-test model containers must be in memory with CloudKit disabled.
- Stateful iOS UI tests must launch through `XCUIApplication.isolatedForTesting()`.
- Keep the iOS UI-test target serialized unless the tests are redesigned to eliminate shared simulator and seeded-state dependencies.
- Use unique test identities for family-creation scenarios.
- Prefer stable accessibility identifiers and observable state over coordinate taps and arbitrary sleeps.
- Expand disclosure rows before asserting on hidden descendants; do not assume collapsed content exists.
- Preserve meaningful assertions. Diagnose state contamination or hierarchy changes instead of increasing timeouts indiscriminately.
- Report destination-specific skips explicitly and run iPad-only regressions on iPad before release.
- When fixing a flaky test, run it repeatedly and then run the complete relevant suite at least twice.
