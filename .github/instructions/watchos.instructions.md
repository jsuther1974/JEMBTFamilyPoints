---
applyTo: "Family Points Watch App Watch App/**/*.swift,Family Points Watch App Watch AppTests/**/*.swift,Family Points Watch App Watch AppUITests/**/*.swift,JEMBT Family Points Tracker/WatchSyncBridge.swift"
---

# Watch and WatchConnectivity instructions

- Treat the iPhone-to-Watch snapshot as a versioned, property-list-compatible API.
- Keep Watch presentation read-only unless a separately authorized command protocol is intentionally designed.
- Publish only records scoped to the active family.
- Child balances and recent activity use approved entries; pending count is informational.
- Preserve deterministic member ordering and bounded recent activity.
- Keep the latest application context queued when the session is inactive or update fails.
- The Watch app must retain and display its last valid cached snapshot offline.
- Decode defensively; malformed fields must not erase a previously valid snapshot.
- Keep UI tests deterministic through the Watch sample environment rather than requiring a live phone.
- After schema changes, update both phone encoding and Watch decoding plus round-trip tests.
- Build and test on an actual Watch simulator destination; an iPhone build does not verify the Watch target or scheme.
