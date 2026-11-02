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

    func testFamilyListRoleOrderIsParentsChildrenThenCaregivers() {
        let members = [
            FamilyMember(name: "Zoe Caregiver", role: .caregiver),
            FamilyMember(name: "Zoe Child", birthDate: date(2016, 1, 1), role: .child),
            FamilyMember(name: "Zoe Parent", role: .parent),
            FamilyMember(name: "Amy Child", birthDate: date(2018, 1, 1), role: .child),
            FamilyMember(name: "Amy Parent", role: .parent)
        ]

        XCTAssertEqual(
            members.sorted(by: FamilyMember.comesBeforeInFamilyList).map(\.name),
            ["Amy Parent", "Zoe Parent", "Amy Child", "Zoe Child", "Zoe Caregiver"]
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
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
