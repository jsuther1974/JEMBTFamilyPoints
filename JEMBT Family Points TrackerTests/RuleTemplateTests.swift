import XCTest
@testable import JEMBT_Family_Points_Tracker

final class RuleTemplateTests: XCTestCase {
    func testMinimumTargetWithholdsPointsUntilReached() {
        let rule = makeRule(points: 50, minimum: 4)

        XCTAssertEqual(rule.calculatedPoints(quantity: 3), 0)
        XCTAssertEqual(rule.calculatedPoints(quantity: 4), 50)
        XCTAssertEqual(rule.calculatedPoints(quantity: 5), 100)
    }

    func testMaximumCapsBillableUnits() {
        let rule = makeRule(points: 100, maximum: 4)

        XCTAssertEqual(rule.calculatedPoints(quantity: 10), 400)
    }

    func testWarningUnitsDoNotAccruePoints() {
        let rule = makeRule(points: -25, warnings: 1)

        XCTAssertEqual(rule.calculatedPoints(quantity: 1), 0)
        XCTAssertEqual(rule.calculatedPoints(quantity: 3), -50)
    }

    func testPercentageGrowthCompoundsEachAward() {
        let rule = makeRule(points: -100, maximum: 4, growthKind: .percentage, growthAmount: 100)

        XCTAssertEqual(rule.calculatedPoints(quantity: 4), -1_500)
        XCTAssertEqual(rule.calculatedPoints(quantity: 10), -1_500)
    }

    func testFixedGrowthAddsPointsEachAward() {
        let rule = makeRule(points: 100, growthKind: .fixedPoints, growthAmount: 25)

        XCTAssertEqual(rule.calculatedPoints(quantity: 4), 550)
    }

    func testCountFrequencyAwardsEveryConfiguredNumberOfTimes() {
        let rule = makeRule(points: 100, frequencyValue: 2)

        XCTAssertEqual(rule.calculatedPoints(quantity: 1), 0)
        XCTAssertEqual(rule.calculatedPoints(quantity: 5), 200)
    }

    func testTimeFrequencyUsesConfiguredInterval() {
        let rule = makeRule(points: 100, frequencyKind: .time, frequencyValue: 15, timeUnit: .minute)

        XCTAssertEqual(rule.calculatedPoints(quantity: 14), 0)
        XCTAssertEqual(rule.calculatedPoints(quantity: 30), 200)
    }

    func testOnceCountScheduleAwardsOnlyOnce() {
        let rule = makeRule(points: 100, countSchedule: .once)

        XCTAssertEqual(rule.calculatedPoints(quantity: 50), 100)
    }

    func testRiderMultipliesCalculatedTotal() {
        let rule = makeRule(points: -50)

        XCTAssertEqual(rule.calculatedPoints(quantity: 2, riderMultiplier: 4), -400)
    }

    func testIncrementalPointsReturnsOnlyTheNextConfiguredAward() {
        let growingPenalty = makeRule(
            points: -50,
            growthKind: .percentage,
            growthAmount: 100
        )
        let timedReward = makeRule(
            points: 100,
            frequencyKind: .time,
            frequencyValue: 15,
            timeUnit: .minute
        )

        XCTAssertEqual(growingPenalty.incrementalPoints(existingQuantity: 0), -50)
        XCTAssertEqual(growingPenalty.incrementalPoints(existingQuantity: 2), -200)
        XCTAssertEqual(timedReward.singleAwardQuantity, 15)
        XCTAssertEqual(timedReward.incrementalPoints(existingQuantity: 15), 100)
    }

    func testWeeklyParentAssignmentsAdvanceGrowthAndRespectMaximum() {
        let growingReward = makeRule(
            points: 50,
            maximum: 3,
            growthKind: .percentage,
            growthAmount: 100
        )

        XCTAssertEqual(
            growingReward.incrementalPointAllocations(
                existingQuantities: [0, 0, 0, 0],
                additionalQuantity: 1
            ),
            [50, 100, 200, 0]
        )
    }

    func testDailyParentAssignmentsCalculateEachSelectedDateIndependently() {
        let dailyReward = makeRule(
            points: 50,
            maximum: 2,
            maximumPeriod: .daily,
            growthKind: .percentage,
            growthAmount: 100
        )

        XCTAssertEqual(
            dailyReward.incrementalPointAllocations(
                existingQuantities: [0, 1, 2],
                additionalQuantity: 1
            ),
            [50, 100, 0]
        )
    }

    func testVariableEntryDefaultsToFirstPayableQuantity() {
        let reading = makeRule(
            points: 1,
            minimum: 15,
            frequencyKind: .time,
            frequencyValue: 1,
            timeUnit: .minute
        )
        let intervalActivity = makeRule(
            points: 50,
            minimum: 2,
            frequencyKind: .time,
            frequencyValue: 15,
            timeUnit: .minute
        )
        let fixedAward = makeRule(points: 100, minimum: 4)

        XCTAssertEqual(reading.defaultEntryQuantity, 15)
        XCTAssertEqual(intervalActivity.defaultEntryQuantity, 30)
        XCTAssertEqual(fixedAward.defaultEntryQuantity, 1)
    }

