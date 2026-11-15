---
applyTo: "JEMBT Family Points Tracker/{DomainModels,AppleIDManager,SeedData,JEMBTFamilyPointsTrackerApp,PointsEngine,StorefrontViews,StatisticsEngine}.swift"
---

# SwiftData and domain instructions

- Read `docs/ARCHITECTURE.md`, `docs/PRODUCT_RULES.md`, and the applicable domain skill before changing these files.
- Scope family-owned data by `currentFamily.id` or a verified set of that family's member IDs.
- Treat membership authorization and member points participation as separate concerns.
- Keep accounting deterministic and UI-independent.
- Prefer additive persisted fields that are optional or have migration-safe defaults.
- Preserve raw-value fallback behavior for existing records.
- Consider confirmed settlement history and transaction fingerprints before changing entry semantics.
- Normal app configuration must remain persistent with CloudKit `.automatic`.
- Test configurations must be in memory with CloudKit `.none`.
- Do not assume SwiftData's automatic private CloudKit database shares records across Apple IDs.
- Never hide a schema or initialization failure by silently discarding the production store.
- Add unit tests for family isolation, authorization, old/default values, and affected accounting boundaries.
