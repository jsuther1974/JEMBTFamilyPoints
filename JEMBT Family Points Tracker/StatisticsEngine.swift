import Foundation

struct MemberWeekStatistic: Identifiable {
    let memberID: UUID
    let weekEnding: Date
    let earned: Int
    let lost: Int
    let spent: Int

    var net: Int { earned - lost }
    var id: String { "\(memberID.uuidString)-\(weekEnding.timeIntervalSinceReferenceDate)" }
}

struct PeriodTrophy: Identifiable {
    enum Period: String, CaseIterable {
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
    }

    let period: Period
    let memberIDs: [UUID]
    let earnedPoints: Int

    var id: String { period.rawValue }
}

struct AgeNormalizedStatistic: Identifiable {
    let memberID: UUID
    let age: Int
    let activeWeeks: Int
    let adjustedNetPoints: Int
    let averageWeeklyNet: Double
    let performanceIndex: Double

    var id: UUID { memberID }
}

struct MemberYearProjection: Identifiable {
    let memberID: UUID
    let yearToDateNet: Int
    let projectedYearEndNet: Int
    let previousYearNet: Int?
    let usesPriorYearPace: Bool

    var id: UUID { memberID }
}

struct MemberYearActivity: Identifiable {
    let memberID: UUID
    let earned: Int
    let lost: Int
    let spent: Int

    var net: Int { earned - lost }
    var id: UUID { memberID }
}

enum StatisticsEngine {
    static func weeklyActivity(
        members: [FamilyMember],
        entries: [LedgerEntry],
        endingAt date: Date,
        weekCount: Int = 13,
        calendar: Calendar = .current
    ) -> [MemberWeekStatistic] {
        guard weekCount > 0 else { return [] }
        let children = members.filter { $0.isActive && $0.role == .child }
        let childIDs = Set(children.map(\.id))
        let lastWeek = PointsEngine.weekEnding(containing: date, calendar: calendar)
        let weeks = (0..<weekCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -7 * $0, to: lastWeek)
        }
        let approved = approvedFamilyEntries(entries, memberIDs: childIDs)

