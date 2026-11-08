import XCTest
@testable import JEMBT_Family_Points_Tracker

final class PointsEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testAgeUsesSaturdayAtEndOfWeek() {
        let child = FamilyMember(
            name: "Child",
            birthDate: date(2018, 12, 30),
            role: .child
        )

        XCTAssertEqual(
            PointsEngine.startingPoints(
                for: child,
                weekEnding: date(2026, 12, 26),
                calendar: calendar
            ),
            700
        )
        XCTAssertEqual(
            PointsEngine.startingPoints(
                for: child,
                weekEnding: date(2027, 1, 2),
                calendar: calendar
            ),
            800
        )
    }

    func testParentPenaltyPotIsDistributedToChildren() {
        let childOne = FamilyMember(
            name: "One",
            birthDate: date(2016, 1, 1),
            role: .child
        )
        let childTwo = FamilyMember(
            name: "Two",
            birthDate: date(2018, 1, 1),
            role: .child
        )
        let parent = FamilyMember(
            name: "Parent",
            birthDate: date(1980, 1, 1),
            role: .parent
        )
        let weekEnding = date(2026, 9, 12)
        let entry = LedgerEntry(
            memberID: parent.id,
            weekEnding: weekEnding,
            title: "Swearing",
            points: -100,
            kind: .penalty,
            status: .approved,
            submittedBy: "Parent"
        )

        let shares = PointsEngine.parentPotShares(
            weekEnding: weekEnding,
            members: [childOne, childTwo, parent],
            entries: [entry],
            calendar: calendar
        )

        XCTAssertEqual(shares[childOne.id], 50)
        XCTAssertEqual(shares[childTwo.id], 50)
    }

    func testNegativeBalanceCarriesIntoFollowingWeek() {
        let child = FamilyMember(
            name: "Child",
            birthDate: date(2018, 1, 1),
            role: .child
        )
        let firstWeek = date(2026, 9, 5)
        let settlement = WeeklySettlement(
            childID: child.id,
            weekEnding: firstWeek,
            startingPoints: 800,
            debtCarriedIn: 0,
            approvedEntryPoints: -1_000,
            parentPotShare: 0,
            finalPoints: -200,
            cashAmount: 0,
            debtCarriedOut: -200,
            confirmedBy: "Parent"
        )

        let drafts = PointsEngine.settlementDrafts(
            weekEnding: date(2026, 9, 12),
            members: [child],
            entries: [],
            settlements: [settlement],
            calendar: calendar
        )

        XCTAssertEqual(drafts.first?.debtCarriedIn, -200)
        XCTAssertEqual(drafts.first?.finalPoints, 600)
        XCTAssertEqual(drafts.first?.cashAmount, Decimal(6))
    }

    func testUnsavedChildUsesSameStartingPointsRuleAsSavedMember() {
        let birthDate = date(2016, 1, 1)
        let weekEnding = date(2026, 11, 7)
        let child = FamilyMember(name: "Child", birthDate: birthDate, role: .child)

        XCTAssertEqual(
            PointsEngine.startingPoints(
                forBirthDate: birthDate,
                role: .child,
                weekEnding: weekEnding,
                calendar: calendar
            ),
            PointsEngine.startingPoints(for: child, weekEnding: weekEnding, calendar: calendar)
        )
        XCTAssertEqual(
            PointsEngine.startingPoints(
                forBirthDate: birthDate,
                role: .caregiver,
                weekEnding: weekEnding,
                calendar: calendar
            ),
            0
        )
    }

    func testWeeklyMinimumMissIsProposedOnlyWhenRuleOptsIn() {
        let familyID = UUID()
        let child = FamilyMember(
            familyID: familyID,
            name: "Child",
            birthDate: date(2018, 1, 1),
            role: .child
        )
        let optedIn = minimumRule(
            familyID: familyID,
            title: "Homework",
            points: 100,
            minimum: 4,
            period: .weekly,
            deductWhenMissed: true
        )
        let optedOut = minimumRule(
            familyID: familyID,
            title: "Make bed",
            points: 75,
            minimum: 4,
            period: .weekly,
            deductWhenMissed: false
        )
        let weekEnding = date(2026, 9, 12)
        let entry = LedgerEntry(
            memberID: child.id,
            ruleID: optedIn.id,
            occurredAt: date(2026, 9, 10),
            weekEnding: weekEnding,
            title: optedIn.title,
            points: 0,
            kind: .reward,
            status: .approved,
            submittedBy: "Parent",
            quantity: 3
        )

        let deductions = PointsEngine.minimumMissDeductions(
            for: child,
            weekEnding: weekEnding,
            rules: [optedIn, optedOut],
            entries: [entry],
            calendar: calendar
        )

        XCTAssertEqual(deductions.count, 1)
        XCTAssertEqual(deductions.first?.ruleID, optedIn.id)
        XCTAssertEqual(deductions.first?.completedQuantity, 3)
        XCTAssertEqual(deductions.first?.requiredQuantity, 4)
        XCTAssertEqual(deductions.first?.points, 100)
    }

    func testWeeklyMinimumMetDoesNotProposeDeduction() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let rule = minimumRule(
            familyID: familyID,
            title: "Homework",
            points: 100,
            minimum: 4,
            period: .weekly,
            deductWhenMissed: true
        )
        let weekEnding = date(2026, 9, 12)
        let entries = [2.0, 2.0].map { quantity in
            LedgerEntry(
                memberID: child.id,
                ruleID: rule.id,
                weekEnding: weekEnding,
                title: rule.title,
                points: 0,
                kind: .reward,
                status: .approved,
                submittedBy: "Parent",
                quantity: quantity
            )
        }

        XCTAssertTrue(
            PointsEngine.minimumMissDeductions(
                for: child,
                weekEnding: weekEnding,
                rules: [rule],
                entries: entries,
                calendar: calendar
            ).isEmpty
        )
    }

    func testMonthlyMinimumIsProposedOnlyInWeekContainingMonthEnd() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let rule = minimumRule(
            familyID: familyID,
            title: "Clean bedroom",
            points: 150,
            minimum: 2,
            period: .monthly,
            deductWhenMissed: true
        )
        let octoberEntry = LedgerEntry(
            memberID: child.id,
            ruleID: rule.id,
            occurredAt: date(2026, 10, 15),
            weekEnding: date(2026, 10, 17),
            title: rule.title,
            points: 0,
            kind: .reward,
            status: .approved,
            submittedBy: "Parent"
        )

        let closingWeek = PointsEngine.minimumMissDeductions(
            for: child,
            weekEnding: date(2026, 10, 31),
            rules: [rule],
            entries: [octoberEntry],
            calendar: calendar
        )
        let followingWeek = PointsEngine.minimumMissDeductions(
            for: child,
            weekEnding: date(2026, 11, 7),
            rules: [rule],
            entries: [octoberEntry],
            calendar: calendar
        )

        XCTAssertEqual(closingWeek.first?.completedQuantity, 1)
        XCTAssertEqual(closingWeek.first?.points, 150)
        XCTAssertTrue(followingWeek.isEmpty)
    }

    func testSettlementAppliesOnlyParentSelectedMinimumDeductions() {
        let familyID = UUID()
        let child = FamilyMember(
            familyID: familyID,
            name: "Child",
            birthDate: date(2018, 1, 1),
            role: .child
        )
        let homework = minimumRule(
            familyID: familyID,
            title: "Homework",
            points: 100,
            minimum: 4,
            period: .weekly,
            deductWhenMissed: true
        )
        let chores = minimumRule(
            familyID: familyID,
            title: "Chores",
            points: 75,
            minimum: 3,
            period: .weekly,
            deductWhenMissed: true
        )

        let draft = PointsEngine.settlementDrafts(
            weekEnding: date(2026, 9, 12),
            members: [child],
            entries: [],
            settlements: [],
            rules: [homework, chores],
            calendar: calendar
        ).first!

        XCTAssertEqual(draft.finalPoints, 800)
        XCTAssertEqual(draft.minimumMissDeductions.count, 2)
        XCTAssertEqual(draft.deductionPoints(applying: [homework.id]), 100)
        XCTAssertEqual(draft.finalPoints(applying: [homework.id]), 700)
        XCTAssertEqual(draft.cashAmount(applying: [homework.id]), Decimal(7))
        XCTAssertEqual(draft.finalPoints(applying: [homework.id, chores.id]), 625)
    }

    func testMinimumDeductionsIgnoreIneligibleRulesAndOtherFamilies() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let eligible = minimumRule(
            familyID: familyID,
            title: "Eligible",
            points: 100,
            minimum: 2,
            period: .weekly,
            deductWhenMissed: true
        )
        let disabled = minimumRule(
            familyID: familyID,
            title: "Disabled",
            points: 100,
            minimum: 2,
            period: .weekly,
            deductWhenMissed: true
        )
        disabled.isEnabled = false
        let penalty = RuleTemplate(
            familyID: familyID,
            title: "Penalty",
            category: .behavior,
            kind: .penalty,
            defaultPoints: -100,
            minimumTarget: 2,
            deductStartingPointsWhenMinimumMissed: true
        )
        let otherFamily = minimumRule(
            familyID: UUID(),
            title: "Other family",
            points: 100,
            minimum: 2,
            period: .weekly,
            deductWhenMissed: true
        )

        let deductions = PointsEngine.minimumMissDeductions(
            for: child,
            weekEnding: date(2026, 9, 12),
            rules: [disabled, otherFamily, penalty, eligible],
            entries: [],
            calendar: calendar
        )

        XCTAssertEqual(deductions.map(\.ruleID), [eligible.id])
    }

    func testOnlyApprovedEntriesCountTowardMinimum() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let rule = minimumRule(
            familyID: familyID,
            title: "Reading",
            points: 100,
            minimum: 2,
            period: .weekly,
            deductWhenMissed: true
        )
        let weekEnding = date(2026, 9, 12)
        let pendingEntry = LedgerEntry(
            memberID: child.id,
            ruleID: rule.id,
            weekEnding: weekEnding,
            title: rule.title,
            points: 100,
            kind: .reward,
            status: .pending,
            submittedBy: "Child",
            quantity: 2
        )

        let deductions = PointsEngine.minimumMissDeductions(
            for: child,
            weekEnding: weekEnding,
            rules: [rule],
            entries: [pendingEntry],
            calendar: calendar
        )

        XCTAssertEqual(deductions.first?.completedQuantity, 0)
    }

    func testMinimumRespectsConfiguredAwardInterval() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let rule = minimumRule(
            familyID: familyID,
            title: "Practice",
            points: 100,
            minimum: 4,
            period: .weekly,
            deductWhenMissed: true
        )
        rule.frequencyValue = 2
        let weekEnding = date(2026, 9, 12)

        func deductions(for quantity: Double) -> [MinimumMissDeduction] {
            let entry = LedgerEntry(
                memberID: child.id,
                ruleID: rule.id,
                weekEnding: weekEnding,
                title: rule.title,
                points: 0,
                kind: .reward,
                status: .approved,
                submittedBy: "Parent",
                quantity: quantity
            )
            return PointsEngine.minimumMissDeductions(
                for: child,
                weekEnding: weekEnding,
                rules: [rule],
                entries: [entry],
                calendar: calendar
            )
        }

        XCTAssertEqual(deductions(for: 7).first?.requiredQuantity, 8)
        XCTAssertTrue(deductions(for: 8).isEmpty)
    }

    func testSelectedDeductionCanCreateDebtAndZeroCashTransfer() {
        let familyID = UUID()
        let child = FamilyMember(
            familyID: familyID,
            name: "Child",
            birthDate: date(2018, 1, 1),
            role: .child
        )
        let rule = minimumRule(
            familyID: familyID,
            title: "Large deduction",
            points: 900,
            minimum: 1,
            period: .weekly,
            deductWhenMissed: true
        )
        let draft = PointsEngine.settlementDrafts(
            weekEnding: date(2026, 9, 12),
            members: [child],
            entries: [],
            settlements: [],
            rules: [rule],
            calendar: calendar
        ).first!

        XCTAssertEqual(draft.finalPoints(applying: [rule.id]), -100)
        XCTAssertEqual(draft.cashAmount(applying: [rule.id]), 0)
        XCTAssertEqual(draft.debtCarriedOut(applying: [rule.id]), -100)
    }

    func testFamilyListRoleOrderIsChildrenParentsThenCaregivers() {
        let members = [
            FamilyMember(name: "Zoe Caregiver", role: .caregiver),
            FamilyMember(name: "Zoe Child", birthDate: date(2016, 1, 1), role: .child),
            FamilyMember(name: "Zoe Parent", role: .parent),
            FamilyMember(name: "Amy Child", birthDate: date(2018, 1, 1), role: .child),
            FamilyMember(name: "Amy Parent", role: .parent)
        ]

        XCTAssertEqual(
            members.sorted(by: FamilyMember.comesBeforeInFamilyList).map(\.name),
            ["Amy Child", "Zoe Child", "Amy Parent", "Zoe Parent", "Zoe Caregiver"]
        )
    }

    func testLedgerSummariesAggregateCurrentWeekAndHistoricalRecords() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let reward = RuleTemplate(
            familyID: familyID,
            title: "Helping",
            category: .household,
            kind: .reward,
            defaultPoints: 100,
            growthEnabled: true,
            growthKind: .fixedPoints,
            growthAmount: 25
        )
        let currentWeek = date(2026, 11, 7)
        let previousWeek = date(2026, 10, 31)
        let entries = [
            ledgerEntry(child: child, rule: reward, week: currentWeek, points: 100, status: .approved),
            ledgerEntry(child: child, rule: reward, week: currentWeek, points: 125, status: .pending),
            ledgerEntry(child: child, rule: reward, week: previousWeek, points: 100, status: .approved),
            ledgerEntry(child: child, rule: reward, week: previousWeek, points: 125, status: .approved),
            ledgerEntry(child: child, rule: reward, week: previousWeek, points: 150, status: .approved)
        ]

        let summary = PointsEngine.ledgerSummaries(
            weekEnding: currentWeek,
            memberIDs: [child.id],
            entries: entries,
            rules: [reward],
            calendar: calendar
        ).first

        XCTAssertEqual(summary?.weeklyCount, 2)
        XCTAssertEqual(summary?.weeklyPoints, 225)
        XCTAssertEqual(summary?.recordWeeklyCount, 3)
        XCTAssertEqual(summary?.recordWeeklyPoints, 375)
        XCTAssertEqual(summary?.nextPoints, 150)
        XCTAssertEqual(summary?.approvedCount, 1)
        XCTAssertEqual(summary?.approvedPoints, 100)
        XCTAssertEqual(summary?.pendingCount, 1)
        XCTAssertEqual(summary?.pendingPoints, 125)
        XCTAssertEqual(summary?.rejectedCount, 0)
        XCTAssertEqual(summary?.pendingEntryIDs, [entries[1].id])
        XCTAssertEqual(summary?.hasPendingEntries, true)
    }

    func testPenaltyLedgerUsesTheAllTimeWeeklyLowAndIgnoresRejectedEntries() {
        let familyID = UUID()
        let parent = FamilyMember(familyID: familyID, name: "Parent", role: .parent)
        let penalty = RuleTemplate(
            familyID: familyID,
            title: "Shouting",
            category: .behavior,
            kind: .penalty,
            defaultPoints: -50,
            growthEnabled: true,
            growthKind: .percentage,
            growthAmount: 100
        )
        let currentWeek = date(2026, 11, 7)
        let entries = [
            ledgerEntry(child: parent, rule: penalty, week: currentWeek, points: -50, status: .approved),
            ledgerEntry(child: parent, rule: penalty, week: currentWeek, points: -100, status: .approved),
            ledgerEntry(child: parent, rule: penalty, week: currentWeek, points: -400, status: .rejected),
            ledgerEntry(child: parent, rule: penalty, week: date(2026, 10, 31), points: -50, status: .approved)
        ]

        let summary = PointsEngine.ledgerSummaries(
            weekEnding: currentWeek,
            memberIDs: [parent.id],
            entries: entries,
            rules: [penalty],
            calendar: calendar
        ).first

        XCTAssertEqual(summary?.weeklyCount, 2)
        XCTAssertEqual(summary?.weeklyPoints, -150)
        XCTAssertEqual(summary?.recordWeeklyPoints, -150)
        XCTAssertEqual(summary?.nextPoints, -200)
        XCTAssertEqual(summary?.approvedCount, 2)
        XCTAssertEqual(summary?.pendingCount, 0)
        XCTAssertEqual(summary?.rejectedCount, 1)
    }

    func testLedgerIncludesPendingRewardShopPurchases() {
        let familyID = UUID()
        let child = FamilyMember(familyID: familyID, name: "Child", role: .child)
        let purchase = RuleTemplate(
            familyID: familyID,
            title: "Movie Night",
            category: .rewardStore,
            kind: .purchase,
            defaultPoints: -500
        )
        let weekEnding = date(2026, 11, 7)
        let entry = LedgerEntry(
            memberID: child.id,
            ruleID: purchase.id,
            weekEnding: weekEnding,
            title: purchase.title,
            points: -500,
            kind: .purchase,
            status: .pending,
            submittedBy: "Child"
        )

        let summary = PointsEngine.ledgerSummaries(
            weekEnding: weekEnding,
            memberIDs: [child.id],
            entries: [entry],
            rules: [purchase],
            calendar: calendar
        ).first

        XCTAssertEqual(summary?.kind, .purchase)
        XCTAssertEqual(summary?.weeklyCount, 1)
        XCTAssertEqual(summary?.weeklyPoints, -500)
        XCTAssertEqual(summary?.pendingCount, 1)
        XCTAssertEqual(summary?.pendingEntryIDs, [entry.id])
    }

    func testLedgerReviewSelectionSupportsOneAggregateOrAllPendingThisWeek() {
        let child = FamilyMember(name: "Child", role: .child)
        let sibling = FamilyMember(name: "Sibling", role: .child)
        let currentWeek = date(2026, 11, 7)
        let selectedPending = LedgerEntry(
            memberID: child.id,
            weekEnding: currentWeek,
            title: "Helping",
            points: 100,
            kind: .reward,
            status: .pending,
            submittedBy: "Child"
        )
        let otherPending = LedgerEntry(
            memberID: sibling.id,
            weekEnding: currentWeek,
            title: "Chores",
            points: 75,
            kind: .reward,
            status: .pending,
            submittedBy: "Sibling"
        )
        let approved = LedgerEntry(
            memberID: child.id,
            weekEnding: currentWeek,
            title: "Approved",
            points: 50,
            kind: .reward,
            status: .approved,
            submittedBy: "Parent"
        )
        let previousWeek = LedgerEntry(
            memberID: child.id,
            weekEnding: date(2026, 10, 31),
            title: "Previous",
            points: 25,
            kind: .reward,
            status: .pending,
            submittedBy: "Child"
        )
        let outsider = LedgerEntry(
            memberID: UUID(),
            weekEnding: currentWeek,
            title: "Other family",
            points: 25,
            kind: .reward,
            status: .pending,
            submittedBy: "Child"
        )
        let entries = [selectedPending, otherPending, approved, previousWeek, outsider]
        let memberIDs = Set([child.id, sibling.id])

        let selected = PointsEngine.pendingEntriesForReview(
            weekEnding: currentWeek,
            memberIDs: memberIDs,
            entries: entries,
            matchingEntryIDs: [selectedPending.id],
            calendar: calendar
        )
        let all = PointsEngine.pendingEntriesForReview(
            weekEnding: currentWeek,
            memberIDs: memberIDs,
            entries: entries,
            calendar: calendar
        )

        XCTAssertEqual(selected.map(\.id), [selectedPending.id])
        XCTAssertEqual(Set(all.map(\.id)), Set([selectedPending.id, otherPending.id]))

        let reviewedAt = date(2026, 11, 6)
        XCTAssertEqual(
            PointsEngine.applyReview(
                to: selected,
                status: .approved,
                reviewedBy: "Parent",
                reviewedAt: reviewedAt
            ),
            1
        )
        XCTAssertEqual(selectedPending.status, .approved)
        XCTAssertEqual(selectedPending.reviewedBy, "Parent")
        XCTAssertEqual(selectedPending.reviewedAt, reviewedAt)
        XCTAssertEqual(otherPending.status, .pending)

        let remaining = PointsEngine.pendingEntriesForReview(
            weekEnding: currentWeek,
            memberIDs: memberIDs,
            entries: entries,
            calendar: calendar
        )
        XCTAssertEqual(PointsEngine.applyReview(to: remaining, status: .rejected, reviewedBy: "Parent"), 1)
        XCTAssertEqual(otherPending.status, .rejected)
        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(previousWeek.status, .pending)
        XCTAssertEqual(outsider.status, .pending)
    }

    func testPendingPointTotalsAreSeparatedByMemberAndWeek() {
        let child = FamilyMember(name: "Child", role: .child)
        let sibling = FamilyMember(name: "Sibling", role: .child)
        let currentWeek = date(2026, 11, 7)
        let entries = [
            LedgerEntry(
                memberID: child.id,
                weekEnding: currentWeek,
                title: "Helping",
                points: 125,
                kind: .reward,
                status: .pending,
                submittedBy: "Child"
            ),
            LedgerEntry(
                memberID: child.id,
                weekEnding: currentWeek,
                title: "Shouting",
                points: -50,
                kind: .penalty,
                status: .pending,
                submittedBy: "Caregiver"
            ),
            LedgerEntry(
                memberID: child.id,
                weekEnding: currentWeek,
                title: "Approved",
                points: 500,
                kind: .reward,
                status: .approved,
                submittedBy: "Parent"
            ),
            LedgerEntry(
                memberID: child.id,
                weekEnding: currentWeek,
                title: "Rejected",
                points: -400,
                kind: .penalty,
                status: .rejected,
                submittedBy: "Parent"
            ),
            LedgerEntry(
                memberID: child.id,
                weekEnding: date(2026, 10, 31),
                title: "Previous week",
                points: 300,
                kind: .reward,
                status: .pending,
                submittedBy: "Child"
            ),
            LedgerEntry(
                memberID: sibling.id,
                weekEnding: currentWeek,
                title: "Sibling entry",
                points: 200,
                kind: .reward,
                status: .pending,
                submittedBy: "Sibling"
            )
        ]

        let totals = PointsEngine.pendingPointTotals(
            for: child.id,
            weekEnding: currentWeek,
            entries: entries,
            calendar: calendar
        )

        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals.earned, 125)
        XCTAssertEqual(totals.lost, 50)
        XCTAssertEqual(totals.net, 75)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func minimumRule(
        familyID: UUID,
        title: String,
        points: Int,
        minimum: Double,
        period: RuleMinimumPeriod,
        deductWhenMissed: Bool
    ) -> RuleTemplate {
        RuleTemplate(
            familyID: familyID,
            title: title,
            category: .household,
            kind: .reward,
            defaultPoints: points,
            minimumTarget: minimum,
            deductStartingPointsWhenMinimumMissed: deductWhenMissed,
            minimumPeriod: period
        )
    }

    private func ledgerEntry(
        child: FamilyMember,
        rule: RuleTemplate,
        week: Date,
        points: Int,
        status: ApprovalStatus
    ) -> LedgerEntry {
        LedgerEntry(
            memberID: child.id,
            ruleID: rule.id,
            weekEnding: week,
            title: rule.title,
            points: points,
            kind: rule.kind,
            status: status,
            submittedBy: "Parent"
        )
    }
}

