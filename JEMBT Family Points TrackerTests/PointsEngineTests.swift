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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
