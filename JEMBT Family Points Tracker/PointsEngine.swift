import Foundation

struct LedgerSummary: Identifiable {
    let memberID: UUID
    let ruleID: UUID?
    let title: String
    let iconName: String
    let kind: EntryKind
    let occurredAt: Date
    let submittedBy: String
    let weeklyCount: Int
    let recordWeeklyCount: Int
    let weeklyPoints: Int
    let recordWeeklyPoints: Int
    let nextPoints: Int?
    let approvedCount: Int
    let approvedPoints: Int
    let pendingCount: Int
    let pendingPoints: Int
    let rejectedCount: Int
    let entryIDs: [UUID]
    let pendingEntryIDs: [UUID]

    var hasPendingEntries: Bool { pendingCount > 0 }

    var id: String {
        "\(memberID.uuidString)-\(ruleID?.uuidString ?? title)-\(kind.rawValue)-\(occurredAt.timeIntervalSinceReferenceDate)"
    }
}

nonisolated enum LedgerSortColumn: String, CaseIterable, Identifiable {
    case type, item, status, person, day, recordedBy, count, recordCount, points, recordPoints, next

    var id: String { rawValue }
}

nonisolated struct LedgerSortDescriptor: Equatable {
    let column: LedgerSortColumn
    let ascending: Bool
}

struct PendingPointTotals {
    let count: Int
    let earned: Int
    let lost: Int

    var net: Int { earned - lost }
}

enum PointsEngine {