final class ActivitySubmissionPolicyTests: XCTestCase {
    private var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testBirthdateOverridesProfileRoleForSubmissionApproval() {
        let evaluationDate = date(2026, 11, 5)
        let minorWithParentRole = FamilyMember(
            name: "Minor",
            birthDate: date(2010, 1, 1),
            role: .parent
        )
        let adultWithChildRole = FamilyMember(
            name: "Adult",
            birthDate: date(2000, 1, 1),
            role: .child
        )

        XCTAssertTrue(ActivitySubmissionPolicy.isChildAccountHolder(
            member: minorWithParentRole,
            membershipRole: .parent,
            on: evaluationDate,
            calendar: gregorianUTC
        ))
        XCTAssertFalse(ActivitySubmissionPolicy.isChildAccountHolder(
            member: adultWithChildRole,
            membershipRole: .child,
            on: evaluationDate,
            calendar: gregorianUTC
        ))
    }

    func testSubmissionDetectionChangesOnEighteenthBirthday() {
        let accountHolder = FamilyMember(
            name: "Account Holder",
            birthDate: date(2008, 11, 5),
            role: .child
        )

        XCTAssertTrue(accountHolder.isChildAccountHolder(
            on: date(2026, 11, 4),
            calendar: gregorianUTC
        ))
        XCTAssertFalse(accountHolder.isChildAccountHolder(
            on: date(2026, 11, 5),
            calendar: gregorianUTC
        ))
    }

