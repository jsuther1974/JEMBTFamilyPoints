import Foundation

enum PointsEngine {
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

