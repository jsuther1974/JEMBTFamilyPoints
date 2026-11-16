# JEMBT Family Points Tracker instructions

## Sources of truth

- Treat code and tests as the executable specification.
- Read `docs/PRODUCT_RULES.md`, `docs/ARCHITECTURE.md`, `docs/decisions/`, and `docs/TESTING.md` before changing domain behavior, persistence, navigation, or test infrastructure.
- Read `WORK_STATUS.md` for temporary handoff state; verify it against the working tree before relying on it.
- Follow the applicable skill under `.github/skills/` for recurring workflows.
- Do not rely on chat history as the only source of a requirement.

## Core invariants

- Scope every family-owned read and mutation to the active family or to a verified set of that family's member IDs.
- Enforce authorization in mutation logic, not only by hiding controls.
- Caregivers do not participate in points and can only recommend activities for parent review.
- Child and caregiver submissions remain pending; parent-capable submissions may be directly approved.
- Saturday is the normalized reporting-period end date.
- Preserve ledger and settlement audit data; do not silently recalculate confirmed history from later rule changes.
- Preserve production persistence and CloudKit behavior when adding test isolation.
- Do not assume SwiftData automatic CloudKit storage shares records across different Apple IDs; see `README.md`.

## Change discipline

- Trace affected symbols, callers, tests, family scoping, and platform implications before editing.
- Prefer the smallest coherent change and avoid unrelated reformatting.
- Never place real family names, birthdates, contact identifiers, email addresses, invitation codes, or production records in source-controlled seed data, samples, tests, screenshots, logs, or documentation.
- Use clearly fictional fixture names, synthetic boundary-safe dates, `example.invalid` email addresses, and non-production identifiers. Do not copy data from Contacts, CloudKit, spreadsheets, or a production store into fixtures.
- Add stable accessibility identifiers to important interactive controls and stateful rows.
- Keep iPhone, iPad, and Watch behavior in mind; test an affected idiom rather than inferring it from another.
- Do not read or edit `project.pbxproj` directly. Use Xcode project operations for targets, build settings, Info.plist keys, entitlements, and file membership.
- Never add an entitlement for an API that does not require one.
- Do not commit or push unless the user explicitly asks.

## Verification

- Refresh diagnostics for every edited source file.
- Run the narrowest relevant tests first, then the affected target/suite.
- Stateful UI tests must launch through the isolated app factory and remain serialized.
- Do not fix UI-test failures by merely increasing timeouts; determine whether state, hierarchy, disclosure state, navigation, or persistence is wrong.
- For cross-platform changes, build and test each affected target/destination.
- Finish with `git diff --check`, working-tree review, and an explicit report of tests run, skips, warnings, and unresolved risks.

## Music and sound

For soundtrack selection, production, replacement, or auditing, follow
`.github/skills/public-domain-app-soundtracks/SKILL.md`.

- Treat composition, source edition/arrangement, sound recording, and production-asset rights as separate questions.
- Prefer verified public-domain compositions and cleared source editions, then create a new performance/recording with GarageBand, MainStage, or the repository's local renderer.
- Never assume an existing recording is reusable because its composition is public domain.
- Update `SOUNDTRACK_PROVENANCE.md` whenever a soundtrack source or recording changes.
- Retain reproducible source material and production notes when licensing permits.
- Preserve stable app resource names unless the corresponding source and tests are intentionally updated.
- Verify bundle lookup, audio format, clipping, playback lifecycle, mute behavior, and scene restoration before considering audio work complete.
