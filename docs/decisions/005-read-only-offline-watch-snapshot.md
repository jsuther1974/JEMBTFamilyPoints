# 005: Read-only offline Watch snapshot

- Status: Accepted
- Date: 2026-11-14 (documented from existing implementation)

## Context

The Watch should provide useful glance information without requiring an immediately reachable iPhone or duplicating the full SwiftData/authorization stack.

## Decision

The iPhone publishes a family-scoped, property-list-compatible snapshot through WatchConnectivity. The Watch decodes it into Codable value types, caches the last valid snapshot in `UserDefaults`, and displays it offline. Reachable refresh uses message/reply. The initial companion is read-only.

## Consequences

Snapshot fields form a versioned API. Phone encoding, Watch decoding, sample data, and tests change together. Failed refresh or malformed new data must not destroy a valid cache. Watch mutations require a separate authorization, synchronization, and conflict decision.

## Enforced by

`WatchSyncBridge.swift`, `WatchDashboardModel.swift`, Watch unit tests, and `.github/skills/cross-device-verification/SKILL.md`.
