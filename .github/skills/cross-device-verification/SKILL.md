---
name: cross-device-verification
description: Implement and verify SwiftUI behavior across iPhone, iPad, and the Watch companion, including idiom-specific controls and WatchConnectivity snapshots.
---

# Cross-device verification

Use this skill when a change can affect layout, navigation, input, target membership, Watch snapshots, or platform schemes.

## Determine affected surfaces

Before editing, list:

- iPhone compact presentation.
- iPad regular-width and compact-sheet presentation.
- Watch glance/offline presentation.
- Shared models, assets, and schemes.

A shared SwiftUI source file does not guarantee identical interaction behavior.

## iPhone and iPad

- Check interface idiom as well as size class when UIKit input views or sheet behavior are involved.
- Preserve keyboard focus and tab order on iPhone.
- Prefer native SwiftUI picker/date controls on iPad member forms.
- Verify toolbars, menus, sheets, popovers, and navigation separately.
- Test tab overflow and ensure direct tabs do not acquire duplicate back buttons through the system More controller.
- Check Dynamic Type, readable contrast, and accessibility identifiers.

## Watch snapshot changes

1. Define the snapshot change as a versioned API change.
2. Update iPhone encoding and Watch decoding together.
3. Keep context values property-list compatible.
4. Scope data to the active family.
5. Keep approved balances/recent entries and pending informational counts semantically consistent.
6. Preserve the last valid cached snapshot when refresh or decoding fails.
7. Update round-trip tests and deterministic sample data.

## Verification matrix

1. Run focused unit tests for shared logic.
2. Build and run the iPhone app on an iPhone simulator.
3. Run any iPhone-specific UI regression.
4. Switch to an iPad destination and run regular-width interaction regressions.
5. Switch to the Watch scheme and a direct Watch simulator.
6. Run Watch unit tests and, when UI changed, Watch UI tests.
7. Verify offline cached presentation and reachable refresh behavior when Watch data changed.
8. Return the user's active scheme/destination only when appropriate and report any switch.

Do not claim cross-device completion based solely on compilation of the iOS target.
