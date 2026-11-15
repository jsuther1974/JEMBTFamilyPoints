---
name: swiftui-navigation-accessibility
description: Change SwiftUI navigation, cards, forms, disclosures, and adaptive controls without introducing duplicate navigation, gesture conflicts, inaccessible state, or device-specific regressions.
---

# SwiftUI navigation and accessibility

## Before editing

Map the presentation owner: tab, navigation stack, sheet, popover, disclosure group, and nested controls. Identify iPhone/iPad differences and existing UI-test selectors.

## Navigation rules

- A top-level tab should have one clear navigation stack owner.
- Avoid pushing a second copy of a top-level destination from a surrounding stack.
- Check whether tab ordering sends a destination under the iPhone system More controller.
- Member cards open details only; explicit share/edit controls own their own actions.
- Settlement remains contextual rather than a top-level tab unless product rules change.

## Forms and input

- Keep standard Save and Cancel placements.
- Do not fabricate optional values such as adult birthdates.
- Preserve iPhone keyboard focus/tab behavior.
- Use native iPad controls where custom UIKit input views become unreachable in sheets.
- Ensure validation appears near the action and is repeated at mutation time.

## Accessibility

- Give important controls stable semantic identifiers, not identifiers derived from volatile formatting when avoidable.
- Expose selected/unselected and pending/approved/rejected state through labels or values.
- Avoid combining a container in a way that hides nested actionable controls.
- Disclosure descendants may be absent while collapsed; tests must expand the row.
- Ensure icons have labels when meaning is not accompanied by text.
- Check contrast over wallpaper, material, gradients, and tinted cards.

## Verification

Run the focused flow on iPhone and iPad, inspect the hierarchy rather than guessing coordinates, and verify one back button, correct dismissal, stable selectors, disclosure state, keyboard behavior, and accessible labels/values.
