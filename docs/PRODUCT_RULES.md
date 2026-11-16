# Product rules

This document records behavior verified in the current code and tests. Change it alongside intentional product-policy changes.

## Roles and authorization

There are two role concepts:

- `MemberRole`: child, parent, caregiver.
- `FamilyMembershipRole`: family admin, owner, parent, caregiver, child, viewer.

Membership capabilities are authoritative for protected actions:

- Family admin and owner can administer the family.
- Family admin, owner, and parent can manage rules.
- Family admin, owner, and parent can review the ledger.

Profile roles control participation:

- Children participate in points and may receive rewards and penalties.
- Parents participate in points for penalties; their approved negative entries fund the parent penalty pot.
- Caregivers do not participate in points, do not display point totals, and are not valid point recipients.
- Caregivers recommend activities; they do not directly approve them.

Authorization must be enforced before mutation. Hidden buttons are not sufficient authorization.

Every protected mutation requires a complete, internally consistent active session: the Apple ID must match the membership, the membership and linked active profile must belong to the active family, and the membership must link to that profile. Viewer, missing, stale, mismatched, and foreign-family sessions are rejected.

For activity recording, family admin, owner, and parent memberships receive immediate approval only when linked to a parent profile. Child and caregiver memberships may submit, but their entries remain pending. Recipients and rules are revalidated as active-family records at save time, and caregivers are never valid point recipients.

## Submission and review

`ActivitySubmissionPolicy` determines the submission kind:

- Caregiver membership/profile → caregiver recommendation.
- A child account holder → child submission.
- Otherwise → parent submission.

Child submissions and caregiver recommendations require parent approval. Parent submissions may be recorded as approved. Pending entries may be approved or rejected only by a membership with ledger-review capability. Review records `reviewedBy` and `reviewedAt`.

## Family isolation

Every family-owned rule, member, invitation, entry, settlement, statistic, and store operation must be scoped to the active family. When entries do not directly store `familyID`, scope them through the active family's member IDs.

Cross-Apple-ID family sharing uses an explicit iCloud invitation in addition to the app's role invitation:

- Only a family administrator/owner may create or manage the family's `CKShare`.
- A participant first accepts the iCloud share, synchronizes the shared family locally, signs in with Apple, and redeems the family's one-time role code.
- Child and viewer invitations must be linked to an existing active compatible profile; both roles require a child profile. Adult invitations may create a new compatible profile when redeemed.
- Redeeming an invitation never replaces or relinks a different existing membership for the same Apple ID and family.
- Accepting an iCloud share alone grants transport access but never creates an app membership or bypasses membership/profile authorization.
- A shared payload that contains any foreign-family member, rule, rider, invitation, membership, entry, or settlement is rejected before local mutation.
- Cloud conflicts never silently overwrite another device's snapshot. After a validated eligible conflict is fetched, the active family may explicitly choose **Keep Local** (conditionally publish the current local snapshot against that fetched server version) or **Use Cloud Copy** (replace only that family's local graph with the validated remote snapshot). Failed resolutions remain retryable, keep the family dirty when publication state is uncertain, and do not advance the change tag.
- Local data remains usable offline. Before a protected family mutation saves, the app durably marks that family for publication with a monotonically increasing family-scoped generation. A failed save rolls back only the intent introduced by that attempt, while a successful save coalesces a best-effort publication of the latest family snapshot. A publication completion clears only the generation it published, so an older in-flight operation cannot clear a newer mutation even if its transport ignores cancellation. Publication failure never rolls back the local save; unpublished families remain local-only, and the durable per-family intent allows later retry and reconstruction.
- Viewers retain no general mutation or publication capability. The sole publication exception is a durable, invitation-specific redemption intent created while a unique active code is pending and usable only after that exact invitation is consumed into a matching family, Apple ID, role, profile, membership, and active session. It publishes the accepted invitation and membership snapshot; failures remain retryable, while reused codes and foreign or mismatched sessions are rejected.
- Manual Publish and Sync controls remain available. Conflicts still require fetching the server snapshot before publishing again; automatic publication never uses last-writer-wins.

## Members

- A child requires a birthdate.
- A missing adult birthdate remains `nil`; do not fabricate one.
- Active members must be unique within a family by imported contact identifier, case-insensitive email, or normalized name plus matching birthdate.
- Deactivation preserves history rather than deleting the member.
- Avatars may be added, replaced, or removed.
- Child age and birthday calculations use calendar-day values.
- A profile linked to a family membership cannot be deactivated. The administrator/owner profile is specifically protected from lockout. A profile with an active, unexpired pending linked invitation cannot be deactivated until a family administrator/owner revokes it or it is otherwise resolved.
- Expired invitations are deterministically ignored by profile role/deactivation validation and are not presented as active shareable invitations. Family administrators/owners may revoke same-family pending invitations; unauthorized and foreign-family revocation attempts do not mutate them.
- A profile role cannot be changed when the proposed role is incompatible with any same-family linked membership or active, unexpired pending invitation. Inactive profiles cannot be edited or deactivated again, and foreign-family links are never changed by a member mutation.

