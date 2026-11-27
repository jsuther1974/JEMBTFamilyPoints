import SwiftData
import XCTest
@testable import JEMBT_Family_Points_Tracker

@MainActor
final class PointMutationCommandServiceTests: XCTestCase {
    override func tearDown() {
        AppRuntimeDependencies.appleIDManager = nil
        AppRuntimeDependencies.modelContainer = nil
        super.tearDown()
    }

    func testAuthorizedParentCanGivePointsToChild() throws {
        let fixture = try makeFixture(sessionRole: .parent)

        let entry = try PointMutationCommandService.recordPointMutation(
            memberName: fixture.recipient.name,
            pointsDelta: 100,
            appleIDManager: fixture.appleIDManager,
            modelContext: fixture.context
        )

        XCTAssertEqual(entry.points, 100)
        XCTAssertEqual(entry.kind, .reward)
        XCTAssertEqual(entry.status, .approved)
        XCTAssertEqual(entry.reviewedBy, fixture.actor.name)
        XCTAssertEqual(entry.ruleID, fixture.rewardRule.id)

        let saved = try fixture.context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(saved.count, 1)
    }

    func testViewerSessionCannotRecordPointMutation() throws {
        let fixture = try makeFixture(sessionRole: .viewer)

        XCTAssertThrowsError(try PointMutationCommandService.recordPointMutation(
            memberName: fixture.recipient.name,
            pointsDelta: 50,
            appleIDManager: fixture.appleIDManager,
            modelContext: fixture.context
        )) {
            XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized)
        }

        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<LedgerEntry>()).count, 0)
    }

    func testPointMutationRemainsFamilyScoped() throws {
        let fixture = try makeFixture(sessionRole: .parent)

        XCTAssertThrowsError(try PointMutationCommandService.recordPointMutation(
            memberName: fixture.foreignChild.name,
            pointsDelta: 100,
            appleIDManager: fixture.appleIDManager,
            modelContext: fixture.context
        )) {
            XCTAssertEqual($0 as? PointMutationCommandError, .memberNotFound)
        }

        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<LedgerEntry>()).count, 0)
    }

    func testTakePointsCreatesPenaltyEntry() throws {
        let fixture = try makeFixture(sessionRole: .parent)

        let entry = try PointMutationCommandService.recordPointMutation(
            memberName: fixture.recipient.name,
            pointsDelta: -10,
            appleIDManager: fixture.appleIDManager,
            modelContext: fixture.context
        )

        XCTAssertEqual(entry.points, -10)
        XCTAssertEqual(entry.kind, .penalty)
        XCTAssertEqual(entry.ruleID, fixture.penaltyRule.id)
    }

    func testGivePointsIntentUsesAuthorizationAndCreatesApprovedEntryForParent() async throws {
        let fixture = try makeFixture(sessionRole: .parent)
        AppRuntimeDependencies.appleIDManager = fixture.appleIDManager
        AppRuntimeDependencies.modelContainer = fixture.container

        var intent = GivePointsIntent()
        intent.member = FamilyPointMemberEntity(member: fixture.recipient)
        intent.points = 100
        intent.semantic = .award

        _ = try await intent.perform()

        let entries = try fixture.context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].points, 100)
        XCTAssertEqual(entries[0].status, .approved)
    }

    func testGivePointsIntentRejectsViewerRole() async throws {
        let fixture = try makeFixture(sessionRole: .viewer)
        AppRuntimeDependencies.appleIDManager = fixture.appleIDManager
        AppRuntimeDependencies.modelContainer = fixture.container

        var intent = GivePointsIntent()
        intent.member = FamilyPointMemberEntity(member: fixture.recipient)
        intent.points = 25
        intent.semantic = .award

        do {
            _ = try await intent.perform()
            XCTFail("Expected viewer mutation through intent to be rejected")
        } catch {
            XCTAssertEqual(error as? ProtectedMutationError, .notAuthorized)
        }

        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<LedgerEntry>()).count, 0)
    }

    func testGivePointsIntentRemainsFamilyScoped() async throws {
        let fixture = try makeFixture(sessionRole: .parent)
        AppRuntimeDependencies.appleIDManager = fixture.appleIDManager
        AppRuntimeDependencies.modelContainer = fixture.container

        var intent = GivePointsIntent()
        intent.member = FamilyPointMemberEntity(member: fixture.foreignChild)
        intent.points = 50
        intent.semantic = .award

        do {
            _ = try await intent.perform()
            XCTFail("Expected foreign-family child lookup to fail")
        } catch {
            XCTAssertEqual(error as? PointMutationCommandError, .memberNotFound)
        }

        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<LedgerEntry>()).count, 0)
    }

    func testGivePointsIntentKeepsChildMutationsPending() async throws {
        let fixture = try makeFixture(sessionRole: .child)
        AppRuntimeDependencies.appleIDManager = fixture.appleIDManager
        AppRuntimeDependencies.modelContainer = fixture.container

        var intent = GivePointsIntent()
        intent.member = FamilyPointMemberEntity(member: fixture.recipient)
        intent.points = 20
        intent.semantic = .award

        _ = try await intent.perform()

        let entries = try fixture.context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .pending)
        XCTAssertNil(entries[0].reviewedBy)
        XCTAssertNil(entries[0].reviewedAt)
    }

    private func makeFixture(sessionRole: FamilyMembershipRole) throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: AllowanceFamily.self,
            FamilyInvitation.self,
            FamilyMembership.self,
            FamilyMember.self,
            RuleTemplate.self,
            RuleRider.self,
            LedgerEntry.self,
            WeeklySettlement.self,
            AppleIDMapping.self,
            configurations: configuration
        )
        FamilySharingCoordinator.shared.configure(modelContainer: container)

        let context = ModelContext(container)
        let family = AllowanceFamily(name: "Primary Family", createdByAppleID: "primary-admin")
        let actorProfileRole: MemberRole = sessionRole.profileRole
        let actor = FamilyMember(
            familyID: family.id,
            name: "Session Actor",
            birthDate: actorProfileRole == .child ? Date(timeIntervalSince1970: 0) : nil,
            role: actorProfileRole
        )
        let recipient = FamilyMember(
            familyID: family.id,
            name: "Child One",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child
        )
        let membership = FamilyMembership(
            familyID: family.id,
            familyMemberID: actor.id,
            appleID: "session-apple-id",
            role: sessionRole
        )

        let rewardRule = RuleTemplate(
            familyID: family.id,
            title: "Reward Rule",
            category: .household,
            kind: .reward,
            defaultPoints: 25,
            isEnabled: true
        )
        let penaltyRule = RuleTemplate(
            familyID: family.id,
            title: "Penalty Rule",
            category: .behavior,
            kind: .penalty,
            defaultPoints: -10,
            isEnabled: true
        )

        let foreignFamily = AllowanceFamily(name: "Foreign Family", createdByAppleID: "foreign-admin")
        let foreignChild = FamilyMember(
            familyID: foreignFamily.id,
            name: "Foreign Child",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child
        )

        [family, foreignFamily].forEach(context.insert)
        [actor, recipient, foreignChild].forEach(context.insert)
        [membership].forEach(context.insert)
        [rewardRule, penaltyRule].forEach(context.insert)
        try context.save()

        let appleIDManager = AppleIDManager()
        appleIDManager.establishSession(
            appleID: membership.appleID,
            family: family,
            membership: membership,
            member: actor
        )

        return Fixture(
            container: container,
            context: context,
            appleIDManager: appleIDManager,
            actor: actor,
            recipient: recipient,
            foreignChild: foreignChild,
            rewardRule: rewardRule,
            penaltyRule: penaltyRule
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let appleIDManager: AppleIDManager
        let actor: FamilyMember
        let recipient: FamilyMember
        let foreignChild: FamilyMember
        let rewardRule: RuleTemplate
        let penaltyRule: RuleTemplate
    }
}