    func testRoleIsUsedWhenAccountHolderBirthdateIsUnavailable() {
        let child = FamilyMember(name: "Child", role: .child)
        let parent = FamilyMember(name: "Parent", role: .parent)

        XCTAssertTrue(ActivitySubmissionPolicy.isChildAccountHolder(
            member: child,
            membershipRole: .parent
        ))
        XCTAssertFalse(ActivitySubmissionPolicy.isChildAccountHolder(
            member: parent,
            membershipRole: .child
        ))
        XCTAssertTrue(ActivitySubmissionPolicy.isChildAccountHolder(
            member: nil,
            membershipRole: .child
        ))
        XCTAssertFalse(ActivitySubmissionPolicy.isChildAccountHolder(
            member: nil,
            membershipRole: .parent
        ))
    }

    func testCaregiverSubmissionsAreRecommendationsRequiringParentApproval() {
        let caregiver = FamilyMember(
            name: "Caregiver",
            birthDate: date(1980, 1, 1),
            role: .caregiver
        )

        let kind = ActivitySubmissionPolicy.submissionKind(
            member: caregiver,
            membershipRole: .caregiver,
            on: date(2026, 11, 6),
            calendar: gregorianUTC
        )

        XCTAssertEqual(kind, .caregiverRecommendation)
        XCTAssertTrue(kind.requiresParentApproval)
        XCTAssertEqual(kind.submittedBy, "Caregiver")
        XCTAssertFalse(ActivitySubmissionPolicy.isChildAccountHolder(
            member: caregiver,
            membershipRole: .caregiver
        ))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        gregorianUTC.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

final class ContactBirthdayConverterTests: XCTestCase {
    private var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCompleteContactBirthdayIgnoresExtraneousTimeMetadata() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Pacific/Kiritimati")
        components.year = 2014
        components.month = 7
        components.day = 9
        components.hour = 23
        components.minute = 59

        let date = ContactBirthdayConverter.date(from: components)

        XCTAssertNotNil(date)
        XCTAssertEqual(
            gregorianUTC.dateComponents([.year, .month, .day], from: date!),
            DateComponents(year: 2014, month: 7, day: 9)
        )
    }

    func testLeapDayBirthdayIsAccepted() {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2012,
            month: 2,
            day: 29
        )

        XCTAssertNotNil(ContactBirthdayConverter.date(from: components))
    }

