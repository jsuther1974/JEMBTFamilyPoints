import SwiftData
import XCTest
@testable import JEMBT_Family_Points_Tracker

final class AppleIDManagerTests: XCTestCase {
    func testAddingSameContactTwiceIsRejected() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()

        _ = try manager.addFamilyMember(
            family: family,
            name: "Taylor Example, Jr.",
            emailAddress: nil,
            birthDate: nil,
            sourceContactIdentifier: "synthetic-contact-1",
            role: .parent,
            modelContext: context,
            shouldCreateInvitation: false
        )

        XCTAssertThrowsError(
            try manager.addFamilyMember(
                family: family,
                name: "Taylor Example Jr.",
                emailAddress: nil,
                birthDate: nil,
                sourceContactIdentifier: "synthetic-contact-1",
                role: .parent,
                modelContext: context,
                shouldCreateInvitation: false
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Taylor Example, Jr. is already in this family.")
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 1)
    }

    func testDuplicateEmailIsCaseInsensitive() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()

        _ = try manager.addFamilyMember(
            family: family,
            name: "First Profile",
            emailAddress: "member-one@example.invalid",
            birthDate: nil,
            role: .parent,
            modelContext: context,
            shouldCreateInvitation: false
        )

        XCTAssertThrowsError(
            try manager.addFamilyMember(
                family: family,
                name: "Second Profile",
                emailAddress: "MEMBER-ONE@EXAMPLE.INVALID",
                birthDate: nil,
                role: .parent,
                modelContext: context,
                shouldCreateInvitation: false
            )
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 1)
    }

    func testMemberAvatarCanBeAddedUpdatedAndRemoved() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()
        let originalAvatar = Data([0x01, 0x02, 0x03])

        let result = try manager.addFamilyMember(
            family: family,
            name: "Avatar Member",
            emailAddress: nil,
            birthDate: nil,
            avatarData: originalAvatar,
            role: .parent,
            modelContext: context,
            shouldCreateInvitation: false
        )
        XCTAssertEqual(result.member.avatarData, originalAvatar)

        let replacementAvatar = Data([0x04, 0x05])
        try manager.updateFamilyMember(
            result.member,
            name: result.member.name,
            emailAddress: nil,
            birthDate: nil,
            avatarData: replacementAvatar,
            role: .parent,
            modelContext: context
        )
        XCTAssertEqual(result.member.avatarData, replacementAvatar)

        try manager.updateFamilyMember(
            result.member,
            name: result.member.name,
            emailAddress: nil,
            birthDate: nil,
            avatarData: nil,
            role: .parent,
            modelContext: context
        )
        XCTAssertNil(result.member.avatarData)
    }

    func testEnsureProfileCreatesOnlyForUnlinkedValidMembership() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "owner")
        let membership = FamilyMembership(familyID: family.id, appleID: "parent", role: .parent)
        context.insert(family)
        context.insert(membership)
        try context.save()

        let member = try AppleIDManager().ensureProfile(
            for: membership, in: family, defaultName: "Parent", modelContext: context
        )
        XCTAssertEqual(member.familyID, family.id)
        XCTAssertEqual(member.role, .parent)
        XCTAssertEqual(membership.familyMemberID, member.id)
    }

    func testEnsureProfileRejectsForeignFamilyLinkWithoutMutatingEitherFamily() throws {
        let context = try makeContext()
        let first = AllowanceFamily(name: "First", createdByAppleID: "first")
        let second = AllowanceFamily(name: "Second", createdByAppleID: "second")
        let foreignMember = FamilyMember(familyID: second.id, name: "Second Parent", role: .parent)
        let membership = FamilyMembership(
            familyID: first.id,
            familyMemberID: foreignMember.id,
            appleID: "first-parent",
            role: .parent
        )
        context.insert(first)
        context.insert(second)
        context.insert(foreignMember)
        context.insert(membership)
        try context.save()

        let manager = AppleIDManager()
        XCTAssertThrowsError(
            try manager.ensureProfile(
                for: membership, in: first, defaultName: "First Parent", modelContext: context
            )
        ) { error in
            XCTAssertEqual(error as? ProfileRestorationError, .memberFamilyMismatch)
        }
        XCTAssertEqual(foreignMember.familyID, second.id)
        XCTAssertTrue(foreignMember.isActive)
        XCTAssertEqual(membership.familyID, first.id)
        XCTAssertEqual(membership.familyMemberID, foreignMember.id)
        XCTAssertNil(manager.currentFamilyMember)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 1)
    }

    func testEnsureProfileRejectsInactiveAndRoleMismatchedLinksWithoutMutation() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "first")
        let inactive = FamilyMember(
            familyID: family.id, name: "Inactive", role: .parent, isActive: false
        )
        let inactiveMembership = FamilyMembership(
            familyID: family.id,
            familyMemberID: inactive.id,
            appleID: "inactive",
            role: .parent
        )
        let child = FamilyMember(
            familyID: family.id,
            name: "Child",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child
        )
        let mismatchedMembership = FamilyMembership(
            familyID: family.id,
            familyMemberID: child.id,
            appleID: "mismatch",
            role: .parent
        )
        context.insert(family)
        context.insert(inactive)
        context.insert(child)
        context.insert(inactiveMembership)
        context.insert(mismatchedMembership)
        try context.save()

        let manager = AppleIDManager()
        XCTAssertThrowsError(
            try manager.ensureProfile(
                for: inactiveMembership, in: family, defaultName: "Parent", modelContext: context
            )
        ) { error in
            XCTAssertEqual(error as? ProfileRestorationError, .inactiveMember)
        }
        XCTAssertFalse(inactive.isActive)

        XCTAssertThrowsError(
            try manager.ensureProfile(
                for: mismatchedMembership, in: family, defaultName: "Parent", modelContext: context
            )
        ) { error in
            XCTAssertEqual(error as? ProfileRestorationError, .roleProfileMismatch)
        }
        XCTAssertEqual(child.role, .child)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 2)
    }

    func testEnsureProfileCleansLegacyAdultBirthdateOnlyAfterValidation() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "first")
        let joinedAt = Date(timeIntervalSince1970: 10_000)
        let member = FamilyMember(
            familyID: family.id, name: "Parent", birthDate: joinedAt, role: .parent
        )
        let membership = FamilyMembership(
            familyID: family.id,
            familyMemberID: member.id,
            appleID: "parent",
            role: .parent,
            joinedAt: joinedAt
        )
        context.insert(family)
        context.insert(member)
        context.insert(membership)
        try context.save()

        _ = try AppleIDManager().ensureProfile(
            for: membership, in: family, defaultName: "Parent", modelContext: context
        )
        XCTAssertNil(member.birthDate)
    }

    func testEnsureProfileDoesNotFabricateUnlinkedChildProfile() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "owner")
        let membership = FamilyMembership(familyID: family.id, appleID: "child", role: .child)
        context.insert(family)
        context.insert(membership)
        try context.save()

        XCTAssertThrowsError(try AppleIDManager().ensureProfile(
            for: membership,
            in: family,
            defaultName: "Child",
            modelContext: context
        )) { error in
            XCTAssertEqual(error as? ProfileRestorationError, .linkedMemberUnavailable)
        }
        XCTAssertNil(membership.familyMemberID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FamilyMember>()).isEmpty)
    }

    func testCreateInvitationRejectsForeignInactiveAndRoleMismatchedProfiles() throws {
        let context = try makeContext()
        let first = AllowanceFamily(name: "First", createdByAppleID: "first")
        let second = AllowanceFamily(name: "Second", createdByAppleID: "second")
        let foreignChild = FamilyMember(
            familyID: second.id,
            name: "Foreign",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child
        )
        let inactiveChild = FamilyMember(
            familyID: first.id,
            name: "Inactive",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child,
            isActive: false
        )
        context.insert(first)
        context.insert(second)
        context.insert(foreignChild)
        context.insert(inactiveChild)
        try context.save()
        let manager = AppleIDManager()

        for (memberID, role) in [
            (foreignChild.id, FamilyMembershipRole.child),
            (inactiveChild.id, FamilyMembershipRole.child),
            (foreignChild.id, FamilyMembershipRole.parent)
        ] {
            XCTAssertThrowsError(try manager.createInvitation(
                for: first,
                role: role,
                familyMemberID: memberID,
                modelContext: context
            ))
        }
        XCTAssertThrowsError(try manager.createInvitation(
            for: first,
            role: .child,
            modelContext: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<FamilyInvitation>()).isEmpty)
    }

    func testAcceptInvitationCreatesCompleteAdultSessionAndMatchesCodeCaseInsensitively() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "owner")
        let invitation = FamilyInvitation(
            familyID: family.id,
            code: "AbC123",
            role: .caregiver
        )
        context.insert(family)
        context.insert(invitation)
        try context.save()
        let manager = AppleIDManager()

        let result = try manager.acceptInvitation(
            code: " abc123 ",
            appleID: "caregiver-apple-id",
            modelContext: context
        )

        XCTAssertEqual(result.member?.familyID, family.id)
        XCTAssertEqual(result.member?.role, .caregiver)
        XCTAssertEqual(result.membership.familyMemberID, result.member?.id)
        XCTAssertEqual(invitation.status, .accepted)
        XCTAssertTrue(manager.isSignedIn)
        XCTAssertEqual(manager.currentFamilyMember?.id, result.member?.id)
    }

    func testAcceptChildInvitationEstablishesItsLinkedProfile() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "owner")
        let child = FamilyMember(
            familyID: family.id,
            name: "Child",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child
        )
        let invitation = FamilyInvitation(
            familyID: family.id,
            familyMemberID: child.id,
            code: "CHILD2",
            role: .child
        )
        context.insert(family)
        context.insert(child)
        context.insert(invitation)
        try context.save()
        let manager = AppleIDManager()

        let result = try manager.acceptInvitation(
            code: invitation.code,
            appleID: "child-apple-id",
            modelContext: context
        )

        XCTAssertEqual(result.member?.id, child.id)
        XCTAssertEqual(result.membership.familyMemberID, child.id)
        XCTAssertEqual(result.membership.role, .child)
        XCTAssertEqual(manager.currentFamilyMember?.id, child.id)
    }

    func testAcceptInvitationRejectsExistingDifferentMembershipWithoutConsumingInvitation() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "First", createdByAppleID: "owner")
        let parent = FamilyMember(familyID: family.id, name: "Parent", role: .parent)
        let child = FamilyMember(
            familyID: family.id,
            name: "Child",
            birthDate: Date(timeIntervalSince1970: 0),
            role: .child
        )
        let existing = FamilyMembership(
            familyID: family.id,
            familyMemberID: parent.id,
            appleID: "same-apple-id",
            role: .parent
        )
        let invitation = FamilyInvitation(
            familyID: family.id,
            familyMemberID: child.id,
            code: "CHILD1",
            role: .child
        )
        context.insert(family)
        context.insert(parent)
        context.insert(child)
        context.insert(existing)
        context.insert(invitation)
        try context.save()
        let manager = AppleIDManager()

        XCTAssertThrowsError(try manager.acceptInvitation(
            code: invitation.code,
            appleID: existing.appleID,
            modelContext: context
        ))
        XCTAssertEqual(invitation.status, .pending)
        XCTAssertEqual(existing.role, .parent)
        XCTAssertEqual(existing.familyMemberID, parent.id)
        XCTAssertFalse(manager.isSignedIn)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMembership>()).count, 1)
    }

    func testCurrentAdministratorCannotChangeToIncompatibleRoleOrBeDeactivated() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Family", createdByAppleID: "admin")
        let admin = FamilyMember(familyID: family.id, name: "Admin", role: .parent)
        let membership = FamilyMembership(
            familyID: family.id, familyMemberID: admin.id, appleID: "admin", role: .familyAdmin
        )
        context.insert(family)
        context.insert(admin)
        context.insert(membership)
        try context.save()
        let manager = AppleIDManager()

        XCTAssertThrowsError(try manager.updateFamilyMember(
            admin, name: admin.name, emailAddress: nil, birthDate: .now, avatarData: nil,
            role: .child, modelContext: context
        ))
        XCTAssertEqual(admin.role, .parent)
        XCTAssertThrowsError(try manager.deactivateFamilyMember(admin, modelContext: context)) {
            XCTAssertEqual($0.localizedDescription, "The family administrator's profile cannot be deactivated.")
        }
        XCTAssertTrue(admin.isActive)
    }

    func testLinkedParticipantChildAndViewerProfilesRejectIncompatibleRoleChangesAndDeactivation() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Family", createdByAppleID: "admin")
        context.insert(family)
        let cases: [(FamilyMembershipRole, MemberRole)] = [
            (.parent, .parent), (.caregiver, .caregiver), (.child, .child), (.viewer, .child)
        ]
        let manager = AppleIDManager()

        for (index, item) in cases.enumerated() {
            let member = FamilyMember(
                familyID: family.id, name: "Member \(index)",
                birthDate: item.1 == .child ? Date(timeIntervalSince1970: 0) : nil,
                role: item.1
            )
            let membership = FamilyMembership(
                familyID: family.id, familyMemberID: member.id,
                appleID: "member-\(index)", role: item.0
            )
            context.insert(member)
            context.insert(membership)
            try context.save()

            let incompatibleRole: MemberRole = item.1 == .parent ? .caregiver : .parent
            XCTAssertThrowsError(try manager.updateFamilyMember(
                member, name: member.name, emailAddress: nil, birthDate: member.birthDate,
                avatarData: nil, role: incompatibleRole, modelContext: context
            ))
            XCTAssertEqual(member.role, item.1)
            XCTAssertThrowsError(try manager.deactivateFamilyMember(member, modelContext: context))
            XCTAssertTrue(member.isActive)
        }
    }

    func testPendingInvitationPreventsIncompatibleUpdateAndDeactivation() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Family", createdByAppleID: "admin")
        let child = FamilyMember(
            familyID: family.id, name: "Child", birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        let invitation = FamilyInvitation(
            familyID: family.id, familyMemberID: child.id, code: "PENDING", role: .viewer
        )
        context.insert(family)
        context.insert(child)
        context.insert(invitation)
        try context.save()
        let manager = AppleIDManager()

        XCTAssertThrowsError(try manager.updateFamilyMember(
            child, name: child.name, emailAddress: nil, birthDate: nil, avatarData: nil,
            role: .parent, modelContext: context
        ))
        XCTAssertThrowsError(try manager.deactivateFamilyMember(child, modelContext: context)) {
            XCTAssertEqual($0.localizedDescription, "Revoke the pending invitation before deactivating this profile.")
        }
        XCTAssertEqual(invitation.status, .pending)
        XCTAssertTrue(child.isActive)
    }

    func testExpiredPendingInvitationDoesNotBlockRoleChangeOrDeactivation() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Family", createdByAppleID: "admin")
        let child = FamilyMember(
            familyID: family.id, name: "Child", birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        let invitation = FamilyInvitation(
            familyID: family.id,
            familyMemberID: child.id,
            code: "EXPIRED",
            role: .viewer,
            expiresAt: Date(timeIntervalSinceNow: -60)
        )
        context.insert(family)
        context.insert(child)
        context.insert(invitation)
        try context.save()

        let manager = AppleIDManager()
        try manager.updateFamilyMember(
            child, name: child.name, emailAddress: nil, birthDate: nil, avatarData: nil,
            role: .parent, modelContext: context
        )
        try manager.deactivateFamilyMember(child, modelContext: context)

        XCTAssertEqual(child.role, .parent)
        XCTAssertFalse(child.isActive)
        XCTAssertEqual(invitation.status, .pending, "Expiration is evaluated without requiring an unrelated write")
    }

    func testAuthorizedRevokeUnblocksDeactivationAndRejectsForeignOrUnauthorizedRequests() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Local", createdByAppleID: "admin")
        let admin = FamilyMember(familyID: family.id, name: "Admin", role: .parent)
        let child = FamilyMember(
            familyID: family.id, name: "Child", birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        let membership = FamilyMembership(
            familyID: family.id, familyMemberID: admin.id, appleID: "admin", role: .familyAdmin
        )
        let invitation = FamilyInvitation(
            familyID: family.id, familyMemberID: child.id, code: "REVOKE", role: .child
        )
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign")
        let foreignChild = FamilyMember(
            familyID: foreignFamily.id, name: "Foreign child",
            birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        let foreignInvitation = FamilyInvitation(
            familyID: foreignFamily.id, familyMemberID: foreignChild.id, code: "FOREIGN", role: .child
        )
        [family, foreignFamily].forEach(context.insert)
        [admin, child, foreignChild].forEach(context.insert)
        context.insert(membership)
        context.insert(invitation)
        context.insert(foreignInvitation)
        try context.save()
        let manager = AppleIDManager()
        let session = MutationSession(appleID: "admin", family: family, membership: membership, member: admin)

        XCTAssertThrowsError(try manager.revokeInvitation(
            foreignInvitation, in: family, session: session, modelContext: context
        ))
        XCTAssertEqual(foreignInvitation.status, .pending)

        let parentMembership = FamilyMembership(
            familyID: family.id, familyMemberID: admin.id, appleID: "parent", role: .parent
        )
        XCTAssertThrowsError(try manager.revokeInvitation(
            invitation,
            in: family,
            session: MutationSession(appleID: "parent", family: family, membership: parentMembership, member: admin),
            modelContext: context
        ))
        XCTAssertEqual(invitation.status, .pending)

        try manager.revokeInvitation(invitation, in: family, session: session, modelContext: context)
        XCTAssertEqual(invitation.status, .revoked)
        try manager.deactivateFamilyMember(child, modelContext: context)
        XCTAssertFalse(child.isActive)
    }

    func testInactiveProfileIsRejectedAndForeignFamilyLinksAreNotMutated() throws {
        let context = try makeContext()
        let localFamily = AllowanceFamily(name: "Local", createdByAppleID: "local")
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign")
        let inactive = FamilyMember(familyID: localFamily.id, name: "Inactive", role: .parent, isActive: false)
        let local = FamilyMember(familyID: localFamily.id, name: "Local", role: .parent)
        let foreignMembership = FamilyMembership(
            familyID: foreignFamily.id, familyMemberID: local.id, appleID: "foreign", role: .parent
        )
        let foreignInvitation = FamilyInvitation(
            familyID: foreignFamily.id, familyMemberID: local.id, code: "FOREIGN", role: .parent
        )
        context.insert(localFamily)
        context.insert(foreignFamily)
        context.insert(inactive)
        context.insert(local)
        context.insert(foreignMembership)
        context.insert(foreignInvitation)
        try context.save()
        let manager = AppleIDManager()

        XCTAssertThrowsError(try manager.updateFamilyMember(
            inactive, name: "Changed", emailAddress: nil, birthDate: nil, avatarData: nil,
            role: .parent, modelContext: context
        ))
        XCTAssertThrowsError(try manager.deactivateFamilyMember(inactive, modelContext: context))
        try manager.deactivateFamilyMember(local, modelContext: context)
        XCTAssertFalse(local.isActive)
        XCTAssertEqual(foreignMembership.familyMemberID, local.id)
        XCTAssertEqual(foreignInvitation.status, .pending)
    }

    func testViewerInvitationRequiresActiveChildProfile() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Family", createdByAppleID: "admin")
        let child = FamilyMember(
            familyID: family.id, name: "Child", birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        let parent = FamilyMember(familyID: family.id, name: "Parent", role: .parent)
        let inactiveChild = FamilyMember(
            familyID: family.id, name: "Inactive", birthDate: Date(timeIntervalSince1970: 0),
            role: .child, isActive: false
        )
        context.insert(family)
        context.insert(child)
        context.insert(parent)
        context.insert(inactiveChild)
        try context.save()
        let manager = AppleIDManager()

        XCTAssertThrowsError(try manager.createInvitation(for: family, role: .viewer, modelContext: context))
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .viewer, familyMemberID: parent.id, modelContext: context
        ))
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .viewer, familyMemberID: inactiveChild.id, modelContext: context
        ))
        let invitation = try manager.createInvitation(
            for: family, role: .viewer, familyMemberID: child.id, modelContext: context
        )
        XCTAssertEqual(invitation.familyMemberID, child.id)
        XCTAssertEqual(invitation.role, .viewer)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: AllowanceFamily.self,
            FamilyMember.self,
            FamilyInvitation.self,
            FamilyMembership.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}