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

    func testCartTotalIncludesQuantitiesAcrossItems() {
        let movie = makeRule(price: 300)
        let snack = makeRule(price: 75)

        XCTAssertEqual(
            StorefrontEngine.cartTotal(
                quantities: [movie.id: 2, snack.id: 3],
                items: [movie, snack]
            ),
            825
        )
    }

    func testCheckoutRevalidatesAgeInventoryAndTotalBalance() {
        let familyID = UUID()
        let child = FamilyMember(
            familyID: familyID,
            name: "Child",
            birthDate: date(2018, 1, 1),
            role: .child
        )
        let available = RuleTemplate(
            familyID: familyID,
            title: "Available",
            category: .rewardStore,
            kind: .purchase,
            defaultPoints: -300,
            storeInventoryLimit: 2,
            storeInventoryPeriod: .weekly,
            minimumEligibleAge: 8,
            maximumEligibleAge: 12
        )
        let teenOnly = RuleTemplate(
            familyID: familyID,
            title: "Teen only",
            category: .rewardStore,
            kind: .purchase,
            defaultPoints: -100,
            minimumEligibleAge: 13,
            maximumEligibleAge: 17
        )
        let now = date(2026, 11, 6)
        let existingPurchase = purchase(
            rule: available,
            occurredAt: now,
            weekEnding: date(2026, 11, 7),
            status: .approved
        )

        XCTAssertNil(StorefrontEngine.checkoutError(
            quantities: [available.id: 1],
            items: [available],
            child: child,
            familyID: familyID,
            balance: 300,
            entries: [existingPurchase],
            at: now,
            calendar: calendar
        ))
        XCTAssertEqual(StorefrontEngine.checkoutError(
            quantities: [available.id: 2],
            items: [available],
            child: child,
            familyID: familyID,
            balance: 1_000,
            entries: [existingPurchase],
            at: now,
            calendar: calendar
        ), "Only 1 of Available remain.")
        XCTAssertEqual(StorefrontEngine.checkoutError(
            quantities: [teenOnly.id: 1],
            items: [teenOnly],
            child: child,
            familyID: familyID,
            balance: 1_000,
            entries: [],
            at: now,
            calendar: calendar
        ), "Teen only is not available for your age.")
        XCTAssertEqual(StorefrontEngine.checkoutError(
            quantities: [available.id: 1],
            items: [available],
            child: child,
            familyID: familyID,
            balance: 299,
            entries: [],
            at: now,
            calendar: calendar
        ), "You no longer have enough points for everything in your cart.")
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
