import SwiftData
import XCTest
@testable import JEMBT_Family_Points_Tracker

final class AppleIDManagerTests: XCTestCase {
    func testAddingSameContactTwiceIsRejected() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()
        let session = administrationSession(for: family)

        _ = try manager.addFamilyMember(
            family: family,
            name: "Taylor Example, Jr.",
            emailAddress: nil,
            birthDate: nil,
            sourceContactIdentifier: "synthetic-contact-1",
            role: .parent,
            session: session,
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
                session: session,
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
        let session = administrationSession(for: family)

        _ = try manager.addFamilyMember(
            family: family,
            name: "First Profile",
            emailAddress: "member-one@example.invalid",
            birthDate: nil,
            role: .parent,
            session: session,
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
                session: session,
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
        let session = administrationSession(for: family)
        let originalAvatar = Data([0x01, 0x02, 0x03])

        let result = try manager.addFamilyMember(
            family: family,
            name: "Avatar Member",
            emailAddress: nil,
            birthDate: nil,
            avatarData: originalAvatar,
            role: .parent,
            session: session,
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

    func testAddFamilyMemberAllowsPersistedAdministratorAndOwnerSessions() throws {
        for role in [FamilyMembershipRole.familyAdmin, .owner] {
            let context = try makeContext()
            let family = AllowanceFamily(name: "Authorized \(role.rawValue)", createdByAppleID: "owner")
            context.insert(family)
            let persisted = try persistedSession(role: role, family: family, context: context)

            let result = try AppleIDManager().addFamilyMember(
                family: persisted.family,
                name: "New Parent",
                emailAddress: "new-parent-\(role.rawValue)@example.invalid",
                birthDate: nil,
                role: .parent,
                session: persisted.session,
                modelContext: context
            )

            XCTAssertEqual(result.member.familyID, persisted.family.id)
            XCTAssertEqual(result.invitation?.familyMemberID, result.member.id)
            XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 2)
            XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyInvitation>()).count, 1)
        }
    }

    func testAddFamilyMemberRejectsChildCaregiverAndViewerWithoutInsertingMemberOrInvitation() throws {
        for role in [FamilyMembershipRole.child, .caregiver, .viewer] {
            let context = try makeContext()
            let family = AllowanceFamily(name: "Unauthorized \(role.rawValue)", createdByAppleID: "owner")
            context.insert(family)
            let persisted = try persistedSession(role: role, family: family, context: context)

            try assertAddFamilyMemberRejected(
                family: persisted.family,
                session: persisted.session,
                expectedError: .notAuthorized,
                context: context
            )
        }
    }

    func testAddFamilyMemberRejectsStaleAppleIDAndMismatchedOrInactiveProfilesWithoutMutation() throws {
        do {
            let context = try makeContext()
            let family = AllowanceFamily(name: "Stale", createdByAppleID: "owner")
            context.insert(family)
            let persisted = try persistedSession(role: .familyAdmin, family: family, context: context)
            let staleSession = MutationSession(
                appleID: "stale-apple-id",
                family: persisted.family,
                membership: persisted.membership,
                member: persisted.member
            )
            try assertAddFamilyMemberRejected(
                family: persisted.family,
                session: staleSession,
                expectedError: .appleIDMismatch,
                context: context
            )
        }

        do {
            let context = try makeContext()
            let family = AllowanceFamily(name: "Mismatch", createdByAppleID: "owner")
            context.insert(family)
            let persisted = try persistedSession(role: .familyAdmin, family: family, context: context)
            let otherParent = FamilyMember(familyID: family.id, name: "Other Parent", role: .parent)
            context.insert(otherParent)
            try context.save()
            let mismatchedSession = MutationSession(
                appleID: persisted.appleID,
                family: persisted.family,
                membership: persisted.membership,
                member: otherParent
            )
            try assertAddFamilyMemberRejected(
                family: persisted.family,
                session: mismatchedSession,
                expectedError: .profileMismatch,
                context: context
            )
        }

        do {
            let context = try makeContext()
            let family = AllowanceFamily(name: "Inactive", createdByAppleID: "owner")
            context.insert(family)
            let persisted = try persistedSession(
                role: .familyAdmin,
                family: family,
                context: context,
                isActive: false
            )
            try assertAddFamilyMemberRejected(
                family: persisted.family,
                session: persisted.session,
                expectedError: .inactiveProfile,
                context: context
            )
        }
    }

