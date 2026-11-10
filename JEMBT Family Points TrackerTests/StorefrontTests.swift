import XCTest
@testable import JEMBT_Family_Points_Tracker

final class StorefrontTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testStoreNameUsesTrimmedFamilyNameAndFallback() {
        XCTAssertEqual(StorefrontEngine.storeName(for: "  Montell's Reward Mart  "), "Montell's Reward Mart")
        XCTAssertEqual(StorefrontEngine.storeName(for: ""), "Family Reward Mart")
        XCTAssertEqual(StorefrontEngine.storeName(for: "   "), "Family Reward Mart")
        XCTAssertEqual(StorefrontEngine.storeName(for: nil), "Family Reward Mart")
    }

    func testWeeklyInventoryCountsApprovedPurchasesAcrossChildren() {
        let rule = makeRule(limit: 2, period: .weekly)
        let saturday = date(2026, 11, 7)
        let purchases = [
            purchase(rule: rule, occurredAt: date(2026, 11, 2), weekEnding: saturday, status: .approved),
            purchase(rule: rule, occurredAt: date(2026, 11, 6), weekEnding: saturday, status: .approved),
            purchase(rule: rule, occurredAt: date(2026, 11, 5), weekEnding: saturday, status: .rejected)
        ]

        XCTAssertEqual(
            StorefrontEngine.remainingQuantity(for: rule, entries: purchases, at: date(2026, 11, 6), calendar: calendar),
            0
        )
        XCTAssertEqual(
            StorefrontEngine.remainingQuantity(for: rule, entries: purchases, at: date(2026, 11, 8), calendar: calendar),
            2
        )
    }

    func testDailyInventoryResetsAtMidnight() {
        let rule = makeRule(limit: 1, period: .daily)
        let purchase = purchase(
            rule: rule,
            occurredAt: date(2026, 11, 6),
            weekEnding: date(2026, 11, 7),
            status: .approved
        )

        XCTAssertEqual(
            StorefrontEngine.remainingQuantity(for: rule, entries: [purchase], at: date(2026, 11, 6), calendar: calendar),
            0
        )
        XCTAssertEqual(
            StorefrontEngine.remainingQuantity(for: rule, entries: [purchase], at: date(2026, 11, 7), calendar: calendar),
            1
        )
    }

    func testTotalInventoryNeverResetsAndNeverBecomesNegative() {
        let rule = makeRule(limit: 1, period: .total)
        let purchases = [
            purchase(rule: rule, occurredAt: date(2025, 1, 1), weekEnding: date(2025, 1, 4), status: .approved),
            purchase(rule: rule, occurredAt: date(2026, 11, 6), weekEnding: date(2026, 11, 7), status: .approved)
        ]

        XCTAssertEqual(
            StorefrontEngine.remainingQuantity(for: rule, entries: purchases, at: date(2026, 11, 8), calendar: calendar),
            0
        )
    }

    func testUnlimitedInventoryReturnsNil() {
        let rule = makeRule(limit: nil, period: .weekly)
        XCTAssertNil(StorefrontEngine.remainingQuantity(for: rule, entries: []))
    }

    func testAffordabilityIncludesExactAndFreePrices() {
        let reward = makeRule(price: 300)
        let freeReward = makeRule(price: 0)

        XCTAssertFalse(StorefrontEngine.canAfford(reward, balance: 299))
        XCTAssertTrue(StorefrontEngine.canAfford(reward, balance: 300))
        XCTAssertTrue(StorefrontEngine.canAfford(freeReward, balance: 0))
    }

    func testParentSessionCannotUseChildStorefront() {
        XCTAssertFalse(
            StorefrontEngine.canUseChildStorefront(
                memberRole: .parent,
                membershipRole: .parent
            )
        )
    }

    func testParentMembershipCannotUseChildStorefrontThroughMismatchedProfile() {
        XCTAssertFalse(
            StorefrontEngine.canUseChildStorefront(
                memberRole: .child,
                membershipRole: .parent
            )
        )
    }

    func testChildStorefrontRequiresMatchingChildProfileAndMembership() {
        XCTAssertTrue(
            StorefrontEngine.canUseChildStorefront(
                memberRole: .child,
                membershipRole: .child
            )
        )
        XCTAssertFalse(
            StorefrontEngine.canUseChildStorefront(
                memberRole: .parent,
                membershipRole: .child
            )
        )
    }

    private func makeRule(
        price: Int = 100,
        limit: Int? = nil,
        period: StoreInventoryPeriod = .weekly
    ) -> RuleTemplate {
        RuleTemplate(
            title: "Reward",
            category: .rewardStore,
            kind: .purchase,
            defaultPoints: -abs(price),
            storeInventoryLimit: limit,
            storeInventoryPeriod: period
        )
    }

    private func purchase(
        rule: RuleTemplate,
        occurredAt: Date,
        weekEnding: Date,
        status: ApprovalStatus
    ) -> LedgerEntry {
        LedgerEntry(
            memberID: UUID(),
            ruleID: rule.id,
            occurredAt: occurredAt,
            weekEnding: weekEnding,
            title: rule.title,
            points: rule.defaultPoints,
            kind: .purchase,
            status: status,
            submittedBy: "Child"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