## Reporting weeks

- Reporting weeks end on Saturday.
- Week values are normalized to the Saturday start of day.
- A reporting week contains the seven dates ending on that Saturday.
- The current day is the default activity day for the current week; a historical week defaults to its Saturday.
- Family and Ledger expose the shared selected reporting week.

## Starting points and balances

- Only children receive starting points.
- Starting points are `age at week ending × 100`.
- Approved ledger entries affect accounting totals.
- Pending entries are displayed separately and do not become approved value until reviewed.
- Store purchases are approved negative entries.
- A negative child settlement balance becomes debt carried into the immediately following week.
- Cash value is informational and never negative.
- A family's default conversion rate is `$0.01` per point and may be configured to a nonnegative value.

## Rules and eligibility

Rules may define count/time quantities, measurement units, minimums, maximums, daily/weekly maximum periods, warning units, acceleration, growth, riders, and age eligibility.

- No age bounds means all ages.
- A bounded rule is unavailable to a child with no birthdate.
- Minimum and maximum ages are inclusive.
- Parents are not restricted by child age bounds.
- The recorder may override calculated points for an individual entry.

## Quick activity workflow

The Family page is the primary fast-recording workflow.

- Children may expose reward and penalty actions.
- Parents expose penalty actions only.
- Caregivers expose neither as recipients.
- Selecting a rule is sufficient for the default save path.
- Optional configuration supports quantity, per-item weekdays, points, and notes.
- Saving multiple weekdays creates a separate ledger entry for each selected day.
- Entries retain recorder attribution, quantity, unit, and occurrence date.

## Ledger

The weekly ledger is the central accounting and approval view.

- Entries aggregate by recipient, rule/title, displayed kind, and occurrence day.
- Summaries preserve approved, pending, and rejected counts and points.
- Recorder attribution remains visible.
- Default sort is person, day, then item; users may select other columns and reset to default.
- Parent-capable users may review pending entries inline or in week-wide actions.
- Editing must retain quantity datatype/unit and recorder/audit information.
- Copying a prior week includes approved reward and penalty entries, preserves weekday placement, and excludes purchases and rejected/pending entries.
- Collapsed day groups are intentional; tests must expand the relevant group rather than assume child rows are visible.

## Parent penalty pot

Approved negative entries assigned to active parents form a positive weekly pot. The pot is divided evenly among active children. Integer remainder points are distributed deterministically by sorted child UUID.

The parent-pot share appears only when parent penalties created a positive share.

## Missed minimums

A missed-minimum deduction candidate exists only when a rule:

- Belongs to the child's family.
- Is enabled and age eligible.
- Is a positive reward.
- Has a minimum target.
- Enables `deductStartingPointsWhenMinimumMissed`.

Weekly minimums inspect the selected week. Monthly minimums are evaluated only by the reporting week containing the month boundary and inspect that calendar month.

Before closing, a parent must explicitly choose **Deduct** or **Absolve** for every candidate. “Absolve All” is allowed. The settlement stores both applied deduction details and review decisions for auditability.

## Settlement and closing

- Settlement applies only to past weeks with active non-rejected transactions.
- Each active child receives a settlement draft.
- Draft accounting includes starting points, debt carried in, approved entries, purchases, parent-pot share, selected missed-minimum deductions, final points/cash value, and debt carried out.
- Store purchases are grouped by item title with quantity and total points spent.
- Pending entries trigger a warning. Continuing explicitly rejects them before closing; the safe default is not to close.
- Closing is a global parent action for all unconfirmed child drafts.
- Closing requires a family admin, owner, or parent membership linked to an active parent profile, and revalidates all supplied members, rules, entries, and settlements as family-owned before any pending rejection or settlement mutation.
- Confirmed settlements store a transaction fingerprint and reviewer identity.
- A week is closed only when all active children have matching settlements and the underlying transaction state still matches.

## Storefront

- Only a user whose membership and profile are both child may purchase.
- Checkout additionally requires the membership Apple ID, family, and linked child profile to match the active session; a child cannot purchase for another or foreign-family child.
- Parent-capable roles manage store items.
- Store items are family-scoped, enabled for shoppers, age eligible, and ordered by shelf position then title.
- Inventory limits may be daily, weekly, or total.
- The cart supports multiple item quantities.
- Checkout must atomically revalidate availability, age, inventory, and affordability.
- Sold-out or unaffordable items must be clearly represented.

## Navigation and presentation

Top-level iOS tabs are Store, Rules, Ledger, Stats, and Family. There is no Record, Approvals, Dashboard, or Settlement top-level tab. Avoid nesting direct tabs beneath the system More controller in a way that produces duplicate navigation back buttons.

Member cards open member details. They do not open Store or invitation sharing. Invitation actions are explicit controls and are not shown for the current signed-in member.

## Statistics

Stats & Trends is a top-level page. Statistics are family-scoped and may include weekly/year trends, projections, trophies, and age-normalized comparisons. Historical comparisons must use the member's age at the compared period rather than today's age.