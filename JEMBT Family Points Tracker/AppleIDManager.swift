import AuthenticationServices
import Foundation
import SwiftData

@Observable
class AppleIDManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var currentAppleID: String?
    var currentFamily: AllowanceFamily?
    var currentMembership: FamilyMembership?
    var currentFamilyMember: FamilyMember?
    var isSignedIn = false
    var errorMessage: String?
    var presentationAnchor: ASPresentationAnchor?
    
    private var authorizationCompletion: ((String?, Error?) -> Void)?

    func establishSession(
        appleID: String,
        family: AllowanceFamily,
        membership: FamilyMembership,
        member: FamilyMember? = nil
    ) {
        currentAppleID = appleID
        currentFamily = family
        currentMembership = membership
        currentFamilyMember = member
        isSignedIn = true
        errorMessage = nil
    }

    @discardableResult
    func ensureProfile(
        for membership: FamilyMembership,
        in family: AllowanceFamily,
        defaultName: String,
        modelContext: ModelContext
    ) throws -> FamilyMember {
        let linkedMember: FamilyMember?
        if let memberID = membership.familyMemberID {
            linkedMember = try modelContext.fetch(
                FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == memberID })
            ).first
        } else {
            linkedMember = nil
        }

        switch try ProfileRestorationPolicy.validate(
            membership: membership,
            family: family,
            linkedMember: linkedMember
        ) {
        case .useExisting(let existing):
            let hasLegacyPlaceholderBirthdate = existing.role != .child &&
                existing.birthDate.map { abs($0.timeIntervalSince(membership.joinedAt)) < 60 } == true
            if hasLegacyPlaceholderBirthdate {
                existing.birthDate = nil
                try modelContext.save()
            }
            currentFamilyMember = existing
            return existing
        case .create(let role):
            let member = FamilyMember(
                familyID: family.id,
                name: defaultName,
                role: role
            )
            modelContext.insert(member)
            membership.familyMemberID = member.id
            try modelContext.save()
            currentFamilyMember = member
            return member
        }
    }

    func createFamily(
        named name: String,
        administratorName: String,
        for appleID: String,
        cashValuePerPoint: Decimal = Decimal(string: "0.01")!,
        modelContext: ModelContext
    ) throws -> AllowanceFamily {
        let family = AllowanceFamily(
            name: name,
            createdByAppleID: appleID,
            cashValuePerPoint: max(0, cashValuePerPoint)
        )
        modelContext.insert(family)
        let administrator = FamilyMember(
            familyID: family.id,
            name: administratorName,
            role: .parent
        )
        modelContext.insert(administrator)
        let membership = FamilyMembership(
            familyID: family.id,
            familyMemberID: administrator.id,
            appleID: appleID,
            role: .familyAdmin
        )
        modelContext.insert(membership)
        try SeedData.installDefaultRules(for: family, in: modelContext)
        try modelContext.save()
        establishSession(
            appleID: appleID,
            family: family,
            membership: membership,
            member: administrator
        )
        return family
    }

    func createInvitation(
        for family: AllowanceFamily,
        role: FamilyMembershipRole,
        familyMemberID: UUID? = nil,
        modelContext: ModelContext
    ) throws -> FamilyInvitation {
        guard family.isActive else { throw InvitationError.familyUnavailable }
        if let familyMemberID {
            let member = try modelContext.fetch(
                FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == familyMemberID })
            ).first
            guard let member,
                  member.familyID == family.id,
                  member.isActive,
                  role.isCompatible(with: member.role) else {
                throw InvitationError.invalidProfile
            }
        } else if role == .child || role == .viewer {
            throw InvitationError.profileRequired
        }

        let existingCodes = Set(try modelContext.fetch(FetchDescriptor<FamilyInvitation>()).map {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var code: String
        repeat {
            code = String((0..<6).compactMap { _ in alphabet.randomElement() })
        } while existingCodes.contains(code)

        let invitation = FamilyInvitation(
            familyID: family.id,
            familyMemberID: familyMemberID,
            code: code,
            role: role,
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: .now)
        )
        modelContext.insert(invitation)
        try modelContext.save()
        return invitation
    }

    @discardableResult
    func addFamilyMember(
        family: AllowanceFamily,
        name: String,
        emailAddress: String?,
        birthDate: Date?,
        sourceContactIdentifier: String? = nil,
        avatarData: Data? = nil,
        role: MemberRole,
        modelContext: ModelContext,
        shouldCreateInvitation: Bool = true
    ) throws -> (member: FamilyMember, invitation: FamilyInvitation?) {
        try validateBirthDate(birthDate, for: role)
        try validateUniqueMember(
            familyID: family.id,
            name: name,
            emailAddress: emailAddress,
            birthDate: birthDate,
            sourceContactIdentifier: sourceContactIdentifier,
            modelContext: modelContext
        )
        let member = FamilyMember(
            familyID: family.id,
            name: name,
            emailAddress: emailAddress?.nilIfBlank,
            birthDate: birthDate,
            sourceContactIdentifier: sourceContactIdentifier?.nilIfBlank,
            avatarData: avatarData,
            role: role
        )
        modelContext.insert(member)

        let invitation = try shouldCreateInvitation
            ? createInvitation(
                for: family,
                role: FamilyMembershipRole(profileRole: role),
                familyMemberID: member.id,
                modelContext: modelContext
            )
            : nil
        try modelContext.save()
        return (member, invitation)
    }

    func updateFamilyMember(
        _ member: FamilyMember,
        name: String,
        emailAddress: String?,
        birthDate: Date?,
        avatarData: Data?,
        role: MemberRole,
        modelContext: ModelContext
    ) throws {
        guard member.isActive else { throw FamilyMemberError.inactiveMember }
        try validateLinkedRecords(
            for: member,
            proposedRole: role,
            deactivating: false,
            modelContext: modelContext
        )
        try validateBirthDate(birthDate, for: role)
        try validateUniqueMember(
            familyID: member.familyID,
            name: name,
            emailAddress: emailAddress,
            birthDate: birthDate,
            sourceContactIdentifier: member.sourceContactIdentifier,
            excluding: member.id,
            modelContext: modelContext
        )
        member.name = name
        member.emailAddress = emailAddress?.nilIfBlank
        member.birthDate = birthDate
        member.avatarData = avatarData
        member.role = role
        try modelContext.save()
    }

    private func validateBirthDate(_ birthDate: Date?, for role: MemberRole) throws {
        guard role != .child || birthDate != nil else {
            throw FamilyMemberError.childBirthdateRequired
        }
    }

    private func validateUniqueMember(
        familyID: UUID,
        name: String,
        emailAddress: String?,
        birthDate: Date?,
        sourceContactIdentifier: String?,
        excluding memberID: UUID? = nil,
        modelContext: ModelContext
    ) throws {
        let candidates = try modelContext.fetch(
            FetchDescriptor<FamilyMember>(predicate: #Predicate {
                $0.familyID == familyID && $0.isActive
            })
        )
        let normalizedName = name.normalizedMemberIdentity
        let normalizedEmail = emailAddress?.nilIfBlank?.lowercased()
        let contactIdentifier = sourceContactIdentifier?.nilIfBlank

        let duplicate = candidates.first { member in
            guard member.id != memberID else { return false }
            if let contactIdentifier,
               member.sourceContactIdentifier == contactIdentifier {
                return true
            }
            if let normalizedEmail,
               member.emailAddress?.nilIfBlank?.lowercased() == normalizedEmail {
                return true
            }
            guard member.name.normalizedMemberIdentity == normalizedName else { return false }
            switch (member.birthDate, birthDate) {
            case (nil, nil):
                return true
            case let (existingDate?, proposedDate?):
                return Calendar.current.isDate(existingDate, inSameDayAs: proposedDate)
            default:
                return false
            }
        }

        if let duplicate {
            throw FamilyMemberError.duplicateMember(duplicate.name)
        }
    }

    func deactivateFamilyMember(
        _ member: FamilyMember,
        modelContext: ModelContext
    ) throws {
        guard member.isActive else { throw FamilyMemberError.inactiveMember }
        try validateLinkedRecords(
            for: member,
            proposedRole: member.role,
            deactivating: true,
            modelContext: modelContext
        )
        member.isActive = false
        try modelContext.save()
    }

    private func validateLinkedRecords(
        for member: FamilyMember,
        proposedRole: MemberRole,
        deactivating: Bool,
        modelContext: ModelContext,
        now: Date = .now
    ) throws {
        let memberID = member.id
        let familyID = member.familyID
        let linkedMemberships = try modelContext.fetch(FetchDescriptor<FamilyMembership>()).filter {
            $0.familyID == familyID && $0.familyMemberID == memberID
        }
        let linkedPendingInvitations = try modelContext.fetch(FetchDescriptor<FamilyInvitation>()).filter {
            $0.familyID == familyID && $0.familyMemberID == memberID && $0.isActivePending(at: now)
        }
        if deactivating {
            if linkedMemberships.contains(where: { $0.role.canAdministerFamily }) {
                throw FamilyMemberError.administratorProfileRequired
            }
            if !linkedMemberships.isEmpty { throw FamilyMemberError.linkedMembership }
            if !linkedPendingInvitations.isEmpty { throw FamilyMemberError.pendingInvitation }
        }
        guard linkedMemberships.allSatisfy({ $0.role.isCompatible(with: proposedRole) }),
              linkedPendingInvitations.allSatisfy({ $0.role.isCompatible(with: proposedRole) }) else {
            throw FamilyMemberError.roleInUse
        }
    }

    func revokeInvitation(
        _ invitation: FamilyInvitation,
        in family: AllowanceFamily,
        session: MutationSession,
        modelContext: ModelContext
    ) throws {
        let targetMember: FamilyMember?
        if let memberID = invitation.familyMemberID {
            targetMember = try modelContext.fetch(
                FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == memberID })
            ).first
        } else {
            targetMember = nil
        }
        try ProtectedMutationPolicy.authorizeInvitationAdministration(
            session: session,
            targetFamily: family,
            targetMember: targetMember,
            targetInvitation: invitation
        )
        guard invitation.status == .pending else { throw InvitationError.notPending }
        invitation.status = .revoked
        try modelContext.save()
    }

    @discardableResult
    func acceptInvitation(
        code rawCode: String,
        appleID: String,
        modelContext: ModelContext
    ) throws -> (family: AllowanceFamily, membership: FamilyMembership, member: FamilyMember?) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingInvitations = try modelContext.fetch(FetchDescriptor<FamilyInvitation>()).filter {
            $0.status == .pending &&
                $0.code.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(code) == .orderedSame
        }
        guard pendingInvitations.count == 1, let invitation = pendingInvitations.first else {
            throw InvitationError.invalidOrExpired
        }
        if !invitation.isActivePending(at: .now) {
            invitation.status = .revoked
            try modelContext.save()
            throw InvitationError.invalidOrExpired
        }

        let familyID = invitation.familyID
        guard let family = try modelContext.fetch(
            FetchDescriptor<AllowanceFamily>(predicate: #Predicate { $0.id == familyID })
        ).first, family.isActive else {
            throw InvitationError.familyUnavailable
        }
        guard let invitationRole = FamilyMembershipRole(rawValue: invitation.roleRawValue) else {
            throw InvitationError.invalidProfile
        }

        let existing = try modelContext.fetch(
            FetchDescriptor<FamilyMembership>(predicate: #Predicate {
                $0.familyID == familyID && $0.appleID == appleID
            })
        )
        guard existing.count <= 1 else { throw InvitationError.membershipConflict }
        if let existing = existing.first {
            guard existing.roleRawValue == invitation.roleRawValue,
                  invitation.familyMemberID == nil || invitation.familyMemberID == existing.familyMemberID else {
                throw InvitationError.membershipConflict
            }
        }

        let membership = existing.first ?? FamilyMembership(
            familyID: invitation.familyID,
            familyMemberID: invitation.familyMemberID,
            appleID: appleID,
            role: invitationRole
        )
        let linkedMemberID = invitation.familyMemberID ?? membership.familyMemberID
        let member: FamilyMember
        if let linkedMemberID {
            guard let linkedMember = try modelContext.fetch(
                FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == linkedMemberID })
            ).first,
                  linkedMember.familyID == family.id,
                  linkedMember.isActive,
                  invitationRole.isCompatible(with: linkedMember.role) else {
                throw InvitationError.invalidProfile
            }
            member = linkedMember
            membership.familyMemberID = linkedMember.id
        } else {
            guard invitationRole != .child, invitationRole != .viewer else {
                throw InvitationError.profileRequired
            }
            member = FamilyMember(
                familyID: family.id,
                name: invitationRole.title,
                role: invitationRole.profileRole
            )
            modelContext.insert(member)
            membership.familyMemberID = member.id
        }

        if existing.isEmpty { modelContext.insert(membership) }
        invitation.status = .accepted
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        establishSession(appleID: appleID, family: family, membership: membership, member: member)
        return (family, membership, member)
    }

    func pendingInvitations(
        in modelContext: ModelContext
    ) throws -> [FamilyInvitation] {
        let pendingStatus = InvitationStatus.pending.rawValue
        return try modelContext.fetch(FetchDescriptor<FamilyInvitation>(predicate: #Predicate {
            $0.statusRawValue == pendingStatus
        }))
    }
    
    func signInWithApple(anchor: ASPresentationAnchor) {
        self.presentationAnchor = anchor
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let appleID = appleIDCredential.user
            self.currentAppleID = appleID
            self.errorMessage = nil
            authorizationCompletion?(appleID, nil)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.errorMessage = error.localizedDescription
        authorizationCompletion?(nil, error)
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            preconditionFailure("Sign in with Apple requires a presentation anchor before authorization begins.")
        }
        return presentationAnchor
    }
    
    // MARK: - Mapping Management
    
    /// Maps an Apple ID to a family member
    func createMapping(
        appleID: String,
        memberID: UUID,
        modelContext: ModelContext
    ) throws {
        let mapping = AppleIDMapping(appleID: appleID, familyMemberID: memberID)
        modelContext.insert(mapping)
        try modelContext.save()
    }
    
    /// Finds the family member associated with an Apple ID
    func familyMember(
        for appleID: String,
        in mappings: [AppleIDMapping],
        from members: [FamilyMember]
    ) -> FamilyMember? {
        guard let mapping = mappings.first(where: { $0.appleID == appleID }) else {
            return nil
        }
        return members.first { $0.id == mapping.familyMemberID }
    }
    
    /// Updates the last sign-in timestamp
    func updateLastSignIn(
        for appleID: String,
        in mappings: [AppleIDMapping],
        modelContext: ModelContext
    ) throws {
        if let mapping = mappings.first(where: { $0.appleID == appleID }) {
            mapping.lastSignInAt = .now
            try modelContext.save()
        }
    }
    
    /// Removes a mapping (admin only)
    func removeMapping(
        _ mapping: AppleIDMapping,
        modelContext: ModelContext
    ) throws {
        modelContext.delete(mapping)
        try modelContext.save()
    }
    
    /// Signs out the current user
    func signOut() {
        currentAppleID = nil
        currentFamily = nil
        currentMembership = nil
        currentFamilyMember = nil
        isSignedIn = false
        errorMessage = nil
    }
}

