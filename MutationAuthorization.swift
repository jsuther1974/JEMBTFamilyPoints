import Foundation

struct MutationSession {
    let appleID: String?
    let family: AllowanceFamily?
    let membership: FamilyMembership?
    let member: FamilyMember?

    init(appleIDManager: AppleIDManager) {
        appleID = appleIDManager.currentAppleID
        family = appleIDManager.currentFamily
        membership = appleIDManager.currentMembership
        member = appleIDManager.currentFamilyMember
    }

    init(
        appleID: String?,
        family: AllowanceFamily?,
        membership: FamilyMembership?,
        member: FamilyMember?
    ) {
        self.appleID = appleID
        self.family = family
        self.membership = membership
        self.member = member
    }
}

enum ProtectedMutationError: LocalizedError, Equatable {
    case missingSession
    case inactiveFamily
    case appleIDMismatch
    case familyMismatch
    case profileMismatch
    case inactiveProfile
    case notAuthorized
    case invalidRecipient
    case foreignRecipient
    case invalidRule
    case foreignRule
    case foreignEntry
    case invalidReviewStatus

    var errorDescription: String? {
        switch self {
        case .missingSession: "Sign in to a family before making this change."
        case .inactiveFamily: "This family is not active."
        case .appleIDMismatch, .familyMismatch, .profileMismatch: "The signed-in family session is no longer consistent."
        case .inactiveProfile: "The signed-in family profile is inactive."
        case .notAuthorized: "This account is not authorized to make this change."
        case .invalidRecipient: "This family member cannot receive points."
        case .foreignRecipient: "The selected family member does not belong to this family."
        case .invalidRule: "This rule cannot be used for this change."
        case .foreignRule: "The selected rule does not belong to this family."
        case .foreignEntry: "One or more ledger entries do not belong to this family."
        case .invalidReviewStatus: "A review must approve or reject a pending entry."
        }
    }
}

enum ProtectedMutationPolicy {
    private struct ValidatedSession {
        let familyID: UUID
        let role: FamilyMembershipRole
        let member: FamilyMember
    }

    static func activityApprovalStatus(
        session: MutationSession,
        recipient: FamilyMember,
        rule: RuleTemplate,
        kind: EntryKind
    ) throws -> ApprovalStatus {
        let session = try validate(session)
        guard recipient.familyID == session.familyID else { throw ProtectedMutationError.foreignRecipient }
        guard recipient.isActive, recipient.role.participatesInPoints else { throw ProtectedMutationError.invalidRecipient }
        guard recipient.role == .child || (recipient.role == .parent && kind == .penalty) else {
            throw ProtectedMutationError.invalidRecipient
        }
        guard rule.familyID == session.familyID else { throw ProtectedMutationError.foreignRule }
        guard rule.isEnabled,
              kind == .reward || kind == .penalty,
              rule.kind == kind else {
            throw ProtectedMutationError.invalidRule
        }

        if session.role == .caregiver || session.member.role == .caregiver { return .pending }
        if session.role == .child || session.member.role == .child { return .pending }
        guard session.role.canReviewLedger, session.member.role == .parent else {
            throw ProtectedMutationError.notAuthorized
        }
        return .approved
    }

    static func review(
        session: MutationSession,
        entries: [LedgerEntry],
        familyMemberIDs: Set<UUID>,
        familyRuleIDs: Set<UUID>,
        status: ApprovalStatus,
        reviewedBy: String,
        reviewedAt: Date = .now
    ) throws -> Int {
        let session = try validate(session)
        guard session.role.canReviewLedger, session.member.role == .parent else {
            throw ProtectedMutationError.notAuthorized
        }
        guard status == .approved || status == .rejected else {
            throw ProtectedMutationError.invalidReviewStatus
        }
        try validateEntries(entries, memberIDs: familyMemberIDs, ruleIDs: familyRuleIDs)
        return PointsEngine.applyReview(
            to: entries,
            status: status,
            reviewedBy: reviewedBy,
            reviewedAt: reviewedAt
        )
    }

    static func authorizeActivityCopy(
        session: MutationSession,
        entries: [LedgerEntry],
        familyMemberIDs: Set<UUID>,
        familyRuleIDs: Set<UUID>
    ) throws {
        let session = try validate(session)
        guard session.role.canReviewLedger, session.member.role == .parent else {
            throw ProtectedMutationError.notAuthorized
        }
        try validateEntries(entries, memberIDs: familyMemberIDs, ruleIDs: familyRuleIDs)
    }

    static func authorizeSettlementClose(
        session: MutationSession,
        familyMembers: [FamilyMember],
        entries: [LedgerEntry],
        rules: [RuleTemplate],
        settlements: [WeeklySettlement]
    ) throws {
        let session = try validate(session)
        guard session.role.canReviewLedger, session.member.role == .parent else {
            throw ProtectedMutationError.notAuthorized
        }
        guard familyMembers.allSatisfy({ $0.familyID == session.familyID }) else {
            throw ProtectedMutationError.foreignRecipient
        }
        guard rules.allSatisfy({ $0.familyID == session.familyID }) else {
            throw ProtectedMutationError.foreignRule
        }
        let memberIDs = Set(familyMembers.map(\.id))
        try validateEntries(entries, memberIDs: memberIDs, ruleIDs: Set(rules.map(\.id)))
        guard settlements.allSatisfy({ memberIDs.contains($0.childID) }) else {
            throw ProtectedMutationError.foreignEntry
        }
    }

    static func authorizeStoreCheckout(
        session: MutationSession,
        child: FamilyMember,
        items: [RuleTemplate]
    ) throws {
        let session = try validate(session)
        guard session.role == .child, session.member.role == .child else {
            throw ProtectedMutationError.notAuthorized
        }
        guard child.id == session.member.id, child.familyID == session.familyID else {
            throw ProtectedMutationError.foreignRecipient
        }
        guard child.isActive else { throw ProtectedMutationError.invalidRecipient }
        for item in items {
            guard item.familyID == session.familyID else { throw ProtectedMutationError.foreignRule }
            guard item.isEnabled, item.kind == .purchase, item.catalog == .tradingPost else {
                throw ProtectedMutationError.invalidRule
            }
        }
    }

    private static func validate(_ session: MutationSession) throws -> ValidatedSession {
        guard let appleID = session.appleID,
              let family = session.family,
              let membership = session.membership,
              let member = session.member else {
            throw ProtectedMutationError.missingSession
        }
        guard family.isActive else { throw ProtectedMutationError.inactiveFamily }
        guard membership.appleID == appleID else { throw ProtectedMutationError.appleIDMismatch }
        guard membership.familyID == family.id, member.familyID == family.id else {
            throw ProtectedMutationError.familyMismatch
        }
        guard membership.familyMemberID == member.id else {
            throw ProtectedMutationError.profileMismatch
        }
        guard member.isActive else { throw ProtectedMutationError.inactiveProfile }
        guard membership.role != .viewer else { throw ProtectedMutationError.notAuthorized }
        return ValidatedSession(familyID: family.id, role: membership.role, member: member)
    }

    private static func validateEntries(
        _ entries: [LedgerEntry],
        memberIDs: Set<UUID>,
        ruleIDs: Set<UUID>
    ) throws {
        guard entries.allSatisfy({ entry in
            memberIDs.contains(entry.memberID) && entry.ruleID.map(ruleIDs.contains) != false
        }) else {
            throw ProtectedMutationError.foreignEntry
        }
    }
}
