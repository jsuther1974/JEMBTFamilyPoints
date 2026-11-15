# 002: Separate membership authorization from profile participation

- Status: Accepted
- Date: 2026-11-14 (documented from existing implementation)

## Context

A signed-in person's authority in a family and a profile's participation in points are different concerns. Conflating them caused ambiguity for parents, children, and caregivers.

## Decision

- `FamilyMembershipRole` controls administrative capabilities.
- `MemberRole` controls points participation and family presentation.
- Family admin, owner, and parent memberships may manage rules and review the ledger.
- Caregiver profiles do not participate in points.
- Caregiver activity is a recommendation requiring parent review.
- Child activity requires parent review; parent activity may be directly approved.
- Authorization is enforced at mutation boundaries, not only in visible controls.

## Consequences

Features involving roles must test both role concepts and direct unauthorized calls. Family scoping remains independent and mandatory.

## Enforced by

`DomainModels.swift` (`ActivitySubmissionPolicy`, `MemberRole`, `FamilyMembershipRole`), role-aware views, domain tests, and caregiver UI tests.