enum ProfileRestorationPolicy {
    enum Decision {
        case useExisting(FamilyMember)
        case create(MemberRole)
    }

    static func validate(
        membership: FamilyMembership,
        family: AllowanceFamily,
        linkedMember: FamilyMember?
    ) throws -> Decision {
        guard family.isActive else { throw ProfileRestorationError.inactiveFamily }
        guard membership.familyID == family.id else {
            throw ProfileRestorationError.membershipFamilyMismatch
        }
        guard let role = FamilyMembershipRole(rawValue: membership.roleRawValue) else {
            throw ProfileRestorationError.roleProfileMismatch
        }
        guard let linkedMemberID = membership.familyMemberID else {
            guard linkedMember == nil else { throw ProfileRestorationError.linkedMemberMismatch }
            guard role != .child, role != .viewer else {
                throw ProfileRestorationError.linkedMemberUnavailable
            }
            return .create(role.profileRole)
        }
        guard let linkedMember else { throw ProfileRestorationError.linkedMemberUnavailable }
        guard linkedMember.id == linkedMemberID else {
            throw ProfileRestorationError.linkedMemberMismatch
        }
        guard linkedMember.familyID == family.id else {
            throw ProfileRestorationError.memberFamilyMismatch
        }
        guard linkedMember.isActive else { throw ProfileRestorationError.inactiveMember }
        guard role.isCompatible(with: linkedMember.role) else {
            throw ProfileRestorationError.roleProfileMismatch
        }
        return .useExisting(linkedMember)
    }
}

