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
    var isCompact = false

    private var selectableWeekEndings: [Date] {
        (-52...26).compactMap { offset in
            Calendar.current.date(
                byAdding: .day,
                value: offset * 7,
                to: reportingPeriod.weekEnding
            )
        }
    }

    var body: some View {
        @Bindable var reportingPeriod = reportingPeriod
        VStack(alignment: .leading, spacing: 6) {
            if !isCompact {
                Text("Week ending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    reportingPeriod.select(
                        PointsEngine.previousWeekEnding(before: reportingPeriod.weekEnding)
                    )
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous week")

                Picker(
                    "Week ending",
                    selection: Binding(
                        get: { reportingPeriod.weekEnding },
                        set: { reportingPeriod.select($0) }
                    )
                ) {
                    ForEach(selectableWeekEndings, id: \.self) { weekEnding in
                        Text(weekEnding.formatted(date: .abbreviated, time: .omitted))
                            .tag(weekEnding)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .controlSize(isCompact ? .regular : .large)

                Button {
                    if let nextWeek = Calendar.current.date(
                        byAdding: .day,
                        value: 7,
                        to: reportingPeriod.weekEnding
                    ) {
                        reportingPeriod.select(nextWeek)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next week")
            }
        }
        .accessibilityIdentifier("reportingWeekPicker")
    }
}