        return children.flatMap { child in
            weeks.map { week in
                let weekEntries = approved.filter {
                    $0.memberID == child.id && calendar.isDate($0.weekEnding, inSameDayAs: week)
                }
                return statistic(memberID: child.id, weekEnding: week, entries: weekEntries)
            }
        }
    }

    static func yearActivity(
        members: [FamilyMember],
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [MemberYearActivity] {
        let children = members.filter { $0.isActive && $0.role == .child }
        let interval = calendar.dateInterval(of: .year, for: date)!
        let approved = approvedFamilyEntries(entries, memberIDs: Set(children.map(\.id))).filter {
            interval.contains(PointsEngine.occurrenceDate(for: $0, calendar: calendar)) &&
                PointsEngine.occurrenceDate(for: $0, calendar: calendar) <= date
        }

        return children.map { child in
            let memberEntries = approved.filter { $0.memberID == child.id }
            return MemberYearActivity(
                memberID: child.id,
                earned: earnedPoints(in: memberEntries),
                lost: lostPoints(in: memberEntries),
                spent: spentPoints(in: memberEntries)
            )
        }
    }

    static func trophies(
        members: [FamilyMember],
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [PeriodTrophy] {
        let children = members.filter { $0.isActive && $0.role == .child }
        let childIDs = Set(children.map(\.id))
        let approved = approvedFamilyEntries(entries, memberIDs: childIDs)
        let weekEnd = PointsEngine.weekEnding(containing: date, calendar: calendar)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!
        let intervals: [(PeriodTrophy.Period, DateInterval)] = [
            (.week, DateInterval(start: weekStart, end: calendar.date(byAdding: .day, value: 1, to: weekEnd)!)),
            (.month, calendar.dateInterval(of: .month, for: date)!),
            (.year, calendar.dateInterval(of: .year, for: date)!)
        ]

        return intervals.map { period, interval in
            let totals = Dictionary(grouping: approved.filter {
                let occurrence = PointsEngine.occurrenceDate(for: $0, calendar: calendar)
                return interval.contains(occurrence) && occurrence <= date
            }, by: \.memberID).mapValues(earnedPoints)
            let top = totals.values.max() ?? 0
            let winners = top > 0
                ? children.filter { totals[$0.id] == top }.map(\.id)
                : []
            return PeriodTrophy(period: period, memberIDs: winners, earnedPoints: top)
        }
    }

    static func agesWithHistory(
        members: [FamilyMember],
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> [Int] {
        let childrenByID = Dictionary(uniqueKeysWithValues: members
            .filter { $0.role == .child && $0.birthDate != nil }
            .map { ($0.id, $0) })
        return Set(entries.compactMap { entry in
            guard entry.status == .approved, entry.kind != .purchase,
                  let member = childrenByID[entry.memberID] else { return nil }
            return PointsEngine.age(
                from: member.birthDate,
                at: PointsEngine.occurrenceDate(for: entry, calendar: calendar),
                calendar: calendar
            )
        }).filter { $0 >= 0 }.sorted()
    }

    static func ageNormalizedComparison(
        age: Int,
        members: [FamilyMember],
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [AgeNormalizedStatistic] {
        guard age >= 0 else { return [] }
        let children = members.filter { $0.role == .child && $0.birthDate != nil }
        let approved = approvedFamilyEntries(entries, memberIDs: Set(children.map(\.id)))
            .filter { $0.kind != .purchase }
        let currentYear = calendar.component(.year, from: date)
        let scaleByYear = pointScaleByYear(entries: approved, calendar: calendar)
        let currentScale = scaleByYear[currentYear] ?? scaleByYear.values.max() ?? 1
        let baseline = max(1, age * 100)

        return children.compactMap { child in
            let matching = approved.filter {
                $0.memberID == child.id &&
                    PointsEngine.age(
                        from: child.birthDate,
                        at: PointsEngine.occurrenceDate(for: $0, calendar: calendar),
                        calendar: calendar
                    ) == age
            }
            guard !matching.isEmpty else { return nil }
            let activeWeeks = Set(matching.map { calendar.startOfDay(for: $0.weekEnding) }).count
            let adjustedNet = matching.reduce(0.0) { result, entry in
                let year = calendar.component(.year, from: PointsEngine.occurrenceDate(for: entry, calendar: calendar))
                let historicalScale = scaleByYear[year] ?? currentScale
                return result + Double(performancePoints(entry)) * currentScale / max(1, historicalScale)
            }
            let average = adjustedNet / Double(max(1, activeWeeks))
            return AgeNormalizedStatistic(
                memberID: child.id,
                age: age,
                activeWeeks: activeWeeks,
                adjustedNetPoints: Int(adjustedNet.rounded()),
                averageWeeklyNet: average,
                performanceIndex: average / Double(baseline) * 100
            )
        }.sorted { $0.performanceIndex > $1.performanceIndex }
    }

    static func yearProjections(
        members: [FamilyMember],
        entries: [LedgerEntry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [MemberYearProjection] {
        let children = members.filter { $0.isActive && $0.role == .child }
        let approved = approvedFamilyEntries(entries, memberIDs: Set(children.map(\.id)))
            .filter { $0.kind != .purchase }
        let currentInterval = calendar.dateInterval(of: .year, for: date)!
        let previousDate = calendar.date(byAdding: .year, value: -1, to: date)!
        let previousInterval = calendar.dateInterval(of: .year, for: previousDate)!
        let elapsedWeeks = max(1, calendar.component(.weekOfYear, from: date))
        let totalWeeks = calendar.range(of: .weekOfYear, in: .year, for: date)?.count ?? 52
        let previousComparableEnd = min(
            previousInterval.end,
            calendar.date(byAdding: .day, value: calendar.ordinality(of: .day, in: .year, for: date)! - 1, to: previousInterval.start)!
        )

        return children.map { child in
            let memberEntries = approved.filter { $0.memberID == child.id }
            let currentEntries = memberEntries.filter {
                let occurrence = PointsEngine.occurrenceDate(for: $0, calendar: calendar)
                return currentInterval.contains(occurrence) && occurrence <= date
            }
            let previousComparable = memberEntries.filter {
                let occurrence = PointsEngine.occurrenceDate(for: $0, calendar: calendar)
                return previousInterval.contains(occurrence) && occurrence < previousComparableEnd
            }
            let previousFull = memberEntries.filter {
                previousInterval.contains(PointsEngine.occurrenceDate(for: $0, calendar: calendar))
            }
            let currentNet = currentEntries.reduce(0) { $0 + performancePoints($1) }
            let previousComparableNet = previousComparable.reduce(0) { $0 + performancePoints($1) }
            let previousFullNet = previousFull.isEmpty ? nil : previousFull.reduce(0) { $0 + performancePoints($1) }
            let currentPace = Double(currentNet) / Double(elapsedWeeks)
            let previousPace = Double(previousComparableNet) / Double(elapsedWeeks)
            let hasPriorPace = !previousComparable.isEmpty
            let projectedPace = hasPriorPace ? currentPace * 0.7 + previousPace * 0.3 : currentPace
            let remainingWeeks = max(0, totalWeeks - elapsedWeeks)
            let projection = Double(currentNet) + projectedPace * Double(remainingWeeks)
            return MemberYearProjection(
                memberID: child.id,
                yearToDateNet: currentNet,
                projectedYearEndNet: Int(projection.rounded()),
                previousYearNet: previousFullNet,
                usesPriorYearPace: hasPriorPace
            )
        }.sorted { $0.projectedYearEndNet > $1.projectedYearEndNet }
    }

    private static func approvedFamilyEntries(
        _ entries: [LedgerEntry],
        memberIDs: Set<UUID>
    ) -> [LedgerEntry] {
        entries.filter { memberIDs.contains($0.memberID) && $0.status == .approved }
    }

    private static func statistic(
        memberID: UUID,
        weekEnding: Date,
        entries: [LedgerEntry]
    ) -> MemberWeekStatistic {
        MemberWeekStatistic(
            memberID: memberID,
            weekEnding: weekEnding,
            earned: earnedPoints(in: entries),
            lost: lostPoints(in: entries),
            spent: spentPoints(in: entries)
        )
    }

    private static func earnedPoints(in entries: [LedgerEntry]) -> Int {
        entries.reduce(0) { total, entry in
            entry.kind == .purchase ? total : total + max(0, entry.points)
        }
    }

    private static func lostPoints(in entries: [LedgerEntry]) -> Int {
        entries.reduce(0) { total, entry in
            entry.kind == .purchase ? total : total + abs(min(0, entry.points))
        }
    }

    private static func spentPoints(in entries: [LedgerEntry]) -> Int {
        entries.reduce(0) { total, entry in
            entry.kind == .purchase ? total + abs(entry.points) : total
        }
    }

    private static func performancePoints(_ entry: LedgerEntry) -> Int {
        entry.kind == .purchase ? 0 : entry.points
    }

    private static func pointScaleByYear(
        entries: [LedgerEntry],
        calendar: Calendar
    ) -> [Int: Double] {
        Dictionary(grouping: entries.filter { $0.points != 0 }) {
            calendar.component(.year, from: PointsEngine.occurrenceDate(for: $0, calendar: calendar))
        }.mapValues { yearEntries in
            let values = yearEntries.map { Double(abs($0.points)) }.sorted()
            guard !values.isEmpty else { return 1 }
            let middle = values.count / 2
            return values.count.isMultiple(of: 2)
                ? (values[middle - 1] + values[middle]) / 2
                : values[middle]
        }
    }
}