    static let defaultLedgerSort = [
        LedgerSortDescriptor(column: .person, ascending: true),
        LedgerSortDescriptor(column: .day, ascending: true),
        LedgerSortDescriptor(column: .item, ascending: true)
    ]
    static func weekEnding(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysUntilSaturday, to: startOfDay)!
    }

    static func previousWeekEnding(
        before weekEnding: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: -7, to: weekEnding)!
    }

    static func age(
        of member: FamilyMember,
        at weekEnding: Date,
        calendar: Calendar = .current
    ) -> Int {
        age(from: member.birthDate, at: weekEnding, calendar: calendar) ?? 0
    }

    static func dates(inWeekEnding weekEnding: Date, calendar: Calendar = .current) -> [Date] {
        let end = calendar.startOfDay(for: weekEnding)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: end)
        }
    }

    static func dates(
        inWeekEnding weekEnding: Date,
        matchingWeekdays weekdays: Set<Int>,
        calendar: Calendar = .current
    ) -> [Date] {
        dates(inWeekEnding: weekEnding, calendar: calendar).filter {
            weekdays.contains(calendar.component(.weekday, from: $0))
        }
    }

    static func defaultWeekday(
        inWeekEnding weekEnding: Date,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let date = calendar.isDate(self.weekEnding(containing: today, calendar: calendar), inSameDayAs: weekEnding)
            ? today
            : weekEnding
        return calendar.component(.weekday, from: date)
    }

    static func occurrenceDate(
        for entry: LedgerEntry,
        calendar: Calendar = .current
    ) -> Date {
        let occurredAt = calendar.startOfDay(for: entry.occurredAt)
        return calendar.isDate(weekEnding(containing: occurredAt, calendar: calendar), inSameDayAs: entry.weekEnding)
            ? occurredAt
            : calendar.startOfDay(for: entry.weekEnding)
    }

    static func age(
        from birthDate: Date?,
        at date: Date,
        calendar: Calendar = .current
    ) -> Int? {
        guard let birthDate else { return nil }
        return calendar.dateComponents(
            [.year],
            from: calendar.startOfDay(for: birthDate),
            to: calendar.startOfDay(for: date)
        ).year
    }

    static func startingPoints(
        for member: FamilyMember,
        weekEnding: Date,
        calendar: Calendar = .current
    ) -> Int {
        startingPoints(
            forBirthDate: member.birthDate,
            role: member.role,
            weekEnding: weekEnding,
            calendar: calendar
        )
    }

    static func startingPoints(
        forBirthDate birthDate: Date?,
        role: MemberRole,
        weekEnding: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard role == .child,
              let age = age(from: birthDate, at: weekEnding, calendar: calendar) else {
            return 0
        }
        return max(0, age * 100)
    }

    static func approvedPoints(
        for memberID: UUID,
        weekEnding: Date,
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> Int {
        entries
            .filter {
                $0.memberID == memberID &&
                $0.status == .approved &&
                calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
            }
            .reduce(0) { $0 + $1.points }
    }

    static func pendingPointTotals(
        for memberID: UUID,
        weekEnding: Date,
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> PendingPointTotals {
        let pendingEntries = entries.filter {
            $0.memberID == memberID &&
            $0.status == .pending &&
            calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
        }
        return PendingPointTotals(
            count: pendingEntries.count,
            earned: pendingEntries.reduce(0) { $0 + max(0, $1.points) },
            lost: pendingEntries.reduce(0) { $0 + abs(min(0, $1.points)) }
        )
    }

    static func pendingEntriesForReview(
        weekEnding: Date,
        memberIDs: Set<UUID>,
        entries: [LedgerEntry],
        matchingEntryIDs: Set<UUID>? = nil,
        calendar: Calendar = .current
    ) -> [LedgerEntry] {
        entries.filter {
            memberIDs.contains($0.memberID) &&
            $0.status == .pending &&
            calendar.isDate($0.weekEnding, inSameDayAs: weekEnding) &&
            (matchingEntryIDs?.contains($0.id) ?? true)
        }
    }

    static func copyableEntries(
        weekEnding: Date,
        memberIDs: Set<UUID>,
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> [LedgerEntry] {
        entries
            .filter {
                memberIDs.contains($0.memberID) &&
                $0.status == .approved &&
                ($0.kind == .reward || $0.kind == .penalty) &&
                calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
            }
            .sorted {
                let lhsDate = occurrenceDate(for: $0, calendar: calendar)
                let rhsDate = occurrenceDate(for: $1, calendar: calendar)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                if $0.memberID != $1.memberID { return $0.memberID.uuidString < $1.memberID.uuidString }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    static func duplicateEntries(
        _ sourceEntries: [LedgerEntry],
        toWeekEnding targetWeekEnding: Date,
        submittedBy: String,
        status: ApprovalStatus = .approved,
        calendar: Calendar = .current
    ) -> [LedgerEntry] {
        let targetDatesByWeekday = Dictionary(
            uniqueKeysWithValues: dates(inWeekEnding: targetWeekEnding, calendar: calendar).map {
                (calendar.component(.weekday, from: $0), $0)
            }
        )
        return sourceEntries.map { source in
            let sourceDate = occurrenceDate(for: source, calendar: calendar)
            let weekday = calendar.component(.weekday, from: sourceDate)
            let targetDate = targetDatesByWeekday[weekday]!
            return LedgerEntry(
                memberID: source.memberID,
                ruleID: source.ruleID,
                occurredAt: targetDate,
                weekEnding: calendar.startOfDay(for: targetWeekEnding),
                title: source.title,
                notes: source.notes,
                points: source.points,
                kind: source.kind,
                status: status,
                submittedBy: submittedBy,
                reviewedBy: status == .approved ? submittedBy : nil,
                reviewedAt: status == .approved ? .now : nil,
                quantity: source.quantity,
                measurementUnit: RuleMeasurementUnit(rawValue: source.measurementUnitRawValue) ?? .occurrence,
                riderTitle: source.riderTitle
            )
        }
    }

    @discardableResult
    static func applyReview(
        to entries: [LedgerEntry],
        status: ApprovalStatus,
        reviewedBy: String,
        reviewedAt: Date = .now
    ) -> Int {
        var reviewedCount = 0
        for entry in entries where entry.status == .pending {
            entry.status = status
            entry.reviewedBy = reviewedBy
            entry.reviewedAt = reviewedAt
            reviewedCount += 1
        }
        return reviewedCount
    }

    static func ledgerSummaries(
        weekEnding: Date,
        memberIDs: Set<UUID>,
        entries: [LedgerEntry],
        rules: [RuleTemplate],
        calendar: Calendar = .current
    ) -> [LedgerSummary] {
        struct Key: Hashable {
            let memberID: UUID
            let ruleID: UUID?
            let title: String
            let kind: EntryKind
            let occurredAt: Date
        }

        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let eligibleEntries = entries.filter {
            memberIDs.contains($0.memberID)
        }
        func displayKind(for entry: LedgerEntry) -> EntryKind {
            let rule = entry.ruleID.flatMap { rulesByID[$0] }
            return if let rule {
                switch rule.catalog {
                case .incentives: .reward
                case .disincentives: .penalty
                case .tradingPost: .purchase
                }
            } else {
                entry.kind == .adjustment ? (entry.points < 0 ? .penalty : .reward) : entry.kind
            }
        }

        let currentWeekEntries = eligibleEntries.filter {
            calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
        }
        let grouped = Dictionary(grouping: currentWeekEntries) {
            return Key(
                memberID: $0.memberID,
                ruleID: $0.ruleID,
                title: $0.title,
                kind: displayKind(for: $0),
                occurredAt: occurrenceDate(for: $0, calendar: calendar)
            )
        }

        return grouped.map { key, currentEntries in
            let matchingEntries = eligibleEntries.filter {
                $0.memberID == key.memberID &&
                $0.ruleID == key.ruleID &&
                $0.title == key.title &&
                displayKind(for: $0) == key.kind
            }

            let approvedEntries = matchingEntries.filter { $0.status == .approved }
            let entriesByWeek = Dictionary(grouping: approvedEntries) {
                calendar.startOfDay(for: $0.weekEnding)
            }
            let weeklyCounts = entriesByWeek.values.map(\.count)
            let weeklyTotals = entriesByWeek.values.map { weekEntries in
                weekEntries.reduce(0) { $0 + $1.points }
            }
            let rule = key.ruleID.flatMap { rulesByID[$0] }
            let activeWeeklyEntries = matchingEntries.filter {
                $0.status != .rejected && calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
            }
            let approvedCurrentEntries = currentEntries.filter { $0.status == .approved }
            let pendingCurrentEntries = currentEntries.filter { $0.status == .pending }
            let rejectedCurrentEntries = currentEntries.filter { $0.status == .rejected }
            let currentQuantity = activeWeeklyEntries.reduce(0.0) { $0 + max(0, $1.quantity) }
            let recordPoints = key.kind == .penalty
                ? (weeklyTotals.min() ?? 0)
                : (weeklyTotals.max() ?? 0)

            return LedgerSummary(
                memberID: key.memberID,
                ruleID: key.ruleID,
                title: key.title,
                iconName: rule?.iconName ?? defaultLedgerIcon(for: key.kind),
                kind: key.kind,
                occurredAt: key.occurredAt,
                submittedBy: Array(Set(currentEntries.map(\.submittedBy).filter { !$0.isEmpty }))
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .joined(separator: ", "),
                weeklyCount: activeWeeklyEntries.count,
                recordWeeklyCount: weeklyCounts.max() ?? 0,
                weeklyPoints: activeWeeklyEntries.reduce(0) { $0 + $1.points },
                recordWeeklyPoints: recordPoints,
                nextPoints: rule?.incrementalPoints(existingQuantity: currentQuantity),
                approvedCount: approvedCurrentEntries.count,
                approvedPoints: approvedCurrentEntries.reduce(0) { $0 + $1.points },
                pendingCount: pendingCurrentEntries.count,
                pendingPoints: pendingCurrentEntries.reduce(0) { $0 + $1.points },
                rejectedCount: rejectedCurrentEntries.count,
                entryIDs: currentEntries.map(\.id),
                pendingEntryIDs: pendingCurrentEntries.map(\.id)
            )
        }
        .sorted {
            if $0.memberID != $1.memberID { return $0.memberID.uuidString < $1.memberID.uuidString }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func sortLedgerSummaries(
        _ summaries: [LedgerSummary],
        by descriptors: [LedgerSortDescriptor],
        memberNames: [UUID: String]
    ) -> [LedgerSummary] {
        let descriptors = descriptors.isEmpty ? defaultLedgerSort : descriptors
        return summaries.sorted { lhs, rhs in
            for descriptor in descriptors {
                let comparison = compare(
                    lhs,
                    rhs,
                    column: descriptor.column,
                    memberNames: memberNames
                )
                guard comparison != .orderedSame else { continue }
                return descriptor.ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            return lhs.id < rhs.id
        }
    }

    private static func compare(
        _ lhs: LedgerSummary,
        _ rhs: LedgerSummary,
        column: LedgerSortColumn,
        memberNames: [UUID: String]
    ) -> ComparisonResult {
        func compareStrings(_ first: String, _ second: String) -> ComparisonResult {
            first.localizedCaseInsensitiveCompare(second)
        }
        func compareInts(_ first: Int, _ second: Int) -> ComparisonResult {
            first == second ? .orderedSame : (first < second ? .orderedAscending : .orderedDescending)
        }
        switch column {
        case .type: return compareStrings(lhs.kind.rawValue, rhs.kind.rawValue)
        case .item: return compareStrings(lhs.title, rhs.title)
        case .status: return compareInts(ledgerStatusRank(lhs), ledgerStatusRank(rhs))
        case .person: return compareStrings(memberNames[lhs.memberID] ?? "", memberNames[rhs.memberID] ?? "")
        case .day: return lhs.occurredAt.compare(rhs.occurredAt)
        case .recordedBy: return compareStrings(lhs.submittedBy, rhs.submittedBy)
        case .count: return compareInts(lhs.weeklyCount, rhs.weeklyCount)
        case .recordCount: return compareInts(lhs.recordWeeklyCount, rhs.recordWeeklyCount)
        case .points: return compareInts(lhs.weeklyPoints, rhs.weeklyPoints)
        case .recordPoints: return compareInts(lhs.recordWeeklyPoints, rhs.recordWeeklyPoints)
        case .next: return compareInts(lhs.nextPoints ?? Int.min, rhs.nextPoints ?? Int.min)
        }
    }

    private static func ledgerStatusRank(_ summary: LedgerSummary) -> Int {
        if summary.pendingCount > 0 { return 0 }
        if summary.approvedCount > 0 { return 1 }
        return 2
    }

    private static func defaultLedgerIcon(for kind: EntryKind) -> String {
        switch kind {
        case .reward: "party.popper.fill"
        case .penalty: "cloud.rain.fill"
        case .purchase: "gift.fill"
        case .adjustment: "plusminus.circle.fill"
        }
    }

    static func parentPenaltyPot(
        weekEnding: Date,
        members: [FamilyMember],
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> Int {
        let parentIDs = Set(
            members
                .filter { $0.isActive && $0.role == .parent }
                .map(\.id)
        )

        let parentTotal = entries
            .filter {
                parentIDs.contains($0.memberID) &&
                $0.status == .approved &&
                $0.points < 0 &&
                calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
            }
            .reduce(0) { $0 + $1.points }

        return abs(parentTotal)
    }

    static func parentPotShares(
        weekEnding: Date,
        members: [FamilyMember],
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> [UUID: Int] {
        let children = members
            .filter { $0.isActive && $0.role == .child }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !children.isEmpty else { return [:] }

        let pot = parentPenaltyPot(
            weekEnding: weekEnding,
            members: members,
            entries: entries,
            calendar: calendar
        )
        let baseShare = pot / children.count
        let remainder = pot % children.count

        return Dictionary(
            uniqueKeysWithValues: children.enumerated().map { index, child in
                (child.id, baseShare + (index < remainder ? 1 : 0))
            }
        )
    }

    static func debtCarriedIn(
        childID: UUID,
        weekEnding: Date,
        settlements: [WeeklySettlement],
        calendar: Calendar = .current
    ) -> Int {
        let previous = previousWeekEnding(before: weekEnding, calendar: calendar)
        return settlements.first {
            $0.childID == childID &&
            calendar.isDate($0.weekEnding, inSameDayAs: previous)
        }?.debtCarriedOut ?? 0
    }

    static func minimumMissDeductions(
        for child: FamilyMember,
        weekEnding: Date,
        rules: [RuleTemplate],
        entries: [LedgerEntry],
        calendar: Calendar = .current
    ) -> [MinimumMissDeduction] {
        rules
            .filter {
                $0.familyID == child.familyID &&
                $0.isEnabled &&
                $0.kind == .reward &&
                $0.defaultPoints > 0 &&
                $0.minimumTarget != nil &&
                $0.deductStartingPointsWhenMinimumMissed
            }
            .compactMap { rule in
                let matchingEntries = entries.filter {
                    $0.memberID == child.id &&
                    $0.ruleID == rule.id &&
                    $0.status == .approved
                }

                let periodEntries: [LedgerEntry]
                switch rule.minimumPeriod {
                case .weekly:
                    periodEntries = matchingEntries.filter {
                        calendar.isDate($0.weekEnding, inSameDayAs: weekEnding)
                    }
                case .monthly:
                    guard let month = monthClosing(inWeekEnding: weekEnding, calendar: calendar) else {
                        return nil
                    }
                    periodEntries = matchingEntries.filter { month.contains($0.occurredAt) }
                }

                let completed = periodEntries.reduce(0.0) { $0 + max(0, $1.quantity) }
                guard rule.awardCount(for: completed) < rule.firstAwardNumber else { return nil }

                return MinimumMissDeduction(
                    ruleID: rule.id,
                    title: rule.title,
                    period: rule.minimumPeriod,
                    completedQuantity: completed,
                    requiredQuantity: Double(rule.firstAwardNumber) * max(1, rule.frequencyValue),
                    points: abs(rule.defaultPoints)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func monthClosing(
        inWeekEnding weekEnding: Date,
        calendar: Calendar
    ) -> DateInterval? {
        let end = calendar.startOfDay(for: weekEnding)
        guard let start = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            if calendar.component(.month, from: day) != calendar.component(.month, from: nextDay) {
                return calendar.dateInterval(of: .month, for: day)
            }
        }
        return nil
    }



    static func settlementDrafts(
        weekEnding: Date,
        members: [FamilyMember],
        entries: [LedgerEntry],
        settlements: [WeeklySettlement],

        rules: [RuleTemplate] = [],
        calendar: Calendar = .current
    ) -> [SettlementDraft] {
        let shares = parentPotShares(
            weekEnding: weekEnding,
            members: members,
            entries: entries,
            calendar: calendar
        )

        return members
            .filter { $0.isActive && $0.role == .child }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { child in
                let starting = startingPoints(
                    for: child,
                    weekEnding: weekEnding,
                    calendar: calendar
                )
                let debt = debtCarriedIn(
                    childID: child.id,
                    weekEnding: weekEnding,
                    settlements: settlements,
                    calendar: calendar
                )
                let entryPoints = approvedPoints(
                    for: child.id,
                    weekEnding: weekEnding,
                    entries: entries,
                    calendar: calendar
                )
                let parentShare = shares[child.id] ?? 0

                let minimumDeductions = minimumMissDeductions(
                    for: child,
                    weekEnding: weekEnding,
                    rules: rules,
                    entries: entries,
                    calendar: calendar
                )
                let final = starting + debt + entryPoints + parentShare
                let payablePoints = max(0, final)

                return SettlementDraft(
                    child: child,
                    weekEnding: weekEnding,
                    startingPoints: starting,
                    debtCarriedIn: debt,
                    approvedEntryPoints: entryPoints,
                    parentPotShare: parentShare,

                    minimumMissDeductions: minimumDeductions,
                    finalPoints: final,
                    cashAmount: Decimal(payablePoints) / 100,
                    debtCarriedOut: min(0, final)
                )
            }
    }
}

