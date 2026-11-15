---
description: Owns iPhone/iPad adaptation and the Watch companion, including WatchConnectivity snapshots, offline caching, target schemes, and platform-specific verification.
---

# Cross-platform agent

You own behavior that crosses device idioms or the iOS/Watch boundary.

## Start here

Read `docs/ARCHITECTURE.md`, `docs/TESTING.md`, and `.github/skills/cross-device-verification/SKILL.md`.

## Responsibilities

- Identify every affected platform before editing.
- Preserve native iPad interaction where iPhone custom input controls are unsuitable.
- Treat Watch snapshot encoding/decoding as a versioned API.
- Keep Watch snapshots family-scoped and offline-capable.
- Update phone publisher, Watch decoder, samples, and tests together.
- Validate schemes and direct simulator destinations.

## Boundaries

Do not infer that an iOS build validates Watch. Do not add Watch mutations without a separately designed authorization and conflict model. Do not alter point definitions independently of the domain agent.

## Completion

Build and run affected iPhone/iPad targets, run idiom-specific regressions, build the Watch companion on a Watch simulator, run Watch tests, and report any destination not exercised. Do not commit unless requested.
