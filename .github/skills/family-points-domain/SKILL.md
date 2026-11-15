---
name: family-points-domain
description: Safely change family roles, activity submission, eligibility, point calculations, storefront behavior, or other family-points domain rules.
---

# Family-points domain changes

Use this skill for changes involving members, roles, rules, points, identity, invitations, Store, Stats, or family-scoped data.

## Before editing

1. Read `docs/PRODUCT_RULES.md` and `docs/ARCHITECTURE.md`.
2. Identify whether each rule uses `MemberRole`, `FamilyMembershipRole`, or both.
3. Trace the mutation entry point as well as visible UI controls.
4. Identify how the affected models are scoped to the active family.
5. Find existing unit and UI tests for the behavior.

## Required invariants

- No family may read or mutate another family's records.
- Authorization is checked before mutation, not inferred from hidden UI.
- Caregivers do not receive points and recommendations remain pending.
- Child submissions remain pending for parent review.
- Parent-capable memberships alone manage rules, review the ledger, and settle.
- Saturday remains the reporting-period boundary.
- Confirmed settlement history remains auditable.

## Implementation procedure

1. Put deterministic policy and calculations in a domain type, not a view.
2. Filter rules by `familyID` and entries through the family's member IDs.
3. Revalidate eligibility and authorization at save/checkout/review time.
4. Preserve recorder, reviewer, quantity, unit, occurrence date, and status metadata.
5. If persisted fields change, use migration-safe defaults and test old-value behavior.
6. Update `docs/PRODUCT_RULES.md` when product policy intentionally changes.

## Test cases

At minimum, cover:

- Authorized role succeeds.
- Each unauthorized role fails even if called directly.
- Caregiver behavior remains recommendation-only.
- Child versus parent approval state.
- Two-family isolation.
- Inactive member behavior where relevant.
- Missing child birthdate and age-bound eligibility.
- Current and historical reporting weeks.

For Store changes also cover disabled/wrong-family items, age eligibility, inventory period, cart quantity, affordability, and checkout revalidation.

## Review questions

- Is this checking membership capability or profile participation correctly?
- Could an unfiltered `@Query` leak a second family's records?
- Can a stale screen bypass current eligibility at save time?
- Does this alter a confirmed historical result?
- Are Watch snapshots or Stats now showing a different definition of balance?
