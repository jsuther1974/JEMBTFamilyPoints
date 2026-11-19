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

Profile restoration uses a validation-first domain policy. It creates a profile only for a membership with no linked profile ID; linked profiles must exist, remain active, belong to the membership's family, and have a compatible role before migration cleanup or session establishment.

These are related but not interchangeable. Authorization should use membership capabilities, while points participation and display behavior use the member profile role.

Profile edits and deactivation validate same-family links before mutation. Role changes are prohibited when they would make a membership or active, unexpired pending invitation incompatible; deactivation is prohibited while any membership or active, unexpired pending invitation remains linked, with administrator/owner links explicitly protected against lockout. Expired invitations are ignored deterministically, while same-family pending invitations have an administrator/owner-only revoke mutation. Viewer and child memberships/invitations both require active child profiles. These checks live in mutation logic rather than presentation controls.

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

Normal launches keep the existing persistent SwiftData configuration with `cloudKitDatabase: .automatic`. UI-test launches may select an in-memory store with CloudKit disabled through `UITEST_ISOLATED_STORE=1`.

Cross-Apple-ID sharing is a separate, explicit boundary in `FamilyCloudSharing.swift`:

- An administrator publishes one family into its own custom private CloudKit zone and root `SharedFamily` record.
- A `CKShare` and `UICloudSharingController` invite specific iCloud participants; `CKSharingSupported` routes accepted invitations to `FamilySharingAppDelegate`.
- The shared record stores a versioned, family-scoped JSON snapshot as a `CKAsset`. The snapshot includes members, invitations, memberships, rules/riders, ledger entries, and confirmed settlements, including recorder/reviewer and fingerprint audit fields.
- Accepted shared-zone records are fetched from the participant's shared database and reconciled into the existing offline SwiftData store. The owner's private shared zones use the same fetch path.
- Every snapshot is validated as a single-family graph before any local mutation. Memberships must link to active compatible profiles, child/viewer invitations must link to active compatible profiles, and settlements must target child profiles. Import is all-or-nothing at the validation boundary and reconciles only that family.
- Publishing requires a complete authorized session. Creating/managing a share requires family-administrator capability; non-viewer members may publish only their active family after app-level mutation authorization has already succeeded. A viewer has no general publish path. Invitation acceptance creates a narrow durable authorization bound to the pending invitation ID, family, Apple ID, role, and linked profile; only the resulting exact accepted invitation/membership/session graph may use it to publish redemption state or retry that publication.
- The last fetched CloudKit change tag is retained per family. Publishing without that baseline, or after a server-side change, fails as a conflict. A validated eligible conflict is retained in-memory per family for an explicit choice: **Keep Local** conditionally writes the local snapshot against the fetched server change tag, while **Use Cloud Copy** reconciles only that family's local graph from the validated remote snapshot. The pending conflict and dirty marker are cleared only after the chosen resolution completes; malformed, ineligible, mismatched, and foreign-family payloads never become resolution candidates.
- Local SwiftData remains available offline. Successful protected family mutations schedule a per-family coalesced, serialized, best-effort publish of the latest family snapshot; publication failure never rolls back the local save. Multiple families cannot cancel each other's queued publication. Manual Publish and Sync controls remain available. Automatic SwiftData CloudKit remains private-device synchronization and is not treated as family sharing.
- Protected family saves use a prepare/commit/rollback publication intent. Prepare authorizes and durably stores a per-family `UserDefaults` intent with a monotonically increasing generation before `ModelContext.save`; commit schedules the family-scoped coalesced publication; rollback restores only the prior intent replaced by that failed save. Every asynchronous completion conditionally clears the exact generation it captured, so stale or non-cooperative cancelled transport work cannot erase a newer dirty intent. Local-only families retain the intent without surfacing a failure; cancellation and publication errors keep it retryable. Legacy boolean dirty markers migrate additively to general generation intents, and a reconstructed coordinator retries durable general or invitation-redemption intents after a matching session is established and on scene activation. Isolated UI-test stores continue to bypass publication state and transport.

This additive boundary does not move or recreate the production SwiftData store.

## iPhone and iPad

The app shares SwiftUI screens across idioms. Compact iPhone member editing uses keyboard-oriented custom controls. iPad member editing explicitly uses native SwiftUI role and date controls based on `UIDevice.current.userInterfaceIdiom`, because compact sheet size classes alone did not prevent UIKit input-view interaction failures.

Do not replace idiom checks with size-class assumptions without rerunning both iPhone and iPad regressions.

## Family Clubhouse visual system

`ClubhouseArtwork.swift` owns a reusable, adaptive backdrop for the five top-level iOS rooms: Family living room/gallery, Store shop, Rules bulletin board, Ledger desk, and Stats trophy nook. Scenes use scalable SwiftUI shapes, symbols, gradients, and semantic colors. Top-level views keep data-dense lists, balances, controls, and charts on system or material surfaces; artwork is confined to the background and wider iPad gutters.

The existing bundled family artwork is reused only as a cropped, deliberately framed portrait. It is never stretched into wallpaper, and the app icon asset is not modified. The baseball-player portrait and recurring pet, token jar, paper airplane, books, game pieces, glove/duffel motifs are fictional decorative artwork with no person, school, team, league, number, or logo identity.

All decorative artwork is accessibility-hidden and ignores hit testing. The backdrop reduces detail for Increase Contrast, substitutes a nearly opaque semantic system surface for Reduce Transparency, adapts to light/dark appearance, and contains no motion. Layout uses compact edge cameos on iPhone and wider outer-gutter compositions on iPad. Runtime avatars, Contacts photos, names, balances, and other family data must remain in content views and must never be incorporated into the backdrop or decorative portraits.

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

CloudKit share creation, acceptance, payload mapping, family validation, authorization, and conflict behavior are testable through `FamilyShareTransport`. End-to-end invitation delivery, iCloud-account state, push propagation, CloudKit production schema deployment, and multi-device conflict recovery still require signed physical-device verification with separate Apple IDs.