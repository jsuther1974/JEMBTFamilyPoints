---
name: ledger-settlement-accounting
description: Change weekly ledger aggregation, review, copying, missed minimums, debt, parent-pot distribution, or settlement while preserving accounting and audit integrity.
---

# Ledger and settlement accounting

Use this skill for `LedgerEntry`, `LedgerSummary`, approval, copying, settlement, debt, parent-pot, minimum-miss, and closing behavior.

## Model the transaction first

A ledger transaction carries:

- Recipient and optional rule.
- Occurrence date and normalized Saturday week ending.
- Title, notes, points, kind, quantity, and measurement unit.
- Pending/approved/rejected status.
- Recorder plus optional reviewer and review time.

Do not discard these dimensions when aggregating or editing.

## Ledger aggregation

1. Scope entries to the active family's member IDs.
2. Select the reporting week.
3. Normalize occurrence dates through `PointsEngine.occurrenceDate`.
4. Group by recipient, rule/title, displayed kind, and day.
5. Preserve approved, pending, and rejected counts separately.
6. Derive record/next values from the intended approved/history set.
7. Keep sorting deterministic with an ID tie-breaker.

Copy-week behavior includes only approved rewards and penalties and preserves weekday placement. Purchases, pending entries, and rejected entries are excluded.

## Review

Only pending entries transition through review. Record reviewer and timestamp. Apply the same authorization checks to row, group, and week-wide actions. A settlement warning may explicitly reject remaining pending entries; never do this silently.

## Settlement order

For each active child, reason about:

1. Starting points at age on week ending.
2. Debt carried in from the immediately preceding settlement.
3. Approved entries, with purchases represented as spending.
4. Parent penalty-pot share.
5. Explicitly selected missed-minimum deductions.
6. Final points and nonnegative informational cash value.
7. Negative remainder as debt carried out.

Store purchases are grouped by title for presentation but remain individual ledger entries.

## Missed minimums

Generate candidates only for enabled, eligible, positive reward rules that opt into deduction and have a minimum. Weekly candidates inspect that week. Monthly candidates are evaluated only when the reporting week closes a month. Require a Deduct/Absolve decision for every candidate and persist review details.

## Historical integrity

- Confirmed settlements are snapshots.
- Store reviewer identity, confirmation time, deduction/review details, and transaction fingerprint.
- A fingerprint mismatch means the week is not safely closed.
- Never make a later rule edit retroactively alter a confirmed result.

## Required tests

Cover positive, zero, and negative totals; missing birthdates; inactive members; pending/rejected entries; even and remainder parent-pot splits; prior-week debt; weekly/monthly minimums; deduct and absolve decisions; purchase grouping; fingerprint changes; and all-child closure requirements.

For Ledger UI changes, test collapsed day rows, expansion, summary visibility, inline status, double-tap editing, quantity units, and default/multi-column sorting.
