# Architecture

## Overview

JEMBT Family Points Tracker is a SwiftUI application for iPhone and iPad with a watchOS companion. SwiftData stores family, identity, rule, ledger, and settlement records. `PointsEngine` contains deterministic accounting calculations. `AppleIDManager` owns the active identity and family session. `WatchConnectivity` publishes a read-only family snapshot to the Watch app.

The primary iOS tabs are Store, Rules, Ledger, Stats, and Family. Settlement is a parent workflow reached from contextual navigation rather than a top-level tab.

## Application composition

`JEMBTFamilyPointsTrackerApp` creates and injects:

- A `ModelContainer` containing `AllowanceFamily`, `FamilyInvitation`, `FamilyMembership`, `FamilyMember`, `RuleTemplate`, `RuleRider`, `LedgerEntry`, `WeeklySettlement`, and `AppleIDMapping`.
- One observable `AppleIDManager` session.
- One observable `SoundscapeDirector`.

`ContentView` owns the shared `ReportingPeriod`, top-level tabs, point-change notices, soundtrack selection, and the hidden Watch snapshot publisher.

## Domain boundaries

### Identity and family membership

`AppleIDManager` establishes the active Apple ID, `AllowanceFamily`, `FamilyMembership`, and linked `FamilyMember`. `FamilyMembershipRole` controls administrative capabilities. `MemberRole` describes the family profile's participation in family workflows.

These are related but not interchangeable. Authorization should use membership capabilities, while points participation and display behavior use the member profile role.

### Rules and entries

`RuleTemplate` defines rewards, penalties, and store items. It includes quantity calculation, minimums and maximums, age eligibility, growth/acceleration, inventory, and optional missed-minimum deduction behavior.

`LedgerEntry` is the auditable transaction record. It records recipient, rule, occurrence date, reporting week, title, notes, points, kind, approval status, recorder/reviewer attribution, quantity, unit, and rider.

### Accounting

`PointsEngine` is the accounting boundary. Keep point math, date normalization, aggregation, pending totals, copying, parent-pot distribution, debt carryover, minimum-miss detection, transaction fingerprints, and settlement drafts deterministic and UI-independent.

Views may present and collect decisions, but they should not duplicate accounting formulas.

### Settlement history

`WeeklySettlement` snapshots confirmed results and audit details. A transaction fingerprint binds settlements to the relevant non-rejected entries. Persisted settlement values protect history from later rule edits.

Never silently rewrite confirmed history. If correction support is introduced, model it as an explicit audited operation.

## Family isolation

Many SwiftData queries intentionally fetch broad model sets because dynamic environment family IDs are awkward in property-wrapper predicates. Every derived collection and mutation must then scope records by:

- `currentFamily.id`, or
- a set of member IDs proven to belong to the current family.

Review family scoping before correctness or UI polish. Cross-family reads and writes are critical defects.

## Reporting period

`PointsEngine.weekEnding(containing:)` normalizes every reporting week to Saturday at start of day. `ReportingPeriod` shares the selected week across Family, Ledger, and related flows. Occurrence dates belong to a day within that seven-day period; invalid legacy occurrence dates fall back to the week-ending date.

## Storefront

Parents and other rule managers maintain store inventory. A user can purchase only when both their membership and profile roles are child. Checkout revalidates family ownership, enabled state, age eligibility, inventory, and affordability before recording approved negative purchase entries.

## Persistence and CloudKit

Normal launches use persistent SwiftData with `cloudKitDatabase: .automatic`. UI-test launches may select an in-memory store with CloudKit disabled through `UITEST_ISOLATED_STORE=1`.

This test switch must never alter production behavior.

Automatic SwiftData CloudKit storage does not by itself provide cross-Apple-ID family sharing. The production limitation and future shared-zone requirement are documented in `README.md`.

For persisted-model changes:

- Prefer additive optional fields or fields with safe defaults.
- Preserve raw-value fallbacks for existing records.
- Consider CloudKit schema constraints and existing settlement history.
- Test opening or constructing data that omits new values.

## iPhone and iPad

The app shares SwiftUI screens across idioms. Compact iPhone member editing uses keyboard-oriented custom controls. iPad member editing explicitly uses native SwiftUI role and date controls based on `UIDevice.current.userInterfaceIdiom`, because compact sheet size classes alone did not prevent UIKit input-view interaction failures.

Do not replace idiom checks with size-class assumptions without rerunning both iPhone and iPad regressions.

## Watch architecture

The iPhone app's `WatchSnapshotSyncView` observes the active family's members and entries and asks `WatchSyncBridge` to publish a property-list-compatible application context.

The snapshot contains:

- Family/viewer identity and role.
- Pending count.
- Active child balances from approved entries.
- Five recent approved entries.

The Watch app decodes the snapshot into Codable value types, caches it in `UserDefaults`, and displays the last snapshot offline. Reachable refresh uses a message/reply request; failed refreshes retain cached data. Treat the snapshot schema as a versioned API when evolving it.

## Sound architecture

`SoundscapeDirector` owns bundled room music, synthesized effects, haptics, mute persistence, and a scene-owner stack. Overlay scenes temporarily take ownership and restore the most recent visible room when dismissed. Follow `.github/skills/public-domain-app-soundtracks/SKILL.md` and `SOUNDTRACK_PROVENANCE.md` for audio changes.

## Known architectural limitation

Before production use across separate family Apple IDs, implement and validate a shared CloudKit zone/`CKShare` or another explicit shared persistence boundary. Do not describe automatic private-database sync as family sharing.
