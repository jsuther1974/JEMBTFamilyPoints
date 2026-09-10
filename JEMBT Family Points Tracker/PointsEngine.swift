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
        guard let birthDate = member.birthDate else { return 0 }
        return calendar.dateComponents(
            [.year],
            from: calendar.startOfDay(for: birthDate),
            to: calendar.startOfDay(for: weekEnding)
        ).year ?? 0
    }

    static func startingPoints(
        for member: FamilyMember,
        weekEnding: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard member.role == .child else { return 0 }
        return max(0, age(of: member, at: weekEnding, calendar: calendar) * 100)
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

    static func settlementDrafts(
        weekEnding: Date,
        members: [FamilyMember],
        entries: [LedgerEntry],
        settlements: [WeeklySettlement],
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
                let final = starting + debt + entryPoints + parentShare
                let payablePoints = max(0, final)

                return SettlementDraft(
                    child: child,
                    weekEnding: weekEnding,
                    startingPoints: starting,
                    debtCarriedIn: debt,
                    approvedEntryPoints: entryPoints,
                    parentPotShare: parentShare,
                    finalPoints: final,
                    cashAmount: Decimal(payablePoints) / 100,
                    debtCarriedOut: min(0, final)
                )
            }
    }
}

