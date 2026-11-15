# Agent collaboration guide

This file explains how humans, primary coding agents, and subagents should work in this repository.

## Operating model

1. Restate the objective as observable acceptance criteria.
2. Read the global instructions and applicable path instructions.
3. Inspect `WORK_STATUS.md`, then verify its claims against code and tests.
4. Use a search subagent for broad symbol tracing or codebase mapping.
5. Assign one implementation owner per file or tightly coupled feature area.
6. Use an independent reviewer for authorization, family scoping, accounting, accessibility, and regression risk.
7. Run focused verification before broader suites.
8. Report evidence, not just a claim that the task is complete.

Subagents should return findings to the primary agent. They should not make overlapping edits to the same files. Parallel work is appropriate only when tasks are independent—for example, domain research, UI mapping, and test inventory.

## Durable knowledge locations

- Universal rules: `.github/copilot-instructions.md`
- Path-specific rules: `.github/instructions/`
- Repeatable procedures: `.github/skills/`
- Specialized agent roles: `.github/agents/`
- Product behavior: `docs/PRODUCT_RULES.md`
- Architecture and boundaries: `docs/ARCHITECTURE.md`
- Test matrix and reliability rules: `docs/TESTING.md`
- Temporary handoff: `WORK_STATUS.md`
- Soundtrack rights and production record: `SOUNDTRACK_PROVENANCE.md`

Update the narrowest appropriate document. Do not put temporary status into permanent product rules, and do not use a skill as a changelog.

## Request format

The most effective work request contains:

- **Objective:** what the user should be able to do.
- **Constraints:** role, accounting, privacy, platform, or compatibility requirements.
- **Acceptance criteria:** observable behavior and edge cases.
- **Platforms:** iPhone, iPad, Watch, or all affected platforms.
- **Verification:** required tests or scenarios.
- **Git action:** no commit, commit, or commit and push.

If implementation details are omitted, investigate and choose the smallest design consistent with existing architecture.

## Definition of done

A change is done only when the agent has:

- Traced affected definitions and usages.
- Preserved family isolation and authorization.
- Considered migration/history compatibility for persisted data.
- Added or updated tests for important behavior.
- Refreshed diagnostics for edited source files.
- Run focused tests and the relevant broader suite.
- Checked affected iPhone/iPad/Watch destinations.
- Reviewed accessibility identifiers and navigation behavior.
- Run `git diff --check` and inspected the final diff.
- Listed any expected skip, warning, unverified destination, or known limitation.

A successful build alone is not completion when behavior changed.

## Review priorities

Review in this order:

1. Data isolation between families.
2. Unauthorized mutations or approval bypasses.
3. Incorrect point, purchase, debt, or settlement accounting.
4. Historical settlement integrity.
5. Persistent-store and CloudKit regressions.
6. Navigation, accessibility, and device-specific regressions.
7. Test reliability and hidden shared state.
8. Audio provenance and runtime lifecycle when applicable.

## Guardrails

- Do not weaken an assertion simply to make a test green.
- Do not introduce arbitrary sleeps when a deterministic state can be observed.
- Do not expose test-only configuration in normal launches.
- Do not infer authorization solely from visible buttons.
- Do not let a broad refactor obscure a targeted behavioral fix.
- Do not claim a destination was verified unless it actually ran there.
- Do not commit or push unless explicitly requested.
