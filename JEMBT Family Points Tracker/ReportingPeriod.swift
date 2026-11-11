import Observation
import SwiftUI

@MainActor
@Observable
final class ReportingPeriod {
    var weekEnding: Date

    init(weekEnding: Date = .now) {
        self.weekEnding = PointsEngine.weekEnding(containing: weekEnding)
    }

    func select(_ date: Date) {
        weekEnding = PointsEngine.weekEnding(containing: date)
    }
}

struct ReportingWeekPicker: View {
    @Environment(ReportingPeriod.self) private var reportingPeriod

    var body: some View {
        @Bindable var reportingPeriod = reportingPeriod
        DatePicker(
            "Week ending",
            selection: Binding(
                get: { reportingPeriod.weekEnding },
                set: { reportingPeriod.select($0) }
            ),
            displayedComponents: .date
        )
        .accessibilityIdentifier("reportingWeekPicker")
    }
}