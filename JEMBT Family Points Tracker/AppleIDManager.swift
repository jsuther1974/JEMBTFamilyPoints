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
        if let memberID = membership.familyMemberID,
           let existing = try modelContext.fetch(
            FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == memberID })
           ).first {
            let hasLegacyPlaceholderBirthdate = existing.role != .child &&
                existing.birthDate.map { abs($0.timeIntervalSince(membership.joinedAt)) < 60 } == true
            if existing.familyID != family.id || !existing.isActive || hasLegacyPlaceholderBirthdate {
                existing.familyID = family.id
                existing.isActive = true
                if hasLegacyPlaceholderBirthdate {
                    existing.birthDate = nil
                }
                try modelContext.save()
            }
            currentFamilyMember = existing
            return existing
        }

        let member = FamilyMember(
            familyID: family.id,
            name: defaultName,
            role: membership.role.profileRole
        )
        modelContext.insert(member)
        membership.familyMemberID = member.id
        try modelContext.save()
        currentFamilyMember = member
        return member
    }

    func createFamily(
        named name: String,
        administratorName: String,
        for appleID: String,
        modelContext: ModelContext
    ) throws -> AllowanceFamily {
        let family = AllowanceFamily(name: name, createdByAppleID: appleID)
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
        let existingCodes = Set(try modelContext.fetch(FetchDescriptor<FamilyInvitation>()).map(\.code))
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
        role: MemberRole,
        modelContext: ModelContext,
        shouldCreateInvitation: Bool = true
    ) throws -> (member: FamilyMember, invitation: FamilyInvitation?) {
        try validateBirthDate(birthDate, for: role)
        let member = FamilyMember(
            familyID: family.id,
            name: name,
            emailAddress: emailAddress?.nilIfBlank,
            birthDate: birthDate,
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
        role: MemberRole,
        modelContext: ModelContext
    ) throws {
        try validateBirthDate(birthDate, for: role)
        member.name = name
        member.emailAddress = emailAddress?.nilIfBlank
        member.birthDate = birthDate
        member.role = role
        try modelContext.save()
    }

    private func validateBirthDate(_ birthDate: Date?, for role: MemberRole) throws {
        guard role != .child || birthDate != nil else {
            throw FamilyMemberError.childBirthdateRequired
        }
    }

    func deactivateFamilyMember(
        _ member: FamilyMember,
        modelContext: ModelContext
    ) throws {
        member.isActive = false
        try modelContext.save()
    }

    @discardableResult
    func acceptInvitation(
        code rawCode: String,
        appleID: String,
        modelContext: ModelContext
    ) throws -> (family: AllowanceFamily, membership: FamilyMembership, member: FamilyMember?) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pendingStatus = InvitationStatus.pending.rawValue
        let invitation = try modelContext.fetch(
            FetchDescriptor<FamilyInvitation>(predicate: #Predicate {
                $0.code == code && $0.statusRawValue == pendingStatus
            })
        ).first

        guard let invitation else {
            throw InvitationError.invalidOrExpired
        }
        if let expiresAt = invitation.expiresAt, expiresAt < .now {
            invitation.status = .revoked
            try modelContext.save()
            throw InvitationError.invalidOrExpired
        }

        let familyID = invitation.familyID
        let family = try modelContext.fetch(
            FetchDescriptor<AllowanceFamily>(predicate: #Predicate { $0.id == familyID })
        ).first
        guard let family else { throw InvitationError.familyUnavailable }

        let existing = try modelContext.fetch(
            FetchDescriptor<FamilyMembership>(predicate: #Predicate {
                $0.familyID == familyID && $0.appleID == appleID
            })
        ).first

        let membership = existing ?? FamilyMembership(
            familyID: invitation.familyID,
            familyMemberID: invitation.familyMemberID,
            appleID: appleID,
            role: invitation.role
        )
        if existing == nil { modelContext.insert(membership) }
        invitation.status = .accepted

        var member: FamilyMember?
        if let memberID = invitation.familyMemberID {
            member = try modelContext.fetch(
                FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == memberID })
            ).first
        }
        try modelContext.save()
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
        presentationAnchor ?? ASPresentationAnchor()
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

enum InvitationError: LocalizedError {
    case invalidOrExpired
    case familyUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidOrExpired: "That invitation code is invalid or has expired."
        case .familyUnavailable: "That family is no longer available."
        }
    }
}

enum FamilyMemberError: LocalizedError {
    case childBirthdateRequired

    var errorDescription: String? {
        switch self {
        case .childBirthdateRequired: "A birthdate is required for a child profile."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension FamilyMembershipRole {
    var profileRole: MemberRole {
        switch self {
        case .familyAdmin, .owner, .parent: .parent
        case .caregiver: .caregiver
        case .child, .viewer: .child
        }
    }
}