    func testAddFamilyMemberRejectsForeignFamilySessionWithoutInsertingMemberOrInvitation() throws {
        let context = try makeContext()
        let localFamily = AllowanceFamily(name: "Local", createdByAppleID: "local-owner")
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign-owner")
        context.insert(localFamily)
        context.insert(foreignFamily)
        let foreign = try persistedSession(role: .owner, family: foreignFamily, context: context)

        try assertAddFamilyMemberRejected(
            family: localFamily,
            session: foreign.session,
            expectedError: .familyMismatch,
            context: context
        )
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
        let session = administrationSession(for: first)

        for (memberID, role) in [
            (foreignChild.id, FamilyMembershipRole.child),
            (inactiveChild.id, FamilyMembershipRole.child),
            (foreignChild.id, FamilyMembershipRole.parent)
        ] {
            XCTAssertThrowsError(try manager.createInvitation(
                for: first,
                role: role,
                familyMemberID: memberID,
                session: session,
                modelContext: context
            ))
        }
        XCTAssertThrowsError(try manager.createInvitation(
            for: first,
            role: .child,
            session: session,
            modelContext: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<FamilyInvitation>()).isEmpty)
    }

    func testInvitationMutationBoundaryEnforcesRoleSessionAndFamilyMatrix() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Local", createdByAppleID: "admin")
        let child = FamilyMember(
            familyID: family.id, name: "Local child",
            birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign")
        let foreignChild = FamilyMember(
            familyID: foreignFamily.id, name: "Foreign child",
            birthDate: Date(timeIntervalSince1970: 0), role: .child
        )
        [family, foreignFamily].forEach(context.insert)
        [child, foreignChild].forEach(context.insert)
        try context.save()
        let manager = AppleIDManager()

        for role in [FamilyMembershipRole.parent, .caregiver, .child, .viewer] {
            let session = mutationSession(role: role, family: family)
            XCTAssertThrowsError(try manager.createInvitation(
                for: family, role: .child, familyMemberID: child.id,
                session: session, modelContext: context
            ), "Expected creation denial for \(role)") {
                XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized)
            }
            let pending = FamilyInvitation(
                familyID: family.id, familyMemberID: child.id,
                code: "R\(role.rawValue)", role: .child
            )
            context.insert(pending)
            try context.save()
            XCTAssertThrowsError(try manager.revokeInvitation(
                pending, in: family, session: session, modelContext: context
            ), "Expected revocation denial for \(role)") {
                XCTAssertEqual($0 as? ProtectedMutationError, .notAuthorized)
            }
            XCTAssertEqual(pending.status, .pending)
        }

        for role in [FamilyMembershipRole.familyAdmin, .owner] {
            let session = mutationSession(role: role, family: family)
            let created = try manager.createInvitation(
                for: family, role: .child, familyMemberID: child.id,
                session: session, modelContext: context
            )
            try manager.revokeInvitation(created, in: family, session: session, modelContext: context)
            XCTAssertEqual(created.status, .revoked)
        }

