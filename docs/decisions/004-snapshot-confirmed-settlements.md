# 004: Snapshot confirmed settlements with audit decisions

- Status: Accepted
- Date: 2026-11-14 (documented from existing implementation)

## Context

Rules, ages, entries, minimums, and conversion rates can change. Recomputing old weeks from current configuration would alter previously confirmed family accounting.

## Decision

A confirmed `WeeklySettlement` stores the accounting inputs/results, reviewer and confirmation time, missed-minimum deduction/review details, and a transaction fingerprint. Parents explicitly choose Deduct or Absolve for each missed requirement. A week is considered closed only when every active child has a matching settlement and transaction state remains consistent.

## Consequences

Confirmed history is an audit snapshot, not a live projection. Later rule edits must not rewrite it. Corrections require an explicit future audited workflow rather than silent mutation.

## Enforced by

`WeeklySettlement`, `SettlementDraft`, `PointsEngine.transactionFingerprint`, `PointsEngine.isWeekClosed`, `SettlementView`, and settlement unit tests.
