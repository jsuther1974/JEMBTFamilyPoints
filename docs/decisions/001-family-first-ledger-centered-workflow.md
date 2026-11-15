# 001: Family-first recording and Ledger-centered review

- Status: Accepted
- Date: 2026-11-14 (documented from existing implementation)

## Context

Recording an award or penalty is the app's highest-frequency workflow. Separate Record and Approvals destinations increased navigation and duplicated accounting presentation.

## Decision

- Family is the primary fast-recording surface.
- Eligible member cards expose direct reward/penalty actions.
- Selecting an item supports an immediate default save path, with optional configuration.
- Ledger is the central weekly accounting, editing, sorting, copying, and approval surface.
- Approvals and Record are not top-level tabs.
- Settlement remains a contextual parent workflow rather than a top-level tab.

## Consequences

Family UI must remain fast and role-aware. Ledger changes must preserve accounting density and disclosure behavior. Navigation tests protect tab labels and duplicate-back-button regressions.

## Enforced by

`ContentView.swift`, `ManageFamilyView.swift`, `PointsEngine.swift`, and iOS UI tests for Family quick activity, Ledger, and Rules navigation.