        let adminSession = mutationSession(role: .familyAdmin, family: family)
        let invitationCount = try context.fetch(FetchDescriptor<FamilyInvitation>()).count
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .child, familyMemberID: foreignChild.id,
            session: adminSession, modelContext: context
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyInvitation>()).count, invitationCount)

        let foreignInvitation = FamilyInvitation(
            familyID: foreignFamily.id, familyMemberID: foreignChild.id,
            code: "FOREIGN", role: .child
        )
        context.insert(foreignInvitation)
        try context.save()
        XCTAssertThrowsError(try manager.revokeInvitation(
            foreignInvitation, in: family, session: adminSession, modelContext: context
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .foreignRecipient) }
        XCTAssertEqual(foreignInvitation.status, .pending)

        let staleSession = MutationSession(
            appleID: "stale", family: family,
            membership: adminSession.membership, member: adminSession.member
        )
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .parent, session: staleSession, modelContext: context
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .appleIDMismatch) }

        let inactiveSession = mutationSession(role: .familyAdmin, family: family)
        inactiveSession.member?.isActive = false
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .parent, session: inactiveSession, modelContext: context
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .inactiveProfile) }

        let mismatchedMember = FamilyMember(familyID: family.id, name: "Mismatched", role: .parent)
        let mismatchedSession = MutationSession(
            appleID: adminSession.appleID, family: family,
            membership: adminSession.membership, member: mismatchedMember
        )
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .parent, session: mismatchedSession, modelContext: context
        )) { XCTAssertEqual($0 as? ProtectedMutationError, .profileMismatch) }
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
        let session = administrationSession(for: family)

        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .viewer, session: session, modelContext: context
        ))
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .viewer, familyMemberID: parent.id,
            session: session, modelContext: context
        ))
        XCTAssertThrowsError(try manager.createInvitation(
            for: family, role: .viewer, familyMemberID: inactiveChild.id,
            session: session, modelContext: context
        ))
        let invitation = try manager.createInvitation(
            for: family, role: .viewer, familyMemberID: child.id,
            session: session, modelContext: context
        )
        XCTAssertEqual(invitation.familyMemberID, child.id)
        XCTAssertEqual(invitation.role, .viewer)
    }

    private func administrationSession(for family: AllowanceFamily) -> MutationSession {
        mutationSession(role: .familyAdmin, family: family)
    }

    private func mutationSession(
        role: FamilyMembershipRole,
        family: AllowanceFamily
    ) -> MutationSession {
        let appleID = "\(role.rawValue)-\(family.id.uuidString)"
        let profileRole: MemberRole = switch role {
        case .familyAdmin, .owner, .parent: .parent
        case .caregiver: .caregiver
        case .child, .viewer: .child
        }
        let member = FamilyMember(
            familyID: family.id,
            name: role.title,
            birthDate: profileRole == .child ? Date(timeIntervalSince1970: 0) : nil,
            role: profileRole
        )
        let membership = FamilyMembership(
            familyID: family.id,
            familyMemberID: member.id,
            appleID: appleID,
            role: role
        )
        return MutationSession(
            appleID: appleID,
            family: family,
            membership: membership,
            member: member
        )
    }

    private func persistedSession(
        role: FamilyMembershipRole,
        family: AllowanceFamily,
        context: ModelContext,
        isActive: Bool = true
    ) throws -> (
        appleID: String,
        family: AllowanceFamily,
        membership: FamilyMembership,
        member: FamilyMember,
        session: MutationSession
    ) {
        let appleID = "\(role.rawValue)-\(family.id.uuidString)"
        let profileRole: MemberRole = switch role {
        case .familyAdmin, .owner, .parent: .parent
        case .caregiver: .caregiver
        case .child, .viewer: .child
        }
        let member = FamilyMember(
            familyID: family.id,
            name: "Persisted \(role.title)",
            birthDate: profileRole == .child ? Date(timeIntervalSince1970: 0) : nil,
            role: profileRole,
            isActive: isActive
        )
        let membership = FamilyMembership(
            familyID: family.id,
            familyMemberID: member.id,
            appleID: appleID,
            role: role
        )
        context.insert(member)
        context.insert(membership)
        try context.save()

        let persistedFamily = try XCTUnwrap(
            context.fetch(FetchDescriptor<AllowanceFamily>()).first { $0.id == family.id }
        )
        let persistedMember = try XCTUnwrap(
            context.fetch(FetchDescriptor<FamilyMember>()).first { $0.id == member.id }
        )
        let persistedMembership = try XCTUnwrap(
            context.fetch(FetchDescriptor<FamilyMembership>()).first { $0.id == membership.id }
        )
        return (
            appleID,
            persistedFamily,
            persistedMembership,
            persistedMember,
            MutationSession(
                appleID: appleID,
                family: persistedFamily,
                membership: persistedMembership,
                member: persistedMember
            )
        )
    }

    private func assertAddFamilyMemberRejected(
        family: AllowanceFamily,
        session: MutationSession,
        expectedError: ProtectedMutationError,
        context: ModelContext
    ) throws {
        let memberCount = try context.fetch(FetchDescriptor<FamilyMember>()).count
        let invitationCount = try context.fetch(FetchDescriptor<FamilyInvitation>()).count

        XCTAssertThrowsError(try AppleIDManager().addFamilyMember(
            family: family,
            name: "Unauthorized Addition",
            emailAddress: "unauthorized@example.invalid",
            birthDate: nil,
            role: .parent,
            session: session,
            modelContext: context
        )) {
            XCTAssertEqual($0 as? ProtectedMutationError, expectedError)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, memberCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyInvitation>()).count, invitationCount)
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