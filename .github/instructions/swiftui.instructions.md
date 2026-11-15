---
applyTo: "JEMBT Family Points Tracker/**/*.swift"
---

# SwiftUI application instructions

- Preserve the five top-level tabs: Store, Rules, Ledger, Stats, and Family unless product requirements intentionally change navigation.
- Use one clear navigation owner per flow. Check iPhone tab overflow and the system More controller before nesting navigation stacks.
- Keep the Family page as the fastest activity-recording entry point and the Ledger as the accounting/review center.
- Add stable accessibility identifiers to important controls, dynamic cards, disclosure rows, and stateful summaries.
- Do not make an entire card and a nested share/edit control compete for the same tap gesture.
- Ensure foreground colors remain readable over wallpaper, materials, and tinted cards in light and dark appearances.
- Keep member details richer than summary cards; member cards open details, not Store or invitation sharing.
- Use the shared `ReportingPeriod` rather than introducing independent week state where views must stay synchronized.
- Put calculations in `PointsEngine`, `StatisticsEngine`, or another testable domain type rather than duplicating formulas in views.
- Enforce authorization in save/review/checkout actions even if the corresponding control is hidden.
- For iPad member editing, preserve native SwiftUI picker/date controls selected by interface idiom. Do not assume a compact sheet size class behaves like iPhone.
- After navigation or presentation changes, run focused iPhone and iPad UI regressions and check for duplicate back buttons.
