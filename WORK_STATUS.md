# Current work status

Last verified against the working tree: 2026-11-18.

This is a temporary handoff, not a product specification. Replace completed items rather than accumulating history.

## Objective

Complete explicit cross-Apple-ID CloudKit family sharing and authorization hardening without changing production persistence configuration or granting restricted roles broader mutation rights.

## Verified in the working tree

- Viewer invitation acceptance prepares a durable, invitation-specific publication authorization before save, then validates the consumed invitation plus exact family/Apple-ID/role/profile/membership/session graph before publishing. The accepted invitation and viewer membership are included in the exported snapshot; failure remains retryable after coordinator reconstruction. Reused codes and mismatched/foreign sessions fail, and ordinary viewer publication remains unauthorized.
- Durable publication intents now carry a monotonically increasing per-family generation. All asynchronous publication and conflict-resolution completions clear only their captured generation; an older transport operation that ignores cancellation cannot clear a newer mutation. Existing legacy boolean dirty markers migrate additively to general generated intents, with no SwiftData schema or production CloudKit configuration change.
- Share imports validate record/payload family identity, invitation eligibility, linked roles/profiles, settlements, identifier collisions, and reconciliation scope before mutation. Change tags advance only after successful import or an explicit validated conflict resolution.
- Concurrent local/remote edits expose explicit **Keep Local** and **Use Cloud Copy** recovery. Failed recovery remains retryable and cannot mutate another family.
- Linked memberships and unexpired invitations prevent incompatible profile changes. Expired invitations do not block deactivation, and authorized administrators can revoke active invitations. Viewer invitations require an active child profile.
- Family-scoped recording, review, settlement, Store, rule, member, invitation, and sharing mutations enforce authorization in mutation logic. Caregivers and viewers retain their restricted behavior.
- Deterministic transport coverage proves cancellation-ignoring publish A cannot clear newer mutation B. The full `FamilyCloudSharingTests` suite passed: 34/34.
- The complete 167-test iPhone plan produced one valid final run with 166 passed, 0 failed, and 1 expected iPad-only skip. Repeated additional requests intermittently produced empty zero-test Xcode result bundles and are not counted.
- The skipped regular-width member-editor regression passed separately on iPad Air 11-inch (M4) / iOS 27.0.
- Before the final six sharing tests were added, the complete iPhone plan passed twice at each preceding final checkpoint. All 18 stateful UI tests use `XCUIApplication.isolatedForTesting()`; only the intentional launch-performance test uses a normal launch.
- The app project builds successfully. Changed-file diagnostics are clean and `git diff HEAD --check` passes.
- `JEMBTFamilyPointsTrackerApp` uses in-memory SwiftData with CloudKit disabled only when `UITEST_ISOLATED_STORE=1`; normal launches remain persistent with CloudKit `.automatic`.
- The shared iOS scheme keeps the UI-test target serialized while unit tests remain parallelizable.
- Issue Navigator still reports simulator UI-test audio-session/main-thread responsiveness warnings; no stale assertion or build failure remains.
- The working tree intentionally remains uncommitted and contains mixed staged/unstaged changes; no commit or push was requested.

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