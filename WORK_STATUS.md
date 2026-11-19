# Work Status

## Current objective

Implement and verify the first Family Clubhouse visual-art pass while preserving existing Store, Rules, Ledger, Stats, Family, audio, Watch, test-plan, authorization, and family-isolation behavior.

## Implementation state

- Added `ClubhouseArtwork.swift`, a reusable semantic light/dark SwiftUI backdrop system for Family, Store, Rules, Ledger, and Stats with quiet/standard readability intensity.
- Added original scalable decorative art: a fictional unbranded teenage baseball player with a slightly dirty uniform, shoulder duffel and visible bat; plus recurring pet, star-token jar, paper airplane, books/game pieces, and trophy motifs.
- Replaced the stretched Family wallpaper with the bundled family artwork in a deliberate portrait frame; the app icon and runtime member photos remain unchanged and separate.
- Integrated non-interactive, accessibility-hidden scenes behind the five top-level pages. Store and Stats data surfaces remain readable, list content retains system row surfaces, and Store/Stats content widths expose wider iPad gutters.
- Backdrops reduce artwork for Increase Contrast, use a near-opaque semantic surface for Reduce Transparency, contain no motion, and adapt composition for compact versus regular horizontal size classes.
- Documented the visual-system privacy and accessibility boundaries in `docs/ARCHITECTURE.md`.
- Existing CloudKit sharing, role, accounting, persistence, Watch snapshot, and audio logic was not redefined by this pass.

### Pre-existing worktree state preserved

- Cross-Apple-ID CloudKit sharing remains implemented through validated family-scoped snapshots, explicit invitation redemption authorization, strict family isolation, change-tag conflicts, explicit Keep Local/Use Cloud Copy resolution, protected mutation publication intents, per-family coalescing, durable retry, and stale-generation protection.
- Role/profile compatibility, invitation revocation, protected mutation boundaries, Store checkout, Ledger review/editing, settlement, family administration, and rule management remain enforced in domain policy rather than only in UI visibility.
- UI-test scenarios remain gated behind the isolated in-memory store; production CloudKit behavior is unchanged.
- Existing iPhone/iPad member-editor idiom handling, top-level navigation tests, public-domain room soundscapes, soundtrack provenance, Watch sample isolation, shared test-plan files, and the pre-existing Watch/audio/test-plan modifications remain in the worktree.
- Previously documented physical-device CloudKit, production schema, legacy dirty-marker migration, Watch simulator, and simulator audio-session verification gaps remain open below.

## Verified

- iPhone 18 Pro simulator (iOS 27.0): iOS target build passed.
- iPad Pro 11-inch (M5) simulator (iOS 27.2): iOS target build passed.
- `iOS Unit Fast`: 152 passed, 0 failed, 0 skipped.
- The compact Family geometry failure was an obsolete absolute-coordinate assertion, not an artwork layout regression. The artwork is a non-layout-affecting background and the overview banner remains fixed at 52 points; iOS 27 reports the visible Children heading at 326.33 on the 874-point-tall iPhone 18 Pro screen, still within the upper half.
- `testFamilyPageShowsPointsInMemberCardsWithoutStandaloneWeekSection` passed 3 consecutive focused runs on iPhone 18 Pro (iOS 27.0).
- `iOS UI Functional` completed twice on iPhone 18 Pro (iOS 27.0); each Xcode run reported 19 passed, 0 failed, and 1 expected iPhone-only skip (`testRegularWidthAddMemberControlsRemainInteractiveAfterTextEntry`).
- Focused iPad UI on iPad Pro 11-inch (M5) (iOS 27.2): compact/regular Family content regression and regular-width Add Member interaction both passed (2 passed, 0 failed, 0 skipped).
- Current build log has no warnings and Issue Navigator has no current or stale entries.
- SwiftUI artwork preview rendered on iPhone 18 Pro iOS 27.2 and iPad Pro 11-inch iOS 27.2 (dark appearance, increased contrast).

## Still required outside this task

1. On two signed physical devices with different Apple IDs, verify share creation/delivery, `userDidAcceptCloudKitShareWith`, every invitation role (especially Viewer), shared-database visibility, offline edits, foreground retry, both conflict choices, participant removal, re-invitation, and strict family isolation.
2. Verify production CloudKit `SharedFamily` schema/index deployment, permissions, push propagation, and realistic snapshot asset sizes.
3. Exercise an existing installation to verify migration from the legacy boolean dirty marker to generated publication intents.
4. Run Watch unit/UI tests on a Watch simulator destination and confirm the companion build and cached offline snapshot. No Watch schema changed in this work.
5. Triage the remaining simulator audio-session/main-thread responsiveness warnings before declaring the overall app release-ready.

## Guardrails

- Do not change production CloudKit configuration to fix UI tests.
- Do not re-enable parallel UI tests while they depend on shared simulator resources or seeded role flows.
- Do not weaken the Ledger content assertion; keep disclosure expansion and dynamic re-query behavior deterministic.
- Do not commit or push unless explicitly requested.