    func testEntryKindMapsToRequestedCatalog() {
        XCTAssertEqual(makeRule(points: 50, kind: .reward).catalog, .incentives)
        XCTAssertEqual(makeRule(points: -50, kind: .penalty).catalog, .disincentives)
        XCTAssertEqual(makeRule(points: -100, kind: .purchase).catalog, .tradingPost)
    }

    func testOnlyParentRolesCanManageRules() {
        XCTAssertTrue(FamilyMembershipRole.familyAdmin.canManageRules)
        XCTAssertTrue(FamilyMembershipRole.owner.canManageRules)
        XCTAssertTrue(FamilyMembershipRole.parent.canManageRules)
        XCTAssertFalse(FamilyMembershipRole.caregiver.canManageRules)
        XCTAssertFalse(FamilyMembershipRole.child.canManageRules)
        XCTAssertFalse(FamilyMembershipRole.viewer.canManageRules)
    }

    func testOnlyParentRolesCanReviewLedger() {
        XCTAssertTrue(FamilyMembershipRole.familyAdmin.canReviewLedger)
        XCTAssertTrue(FamilyMembershipRole.owner.canReviewLedger)
        XCTAssertTrue(FamilyMembershipRole.parent.canReviewLedger)
        XCTAssertFalse(FamilyMembershipRole.caregiver.canReviewLedger)
        XCTAssertFalse(FamilyMembershipRole.child.canReviewLedger)
        XCTAssertFalse(FamilyMembershipRole.viewer.canReviewLedger)
    }

    func testCaregiverDoesNotParticipateInPoints() {
        XCTAssertTrue(MemberRole.child.participatesInPoints)
        XCTAssertTrue(MemberRole.parent.participatesInPoints)
        XCTAssertFalse(MemberRole.caregiver.participatesInPoints)
    }

    func testDefaultCatalogContainsOnlyTheCuratedFamilyItems() {
        let rules = SeedData.defaultRules(for: UUID())
        let earn = Set(rules.filter { $0.catalog == .incentives }.map(\.title))
        let lose = Set(rules.filter { $0.catalog == .disincentives }.map(\.title))
        let store = Set(rules.filter { $0.catalog == .tradingPost }.map(\.title))

        XCTAssertEqual(earn, [
            "Wash the dishes", "Make your bed", "Clean your room",
            "Help with laundry", "Rake the leaves", "Wash the car"
        ])
        XCTAssertEqual(lose, [
            "Swearing", "Name calling", "Unapproved device use", "School misbehavior"
        ])
        XCTAssertEqual(store, [
            "Extra 15 minutes of screen time", "Extra sweet",
            "Stay up late", "Pick game for Family Game Night"
        ])
        XCTAssertEqual(rules.count, 14)

        let makeBed = rules.first { $0.title == "Make your bed" }
        XCTAssertEqual(makeBed?.measurementUnit, .day)
        XCTAssertEqual(makeBed?.minimumTarget, 4)
        XCTAssertEqual(makeBed?.maximumTarget, 7)

        let cleanRoom = rules.first { $0.title == "Clean your room" }
        XCTAssertEqual(cleanRoom?.countSchedule, .once)
        XCTAssertEqual(cleanRoom?.maximumTarget, 1)

        XCTAssertEqual(
            rules.first { $0.title == "Help with laundry" }?.measurementUnit,
            .basket
        )
    }

    private func makeRule(
        points: Int,
        kind: EntryKind = .reward,
        minimum: Double? = nil,
        maximum: Double? = nil,
        warnings: Int = 0,
        accelerator: Bool = false,
        maximumPeriod: RuleMaximumPeriod = .weekly,
        frequencyKind: RuleFrequencyKind = .count,
        countSchedule: RuleCountSchedule = .every,
        frequencyValue: Double = 1,
        timeUnit: RuleTimeUnit = .day,
        growthKind: RuleGrowthKind? = nil,
        growthAmount: Double = 0
    ) -> RuleTemplate {
        RuleTemplate(
            title: "Test Rule",
            category: .behavior,
            kind: kind,
            defaultPoints: points,
            minimumTarget: minimum,
            maximumTarget: maximum,
            maximumPeriod: maximumPeriod,
            warningUnits: warnings,
            acceleratorEnabled: accelerator,
            acceleratorStartsAt: 2,
            acceleratorMultiplier: 2,
            frequencyKind: frequencyKind,
            countSchedule: countSchedule,
            frequencyValue: frequencyValue,
            timeUnit: timeUnit,
            growthEnabled: growthKind != nil,
            growthKind: growthKind ?? .percentage,
            growthAmount: growthAmount
        )
    }
}