    func testBirthdayWithoutYearIsRejected() {
        let components = DateComponents(month: 7, day: 9)

        XCTAssertNil(ContactBirthdayConverter.date(from: components))
    }

    func testInvalidAndFutureBirthdaysAreRejected() {
        let invalid = DateComponents(year: 2014, month: 2, day: 30)
        let nextYear = gregorianUTC.component(.year, from: .now) + 1
        let future = DateComponents(year: nextYear, month: 1, day: 1)

        XCTAssertNil(ContactBirthdayConverter.date(from: invalid))
        XCTAssertNil(ContactBirthdayConverter.date(from: future))
    }

    func testAdultDetectionChangesOnEighteenthBirthday() {
        let birthday = gregorianUTC.date(from: DateComponents(year: 2008, month: 11, day: 2))!
        let dayBeforeTurningEighteen = gregorianUTC.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let eighteenthBirthday = gregorianUTC.date(from: DateComponents(year: 2026, month: 11, day: 2))!

        XCTAssertFalse(ContactBirthdayConverter.isAdult(birthday, on: dayBeforeTurningEighteen, calendar: gregorianUTC))
        XCTAssertTrue(ContactBirthdayConverter.isAdult(birthday, on: eighteenthBirthday, calendar: gregorianUTC))
    }
}
