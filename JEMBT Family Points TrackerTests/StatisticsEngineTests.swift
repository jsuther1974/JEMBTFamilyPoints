import XCTest
@testable import JEMBT_Family_Points_Tracker

final class StatisticsEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testTrophiesUseApprovedEarnedPointsAndPreserveTies() {
        let amy = child("Amy", born: date(2018, 1, 1))
        let ben = child("Ben", born: date(2018, 2, 1))
        let asOf = date(2026, 11, 10)
        let weekEnding = PointsEngine.weekEnding(containing: asOf, calendar: calendar)
        let entries = [
            entry(for: amy, points: 200, kind: .reward, status: .approved, occurredAt: date(2026, 11, 9), weekEnding: weekEnding),
            entry(for: ben, points: 200, kind: .reward, status: .approved, occurredAt: date(2026, 11, 10), weekEnding: weekEnding),
            entry(for: amy, points: 5_000, kind: .reward, status: .pending, occurredAt: date(2026, 11, 10), weekEnding: weekEnding),
            entry(for: ben, points: -500, kind: .purchase, status: .approved, occurredAt: date(2026, 11, 10), weekEnding: weekEnding)
        ]

        let trophies = StatisticsEngine.trophies(
            members: [amy, ben],
            entries: entries,
            asOf: asOf,
            calendar: calendar
        )