enum ProfileRestorationError: LocalizedError, Equatable {
    case inactiveFamily
    case membershipFamilyMismatch
    case linkedMemberUnavailable
    case linkedMemberMismatch
    case memberFamilyMismatch
    case inactiveMember
    case roleProfileMismatch

    var errorDescription: String? {
        switch self {
        case .inactiveFamily:
            "The selected family is inactive. No profile was changed."
        case .membershipFamilyMismatch:
            "This membership belongs to a different family. No profile was changed."
        case .linkedMemberUnavailable:
            "The membership's linked profile is missing. No profile was changed."
        case .linkedMemberMismatch:
            "The membership does not link to the supplied profile. No profile was changed."
        case .memberFamilyMismatch:
            "The linked profile belongs to a different family. No profile was changed."
        case .inactiveMember:
            "The linked profile is inactive and cannot be restored automatically."
        case .roleProfileMismatch:
            "The membership role does not match the linked profile. No profile was changed."
        }
    }
}

enum InvitationError: LocalizedError {
    case invalidOrExpired
    case familyUnavailable
    case invalidProfile
    case profileRequired
    case membershipConflict
    case notPending

    var errorDescription: String? {
        switch self {
        case .invalidOrExpired: "That invitation code is invalid or has expired."
        case .familyUnavailable: "That family is no longer available."
        case .invalidProfile: "The invitation's family profile is invalid or inactive."
        case .profileRequired: "A child or viewer invitation must be linked to an existing child profile."
        case .membershipConflict: "This Apple ID already has a different membership in this family."
        case .notPending: "This invitation is no longer pending."
        }
    }
}

enum FamilyMemberError: LocalizedError {
    case childBirthdateRequired
    case duplicateMember(String)
    case inactiveMember
    case linkedMembership
    case pendingInvitation
    case administratorProfileRequired
    case roleInUse

    var errorDescription: String? {
        switch self {
        case .childBirthdateRequired: "A birthdate is required for a child profile."
        case .duplicateMember(let name): "\(name) is already in this family."
        case .inactiveMember: "An inactive family profile cannot be changed."
        case .linkedMembership: "This profile is linked to an active family membership and cannot be deactivated."
        case .pendingInvitation: "Revoke the pending invitation before deactivating this profile."
        case .administratorProfileRequired: "The family administrator's profile cannot be deactivated."
        case .roleInUse: "The new profile role is incompatible with a linked membership or pending invitation."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedMemberIdentity: String {
        split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}