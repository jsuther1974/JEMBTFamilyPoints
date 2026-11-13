import Charts
import SwiftData
import SwiftUI

struct FamilyStatisticsView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @State private var selectedAge = 0

    private var children: [FamilyMember] {
        guard let familyID = appleIDManager.currentFamily?.id else { return [] }
        return members
            .filter { $0.familyID == familyID && $0.isActive && $0.role == .child }
            .sorted(by: FamilyMember.comesBeforeInFamilyList)
    }

    private var familyEntries: [LedgerEntry] {
        let memberIDs = Set(children.map(\.id))
        return entries.filter { memberIDs.contains($0.memberID) }
    }

    private var names: [UUID: String] {
        Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0.name) })
    }

    private var weeklyActivity: [MemberWeekStatistic] {
        StatisticsEngine.weeklyActivity(
            members: children,
            entries: familyEntries,
            endingAt: .now
        )
    }

    private var yearActivity: [MemberYearActivity] {
        StatisticsEngine.yearActivity(members: children, entries: familyEntries, asOf: .now)
    }

    private var trophies: [PeriodTrophy] {
        StatisticsEngine.trophies(members: children, entries: familyEntries, asOf: .now)
    }

    private var availableAges: [Int] {
        StatisticsEngine.agesWithHistory(members: children, entries: familyEntries)
    }

    private var ageComparison: [AgeNormalizedStatistic] {
        StatisticsEngine.ageNormalizedComparison(
            age: selectedAge,
            members: children,
            entries: familyEntries,
            asOf: .now
        )
    }

    private var projections: [MemberYearProjection] {
        StatisticsEngine.yearProjections(members: children, entries: familyEntries, asOf: .now)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if children.isEmpty {
                    ContentUnavailableView(
                        "No Child Statistics",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Add a child to begin building family trends.")
                    )
                } else {
                    trophiesSection
                    weeklyTrendSection
                    yearSection
                    ageSection
                    projectionSection
                    methodologySection
                }
            }
            .padding()
        }
        .navigationTitle("Stats & Trends")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("familyStatisticsPage")
        .onAppear {
            selectInitialAge()
        }
        .onChange(of: availableAges) { selectInitialAge() }
    }

    private var trophiesSection: some View {
        statisticsCard(title: "Trophy Case", subtitle: "Highest approved reward points earned") {
            HStack(alignment: .top, spacing: 10) {
                ForEach(trophies) { trophy in
                    VStack(spacing: 7) {
                        Image(systemName: trophy.memberIDs.isEmpty ? "trophy" : "trophy.fill")
                            .font(.title2)
                            .foregroundStyle(trophy.memberIDs.isEmpty ? Color.secondary : Color.yellow)
                        Text(trophy.period.rawValue)
                            .font(.caption.bold())
                        Text(winnerNames(for: trophy))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(trophy.memberIDs.isEmpty ? "No activity" : "\(trophy.earnedPoints.formatted()) pts")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("statsTrophy-\(trophy.period.rawValue)")
                }
            }
        }
    }

    private var weeklyTrendSection: some View {
        statisticsCard(title: "13-Week Momentum", subtitle: "Approved rewards minus penalties; purchases excluded") {
            Chart(weeklyActivity) { statistic in
                LineMark(
                    x: .value("Week", statistic.weekEnding),
                    y: .value("Net points", statistic.net)
                )
                .foregroundStyle(by: .value("Child", names[statistic.memberID] ?? "Unknown"))
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Week", statistic.weekEnding),
                    y: .value("Net points", statistic.net)
                )
                .foregroundStyle(by: .value("Child", names[statistic.memberID] ?? "Unknown"))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 230)
            .accessibilityIdentifier("statsWeeklyTrendChart")
        }
    }

    private var yearSection: some View {
        statisticsCard(title: "Year to Date", subtitle: "Performance and spending through today") {
            Chart(yearActivity) { activity in
                BarMark(
                    x: .value("Child", names[activity.memberID] ?? "Unknown"),
                    y: .value("Net points", activity.net)
                )
                .foregroundStyle(activity.net < 0 ? Color.red : Color.green)
                .annotation(position: activity.net < 0 ? .bottom : .top) {
                    Text(activity.net.formatted())
                        .font(.caption2.monospacedDigit())
                }
            }
            .frame(height: 210)
            .accessibilityIdentifier("statsYearChart")

            ForEach(yearActivity) { activity in
                HStack {
                    Text(names[activity.memberID] ?? "Unknown")
                    Spacer()
                    Text("Earned \(activity.earned.formatted())")
                        .foregroundStyle(.green)
                    Text("Lost \(activity.lost.formatted())")
                        .foregroundStyle(.red)
                    Text("Spent \(activity.spent.formatted())")
                        .foregroundStyle(.blue)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var ageSection: some View {
        statisticsCard(
            title: "Same-Age Comparison",
            subtitle: "Average weekly net as a percentage of the age-based starting value"
        ) {
            if availableAges.isEmpty {
                Text("Add approved history with child birthdates to unlock age comparisons.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Compare at age", selection: $selectedAge) {
                    ForEach(availableAges, id: \.self) { age in
                        Text("Age \(age)").tag(age)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("statsAgePicker")

                Chart(ageComparison) { statistic in
                    BarMark(
                        x: .value("Child", names[statistic.memberID] ?? "Unknown"),
                        y: .value("Performance index", statistic.performanceIndex)
                    )
                    .foregroundStyle(by: .value("Child", names[statistic.memberID] ?? "Unknown"))
                    .annotation(position: statistic.performanceIndex < 0 ? .bottom : .top) {
                        Text(statistic.performanceIndex, format: .number.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                    }
                }
                .chartYAxisLabel("% of weekly starting value")
                .frame(height: 210)
                .accessibilityIdentifier("statsAgeComparisonChart")

                ForEach(ageComparison) { statistic in
                    HStack {
                        Text(names[statistic.memberID] ?? "Unknown")
                        Spacer()
                        Text("\(statistic.activeWeeks) active wk")
                        Text("\(Int(statistic.averageWeeklyNet.rounded()).formatted()) avg pts")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var projectionSection: some View {
        statisticsCard(title: "Year-End Forecast", subtitle: "Current pace blended with comparable prior-year pace when available") {
            Chart(projections) { projection in
                BarMark(
                    x: .value("Child", names[projection.memberID] ?? "Unknown"),
                    y: .value("Projected net", projection.projectedYearEndNet)
                )
                .foregroundStyle(.purple.gradient)
                .annotation(position: projection.projectedYearEndNet < 0 ? .bottom : .top) {
                    Text(projection.projectedYearEndNet.formatted())
                        .font(.caption2.monospacedDigit())
                }
            }
            .frame(height: 210)
            .accessibilityIdentifier("statsProjectionChart")

            ForEach(projections) { projection in
                HStack {
                    Text(names[projection.memberID] ?? "Unknown")
                    Spacer()
                    Text("YTD \(projection.yearToDateNet.formatted())")
                    Text(projection.usesPriorYearPace ? "YTD + prior-year blend" : "YTD pace")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var methodologySection: some View {
        statisticsCard(title: "How These Numbers Work", subtitle: nil) {
            Label("Only approved entries count. Purchases are reported separately from performance.", systemImage: "checkmark.seal")
            Label("Same-age history is adjusted using each year’s typical point award, then normalized by age × 100 starting points.", systemImage: "scalemass")
            Label("Forecasts are estimates, not goals or guarantees, and become more stable as history grows.", systemImage: "sparkles")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statisticsCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func winnerNames(for trophy: PeriodTrophy) -> String {
        trophy.memberIDs.compactMap { names[$0] }.joined(separator: " & ")
    }

    private func selectInitialAge() {
        guard !availableAges.isEmpty else { return }
        if !availableAges.contains(selectedAge) {
            selectedAge = availableAges.last!
        }
    }
}