        XCTAssertEqual(trophies.count, 3)
        XCTAssertTrue(trophies.allSatisfy { Set($0.memberIDs) == Set([amy.id, ben.id]) })
        XCTAssertTrue(trophies.allSatisfy { $0.earnedPoints == 200 })
    }

    func testYearActivitySeparatesPerformanceFromStoreSpending() {
        let child = child("Child", born: date(2018, 1, 1))
        let asOf = date(2026, 11, 10)
        let weekEnding = PointsEngine.weekEnding(containing: asOf, calendar: calendar)
        let entries = [
            entry(for: child, points: 300, kind: .reward, status: .approved, occurredAt: date(2026, 11, 8), weekEnding: weekEnding),
            entry(for: child, points: -75, kind: .penalty, status: .approved, occurredAt: date(2026, 11, 9), weekEnding: weekEnding),
            entry(for: child, points: -100, kind: .purchase, status: .approved, occurredAt: date(2026, 11, 10), weekEnding: weekEnding)
        ]

        let activity = StatisticsEngine.yearActivity(
            members: [child],
            entries: entries,
            asOf: asOf,
            calendar: calendar
        ).first

        XCTAssertEqual(activity?.earned, 300)
        XCTAssertEqual(activity?.lost, 75)
        XCTAssertEqual(activity?.spent, 100)
        XCTAssertEqual(activity?.net, 225)
    }

    func testSameAgeComparisonAdjustsHistoricalPointScale() {
        let older = child("Older", born: date(2016, 1, 1))
        let younger = child("Younger", born: date(2018, 1, 1))
        let oldDate = date(2024, 6, 1)
        let currentDate = date(2026, 6, 1)
        let entries = [
            entry(
                for: older,
                points: 100,
                kind: .reward,
                status: .approved,
                occurredAt: oldDate,
                weekEnding: PointsEngine.weekEnding(containing: oldDate, calendar: calendar)
            ),
            entry(
                for: younger,
                points: 200,
                kind: .reward,
                status: .approved,
                occurredAt: currentDate,
                weekEnding: PointsEngine.weekEnding(containing: currentDate, calendar: calendar)
            )
        ]

        let comparison = StatisticsEngine.ageNormalizedComparison(
            age: 8,
            members: [older, younger],
            entries: entries,
            asOf: date(2026, 11, 10),
            calendar: calendar
        )

        XCTAssertEqual(comparison.count, 2)
        XCTAssertEqual(comparison.map(\.adjustedNetPoints), [200, 200])
        XCTAssertTrue(comparison.allSatisfy { $0.activeWeeks == 1 })
        XCTAssertTrue(comparison.allSatisfy { abs($0.performanceIndex - 25) < 0.001 })
    }

    func testProjectionExcludesPurchasesAndUsesPriorYearPaceWhenAvailable() {
        let child = child("Child", born: date(2018, 1, 1))
        let asOf = date(2026, 7, 1)
        let entries = [
            entry(
                for: child,
                points: 1_000,
                kind: .reward,
                status: .approved,
                occurredAt: date(2026, 2, 1),
                weekEnding: PointsEngine.weekEnding(containing: date(2026, 2, 1), calendar: calendar)
            ),
            entry(
                for: child,
                points: -900,
                kind: .purchase,
                status: .approved,
                occurredAt: date(2026, 3, 1),
                weekEnding: PointsEngine.weekEnding(containing: date(2026, 3, 1), calendar: calendar)
            ),
            entry(
                for: child,
                points: 500,
                kind: .reward,
                status: .approved,
                occurredAt: date(2025, 2, 1),
                weekEnding: PointsEngine.weekEnding(containing: date(2025, 2, 1), calendar: calendar)
            )
        ]

        let projection = StatisticsEngine.yearProjections(
            members: [child],
            entries: entries,
            asOf: asOf,
            calendar: calendar
        ).first

        XCTAssertEqual(projection?.yearToDateNet, 1_000)
        XCTAssertTrue(projection?.usesPriorYearPace == true)
        XCTAssertGreaterThan(projection?.projectedYearEndNet ?? 0, 1_000)
        XCTAssertEqual(projection?.previousYearNet, 500)
    }

    func testMemberInsightsSummarizeFrequenciesLastWeekAndTrends() {
        let child = child("Child", born: date(2018, 1, 1))
        let endingAt = date(2026, 11, 14)
        let currentWeek = PointsEngine.weekEnding(containing: endingAt, calendar: calendar)
        let lastWeek = PointsEngine.previousWeekEnding(before: currentWeek, calendar: calendar)
        let priorPeriodWeek = calendar.date(byAdding: .day, value: -35, to: currentWeek)!
        let entries = [
            entry(for: child, title: "Focus", points: 400, kind: .reward, status: .approved, occurredAt: currentWeek, weekEnding: currentWeek),
            entry(for: child, title: "Reading", points: 100, kind: .reward, status: .approved, occurredAt: lastWeek, weekEnding: lastWeek),
            entry(for: child, title: "reading", points: 100, kind: .reward, status: .approved, occurredAt: lastWeek, weekEnding: lastWeek),
            entry(for: child, title: "Chores", points: 150, kind: .reward, status: .approved, occurredAt: lastWeek, weekEnding: lastWeek),
            entry(for: child, title: "Late", points: -80, kind: .penalty, status: .approved, occurredAt: lastWeek, weekEnding: lastWeek),
            entry(for: child, title: "Mess", points: -100, kind: .penalty, status: .approved, occurredAt: lastWeek, weekEnding: lastWeek),
            entry(for: child, title: "Movie", points: -300, kind: .purchase, status: .approved, occurredAt: lastWeek, weekEnding: lastWeek, quantity: 2),
            entry(for: child, title: "Practice", points: 80, kind: .reward, status: .approved, occurredAt: priorPeriodWeek, weekEnding: priorPeriodWeek),
            entry(for: child, title: "Pending", points: 9_999, kind: .reward, status: .pending, occurredAt: currentWeek, weekEnding: currentWeek)
        ]

        let insights = StatisticsEngine.memberInsights(
            memberID: child.id,
            entries: entries,
            endingAt: endingAt,
            calendar: calendar
        )

        XCTAssertEqual(insights.activeWeeks, 3)
        XCTAssertEqual(insights.averageWeeklyNet, 650.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(insights.recentFourWeekAverage, 142.5, accuracy: 0.001)
        XCTAssertEqual(insights.trendFromPreviousFourWeeks, 122.5, accuracy: 0.001)
        XCTAssertEqual(insights.topAwardLastWeek, MemberActivityItemSummary(title: "Reading", count: 2, points: 200))
        XCTAssertEqual(insights.topPenaltyLastWeek, MemberActivityItemSummary(title: "Mess", count: 1, points: 100))
        XCTAssertEqual(insights.frequentAwards.first, MemberActivityItemSummary(title: "Reading", count: 2, points: 200))
        XCTAssertEqual(insights.frequentPurchases, [MemberActivityItemSummary(title: "Movie", count: 2, points: 300)])
    }

    private func child(_ name: String, born: Date) -> FamilyMember {
        FamilyMember(name: name, birthDate: born, role: .child)
    }

    private func entry(
        for member: FamilyMember,
        title: String = "Activity",
        points: Int,
        kind: EntryKind,
        status: ApprovalStatus,
        occurredAt: Date,
        weekEnding: Date,
        quantity: Double = 1
    ) -> LedgerEntry {
        LedgerEntry(
            memberID: member.id,
            occurredAt: occurredAt,
            weekEnding: weekEnding,
            title: title,
            points: points,
            kind: kind,
            status: status,
            submittedBy: "Parent",
            quantity: quantity
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
