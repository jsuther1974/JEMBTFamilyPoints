import SwiftData
import XCTest
@testable import JEMBT_Family_Points_Tracker

@MainActor
final class MutationAuthorizationTests: XCTestCase {
    func testEveryMembershipRoleHasExplicitActivityBehavior() throws {
        for role in FamilyMembershipRole.allCases {
            let fixture = try makeFixture(role: role)
            let operation = {
                try ProtectedMutationPolicy.activityApprovalStatus(
                    session: fixture.session,
                    recipient: fixture.child,
                    rule: fixture.reward,
                    kind: .reward
                )
            }

            switch role {
            case .familyAdmin, .owner, .parent:
                XCTAssertEqual(try operation(), .approved, "Unexpected result for \(role)")
            case .caregiver, .child:
                XCTAssertEqual(try operation(), .pending, "Unexpected result for \(role)")
            case .viewer:
                XCTAssertThrowsError(try operation()) { XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized) }
            }
        }
    }

    func testMissingAndInconsistentSessionsAreRejected() throws {
        let fixture = try makeFixture(role: .parent)
        XCTAssertThrowsError(try activity(session: MutationSession(appleID: nil, family: nil, membership: nil, member: nil), fixture: fixture)) {
            XCTAssertEqual($0 as? ProtectedMutationError, .missingSession)
        }

        let wrongAppleID = MutationSession(
            appleID: "other-apple-id",
            family: fixture.family,
            membership: fixture.membership,
            member: fixture.actor
        )
        XCTAssertThrowsError(try activity(session: wrongAppleID, fixture: fixture)) {
            XCTAssertEqual($0 as? ProtectedMutationError, .appleIDMismatch)
        }

        let otherFamily = AllowanceFamily(name: "Other", createdByAppleID: "other")
        let mismatchedFamily = MutationSession(
            appleID: fixture.appleID,
            family: otherFamily,
            membership: fixture.membership,
            member: fixture.actor
        )
        XCTAssertThrowsError(try activity(session: mismatchedFamily, fixture: fixture)) {
            XCTAssertEqual($0 as? ProtectedMutationError, .familyMismatch)
        }

        let unlinkedMember = FamilyMember(familyID: fixture.family.id, name: "Unlinked", role: .parent)
        let mismatchedProfile = MutationSession(
            appleID: fixture.appleID,
            family: fixture.family,
            membership: fixture.membership,
            member: unlinkedMember
        )
        XCTAssertThrowsError(try activity(session: mismatchedProfile, fixture: fixture)) {
            XCTAssertEqual($0 as? ProtectedMutationError, .profileMismatch)
        }
    }

    func testActivityRejectsForeignAndCaregiverRecipientsAndForeignRules() throws {
        let fixture = try makeFixture(role: .parent)
        let otherFamily = AllowanceFamily(name: "Second family", createdByAppleID: "other")
        let foreignChild = FamilyMember(familyID: otherFamily.id, name: "Foreign child", role: .child)
        let foreignRule = makeRule(familyID: otherFamily.id, kind: .reward)
        fixture.context.insert(otherFamily)
        fixture.context.insert(foreignChild)
        fixture.context.insert(foreignRule)
        try fixture.context.save()

        XCTAssertThrowsError(try ProtectedMutationPolicy.activityApprovalStatus(
            session: fixture.session,
            recipient: foreignChild,
            rule: fixture.reward,
            kind: .reward
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRecipient) }

        let caregiver = FamilyMember(familyID: fixture.family.id, name: "Caregiver", role: .caregiver)
        XCTAssertThrowsError(try ProtectedMutationPolicy.activityApprovalStatus(
            session: fixture.session,
            recipient: caregiver,
            rule: fixture.reward,
            kind: .reward
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .invalidRecipient) }

        XCTAssertThrowsError(try ProtectedMutationPolicy.activityApprovalStatus(
            session: fixture.session,
            recipient: fixture.child,
            rule: foreignRule,
            kind: .reward
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRule) }
    }

    func testLedgerReviewCapabilitiesAndAuditMutationForAllRoles() throws {
        for role in FamilyMembershipRole.allCases {
            let fixture = try makeFixture(role: role)
            let entry = makeEntry(memberID: fixture.child.id, ruleID: fixture.reward.id)
            let operation = {
                try ProtectedMutationPolicy.review(
                    session: fixture.session,
                    entries: [entry],
                    familyMemberIDs: [fixture.child.id, fixture.actor.id],
                    familyRuleIDs: [fixture.reward.id],
                    status: .approved,
                    reviewedBy: fixture.actor.name
                )
            }

            if role.canReviewLedger {
                XCTAssertEqual(try operation(), 1)
                XCTAssertEqual(entry.status, .approved)
                XCTAssertEqual(entry.reviewedBy, fixture.actor.name)
                XCTAssertNotNil(entry.reviewedAt)
            } else {
                XCTAssertThrowsError(try operation()) { XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized) }
                XCTAssertEqual(entry.status, .pending)
                XCTAssertNil(entry.reviewedBy)
                XCTAssertNil(entry.reviewedAt)
            }
        }
    }

    func testActivityCopyRequiresParentCapabilityAndFamilyOwnedEntries() throws {
        let parent = try makeFixture(role: .parent)
        let entry = makeEntry(memberID: parent.child.id, ruleID: parent.reward.id)
        XCTAssertNoThrow(try ProtectedMutationPolicy.authorizeActivityCopy(
            session: parent.session,
            entries: [entry],
            familyMemberIDs: [parent.actor.id, parent.child.id],
            familyRuleIDs: [parent.reward.id]
        ))

        let caregiver = try makeFixture(role: .caregiver)
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeActivityCopy(
            session: caregiver.session,
            entries: [makeEntry(memberID: caregiver.child.id, ruleID: caregiver.reward.id)],
            familyMemberIDs: [caregiver.actor.id, caregiver.child.id],
            familyRuleIDs: [caregiver.reward.id]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized) }

        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeActivityCopy(
            session: parent.session,
            entries: [makeEntry(memberID: parent.child.id, ruleID: UUID())],
            familyMemberIDs: [parent.actor.id, parent.child.id],
            familyRuleIDs: [parent.reward.id]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignEntry) }
    }

    func testReviewRejectsForeignRecipientAndRuleBeforeMutation() throws {
        let fixture = try makeFixture(role: .owner)
        let foreignRecipientEntry = makeEntry(memberID: UUID(), ruleID: fixture.reward.id)
        XCTAssertThrowsError(try review(foreignRecipientEntry, fixture: fixture)) {
            XCTAssertEqual($0 as? ProtectedMutationError, .foreignEntry)
        }
        XCTAssertEqual(foreignRecipientEntry.status, .pending)

        let foreignRuleEntry = makeEntry(memberID: fixture.child.id, ruleID: UUID())
        XCTAssertThrowsError(try review(foreignRuleEntry, fixture: fixture)) {
            XCTAssertEqual($0 as? ProtectedMutationError, .foreignEntry)
        }
        XCTAssertEqual(foreignRuleEntry.status, .pending)
    }

    func testSettlementCloseRejectsUnauthorizedRolesAndForeignData() throws {
        for role in [FamilyMembershipRole.caregiver, .child, .viewer] {
            let fixture = try makeFixture(role: role)
            XCTAssertThrowsError(try authorizeClose(fixture: fixture)) {
                XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized)
            }
        }

        let fixture = try makeFixture(role: .familyAdmin)
        XCTAssertNoThrow(try authorizeClose(fixture: fixture))
        let foreignEntry = makeEntry(memberID: UUID(), ruleID: fixture.reward.id)
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeSettlementClose(
            session: fixture.session,
            familyMembers: [fixture.actor, fixture.child],
            entries: [foreignEntry],
            rules: [fixture.reward],
            settlements: []
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignEntry) }
    }

    func testStoreCheckoutRequiresLinkedChildAndRejectsForeignChildOrItem() throws {
        let fixture = try makeFixture(role: .child)
        let storeItem = makeRule(familyID: fixture.family.id, kind: .purchase)
        XCTAssertNoThrow(try ProtectedMutationPolicy.authorizeStoreCheckout(
            session: fixture.session,
            child: fixture.actor,
            items: [storeItem]
        ))

        let otherChild = FamilyMember(familyID: fixture.family.id, name: "Other child", role: .child)
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeStoreCheckout(
            session: fixture.session,
            child: otherChild,
            items: [storeItem]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRecipient) }

        let foreignItem = makeRule(familyID: UUID(), kind: .purchase)
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeStoreCheckout(
            session: fixture.session,
            child: fixture.actor,
            items: [foreignItem]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRule) }
    }

    func testAdministrationAndRuleManagementCapabilitiesAcrossAllRoles() throws {
        for role in FamilyMembershipRole.allCases {
            let fixture = try makeFixture(role: role)
            let administer = {
                try ProtectedMutationPolicy.authorizeFamilyAdministration(
                    session: fixture.session,
                    targetFamily: fixture.family
                )
            }
            let manageRule = {
                try ProtectedMutationPolicy.authorizeRuleManagement(
                    session: fixture.session,
                    targetRules: [fixture.reward]
                )
            }

            if role.canAdministerFamily {
                XCTAssertNoThrow(try administer(), "Unexpected administration denial for \(role)")
            } else {
                XCTAssertThrowsError(try administer()) {
                    XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized)
                }
            }
            if role.canManageRules {
                XCTAssertNoThrow(try manageRule(), "Unexpected rule denial for \(role)")
            } else {
                XCTAssertThrowsError(try manageRule()) {
                    XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized)
                }
            }
        }
    }

    func testAdministrationRejectsForeignFamilyMemberInvitationAndRuleTargets() throws {
        let fixture = try makeFixture(role: .familyAdmin)
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign")
        let foreignMember = FamilyMember(familyID: foreignFamily.id, name: "Foreign", role: .child)
        let foreignRule = makeRule(familyID: foreignFamily.id, kind: .reward)
        let foreignInvitation = FamilyInvitation(
            familyID: foreignFamily.id,
            familyMemberID: foreignMember.id,
            code: "FOREIGN",
            role: .child
        )

        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeFamilyAdministration(
            session: fixture.session,
            targetFamily: foreignFamily
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .familyMismatch) }
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeMemberAdministration(
            session: fixture.session,
            targetFamily: fixture.family,
            targetMember: foreignMember
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRecipient) }
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeInvitationAdministration(
            session: fixture.session,
            targetFamily: fixture.family,
            targetMember: fixture.child,
            targetInvitation: foreignInvitation
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .familyMismatch) }
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeRuleManagement(
            session: fixture.session,
            targetRules: [foreignRule]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRule) }
    }

    func testLedgerEditingRequiresReviewerAndRejectsForeignEntriesBeforeMutation() throws {
        let owner = try makeFixture(role: .owner)
        let entry = makeEntry(memberID: owner.child.id, ruleID: owner.reward.id)
        XCTAssertNoThrow(try ProtectedMutationPolicy.authorizeLedgerEditing(
            session: owner.session,
            entries: [entry],
            familyMemberIDs: [owner.actor.id, owner.child.id],
            familyRuleIDs: [owner.reward.id]
        ))

        let caregiver = try makeFixture(role: .caregiver)
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeLedgerEditing(
            session: caregiver.session,
            entries: [makeEntry(memberID: caregiver.child.id, ruleID: caregiver.reward.id)],
            familyMemberIDs: [caregiver.actor.id, caregiver.child.id],
            familyRuleIDs: [caregiver.reward.id]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized) }

        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeLedgerEditing(
            session: owner.session,
            entries: [makeEntry(memberID: UUID(), ruleID: owner.reward.id)],
            familyMemberIDs: [owner.actor.id, owner.child.id],
            familyRuleIDs: [owner.reward.id]
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignEntry) }
    }

    func testRoleProfileMismatchIsRejectedForProtectedAdministration() throws {
        let fixture = try makeFixture(role: .familyAdmin)
        fixture.actor.role = .caregiver
        XCTAssertThrowsError(try ProtectedMutationPolicy.authorizeFamilyAdministration(
            session: fixture.session,
            targetFamily: fixture.family
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .profileMismatch) }
    }

    private func activity(session: MutationSession, fixture: Fixture) throws -> ApprovalStatus {
        try ProtectedMutationPolicy.activityApprovalStatus(
            session: session,
            recipient: fixture.child,
            rule: fixture.reward,
            kind: .reward
        )
    }

    private func review(_ entry: LedgerEntry, fixture: Fixture) throws -> Int {
        try ProtectedMutationPolicy.review(
            session: fixture.session,
            entries: [entry],
            familyMemberIDs: [fixture.actor.id, fixture.child.id],
            familyRuleIDs: [fixture.reward.id],
            status: .rejected,
            reviewedBy: fixture.actor.name
        )
    }

    private func authorizeClose(fixture: Fixture) throws {
        try ProtectedMutationPolicy.authorizeSettlementClose(
            session: fixture.session,
            familyMembers: [fixture.actor, fixture.child],
            entries: [makeEntry(memberID: fixture.child.id, ruleID: fixture.reward.id)],
            rules: [fixture.reward],
            settlements: []
        )
    }

    private func makeFixture(role: FamilyMembershipRole) throws -> Fixture {
        let context = try makeContext()
        let appleID = "\(role.rawValue)-apple-id"
        let family = AllowanceFamily(name: "Primary", createdByAppleID: appleID)
        let profileRole: MemberRole = switch role {
        case .familyAdmin, .owner, .parent: .parent
        case .caregiver: .caregiver
        case .child, .viewer: .child
        }
        let actor = FamilyMember(familyID: family.id, name: role.title, role: profileRole)
        let membership = FamilyMembership(
            familyID: family.id,
            familyMemberID: actor.id,
            appleID: appleID,
            role: role
        )
        let child = role == .child
            ? actor
            : FamilyMember(familyID: family.id, name: "Recipient", role: .child)
        let reward = makeRule(familyID: family.id, kind: .reward)
        context.insert(family)
        context.insert(actor)
        context.insert(membership)
        if child.id != actor.id { context.insert(child) }
        context.insert(reward)
        try context.save()
        return Fixture(
            context: context,
            appleID: appleID,
            family: family,
            membership: membership,
            actor: actor,
            child: child,
            reward: reward
        )
    }

    private func makeRule(familyID: UUID, kind: EntryKind) -> RuleTemplate {
        RuleTemplate(
            familyID: familyID,
            title: kind == .purchase ? "Store item" : "Reward",
            category: kind == .purchase ? .rewardStore : .household,
            kind: kind,
            defaultPoints: kind == .purchase ? -100 : 100,
            isEnabled: true
        )
    }

    private func makeEntry(memberID: UUID, ruleID: UUID?) -> LedgerEntry {
        LedgerEntry(
            memberID: memberID,
            ruleID: ruleID,
            weekEnding: PointsEngine.weekEnding(containing: .now),
            title: "Reward",
            points: 100,
            kind: .reward,
            status: .pending,
            submittedBy: "Child"
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: AllowanceFamily.self,
            FamilyMembership.self,
            FamilyMember.self,
            RuleTemplate.self,
            LedgerEntry.self,
            WeeklySettlement.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @MainActor
    private struct Fixture {
        let context: ModelContext
        let appleID: String
        let family: AllowanceFamily
        let membership: FamilyMembership
        let actor: FamilyMember
        let child: FamilyMember
        let reward: RuleTemplate

        var session: MutationSession {
            MutationSession(appleID: appleID, family: family, membership: membership, member: actor)
        }
    }
}
