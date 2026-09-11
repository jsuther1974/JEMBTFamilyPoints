import Foundation
import SwiftData

enum MemberRole: String, Codable, CaseIterable {
    case child
    case parent
    case caregiver
}

enum EntryKind: String, Codable, CaseIterable {
    case reward
    case penalty
    case purchase
    case adjustment
}

enum ApprovalStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
}

enum RuleCategory: String, Codable, CaseIterable {
    case household
    case behavior
    case rewardStore
}

@Model
final class FamilyMember {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    var emailAddress: String?
    var birthDate: Date?
    var roleRawValue: String = MemberRole.child.rawValue
    var isActive: Bool = true

    var role: MemberRole {
        get { MemberRole(rawValue: roleRawValue) ?? .child }
        set { roleRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        familyID: UUID = UUID(),
        name: String,
        emailAddress: String? = nil,
        birthDate: Date? = nil,
        role: MemberRole,
        isActive: Bool = true
    ) {
        self.id = id
        self.familyID = familyID
        self.name = name
        self.emailAddress = emailAddress
        self.birthDate = birthDate
        self.roleRawValue = role.rawValue
        self.isActive = isActive
    }
}

@Model
final class RuleTemplate {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRawValue: String = RuleCategory.household.rawValue
    var kindRawValue: String = EntryKind.adjustment.rawValue
    var defaultPoints: Int = 0
    var guidance: String = ""
    var requiresApproval: Bool = true
    var isEnabled: Bool = true

    var category: RuleCategory {
        get { RuleCategory(rawValue: categoryRawValue) ?? .household }
        set { categoryRawValue = newValue.rawValue }
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRawValue) ?? .adjustment }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: RuleCategory,
        kind: EntryKind,
        defaultPoints: Int,
        guidance: String = "",
        requiresApproval: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.categoryRawValue = category.rawValue
        self.kindRawValue = kind.rawValue
        self.defaultPoints = defaultPoints
        self.guidance = guidance
        self.requiresApproval = requiresApproval
        self.isEnabled = isEnabled
    }
}

@Model
final class LedgerEntry {
    var id: UUID = UUID()
    var memberID: UUID = UUID()
    var ruleID: UUID?
    var occurredAt: Date = Date()
    var weekEnding: Date = Date()
    var title: String = ""
    var notes: String = ""
    var points: Int = 0
    var kindRawValue: String = EntryKind.adjustment.rawValue
    var statusRawValue: String = ApprovalStatus.pending.rawValue
    var submittedBy: String = ""
    var reviewedBy: String?
    var reviewedAt: Date?

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRawValue) ?? .adjustment }
        set { kindRawValue = newValue.rawValue }
    }

    var status: ApprovalStatus {
        get { ApprovalStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        memberID: UUID,
        ruleID: UUID? = nil,
        occurredAt: Date = .now,
        weekEnding: Date,
        title: String,
        notes: String = "",
        points: Int,
        kind: EntryKind,
        status: ApprovalStatus,
        submittedBy: String,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil
    ) {
        self.id = id
        self.memberID = memberID
        self.ruleID = ruleID
        self.occurredAt = occurredAt
        self.weekEnding = weekEnding
        self.title = title
        self.notes = notes
        self.points = points
        self.kindRawValue = kind.rawValue
        self.statusRawValue = status.rawValue
        self.submittedBy = submittedBy
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
    }
}

@Model
final class WeeklySettlement {
    var id: UUID = UUID()
    var childID: UUID = UUID()
    var weekEnding: Date = Date()
    var startingPoints: Int = 0
    var debtCarriedIn: Int = 0
    var approvedEntryPoints: Int = 0
    var parentPotShare: Int = 0
    var finalPoints: Int = 0
    var cashAmount: Decimal = 0
    var debtCarriedOut: Int = 0
    var confirmedAt: Date = Date()
    var confirmedBy: String = ""

    init(
        id: UUID = UUID(),
        childID: UUID,
        weekEnding: Date,
        startingPoints: Int,
        debtCarriedIn: Int,
        approvedEntryPoints: Int,
        parentPotShare: Int,
        finalPoints: Int,
        cashAmount: Decimal,
        debtCarriedOut: Int,
        confirmedAt: Date = .now,
        confirmedBy: String
    ) {
        self.id = id
        self.childID = childID
        self.weekEnding = weekEnding
        self.startingPoints = startingPoints
        self.debtCarriedIn = debtCarriedIn
        self.approvedEntryPoints = approvedEntryPoints
        self.parentPotShare = parentPotShare
        self.finalPoints = finalPoints
        self.cashAmount = cashAmount
        self.debtCarriedOut = debtCarriedOut
        self.confirmedAt = confirmedAt
        self.confirmedBy = confirmedBy
    }
}

struct SettlementDraft: Identifiable {
    let child: FamilyMember
    let weekEnding: Date
    let startingPoints: Int
    let debtCarriedIn: Int
    let approvedEntryPoints: Int
    let parentPotShare: Int
    let finalPoints: Int
    let cashAmount: Decimal
    let debtCarriedOut: Int

    var id: UUID { child.id }
}

@Model
final class AppleIDMapping {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var appleID: String = ""  // Unique identifier from Sign in with Apple
    var familyMemberID: UUID = UUID()
    var createdAt: Date = Date()
    var lastSignInAt: Date?
    
    init(
        id: UUID = UUID(),
        familyID: UUID = UUID(),
        appleID: String,
        familyMemberID: UUID,
        createdAt: Date = .now,
        lastSignInAt: Date? = nil
    ) {
        self.id = id
        self.familyID = familyID
        self.appleID = appleID
        self.familyMemberID = familyMemberID
        self.createdAt = createdAt
        self.lastSignInAt = lastSignInAt
    }
}

extension FamilyMember {
    var currentAge: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
    }
}

enum FamilyMembershipRole: String, Codable, CaseIterable {
    case familyAdmin
    case owner
    case parent
    case caregiver
    case child
    case viewer
}

extension MemberRole {
    var title: String {
        switch self {
        case .child: "Child"
        case .parent: "Parent"
        case .caregiver: "Caregiver"
        }
    }
}

extension FamilyMembershipRole {
    init(profileRole: MemberRole) {
        switch profileRole {
        case .child: self = .child
        case .parent: self = .parent
        case .caregiver: self = .caregiver
        }
    }

    var title: String {
        switch self {
        case .familyAdmin, .owner: "Family Admin"
        case .parent: "Parent"
        case .caregiver: "Caregiver"
        case .child: "Child"
        case .viewer: "Viewer"
        }
    }

    var canAdministerFamily: Bool {
        self == .familyAdmin || self == .owner
    }
}

enum InvitationStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case declined
    case revoked
}

@Model
final class AllowanceFamily {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var createdByAppleID: String = ""
    var isActive: Bool = true

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        createdByAppleID: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.createdByAppleID = createdByAppleID
        self.isActive = isActive
    }
}

@Model
final class FamilyInvitation {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var familyMemberID: UUID?
    var code: String = ""
    var roleRawValue: String = FamilyMembershipRole.child.rawValue
    var statusRawValue: String = InvitationStatus.pending.rawValue
    var createdAt: Date = Date()
    var expiresAt: Date?

    var role: FamilyMembershipRole {
        get { FamilyMembershipRole(rawValue: roleRawValue) ?? .child }
        set { roleRawValue = newValue.rawValue }
    }

    var status: InvitationStatus {
        get { InvitationStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        familyID: UUID,
        familyMemberID: UUID? = nil,
        code: String,
        role: FamilyMembershipRole,
        status: InvitationStatus = .pending,
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.familyID = familyID
        self.familyMemberID = familyMemberID
        self.code = code
        self.roleRawValue = role.rawValue
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

@Model
final class FamilyMembership {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var familyMemberID: UUID?
    var appleID: String = ""
    var roleRawValue: String = FamilyMembershipRole.child.rawValue
    var joinedAt: Date = Date()

    var role: FamilyMembershipRole {
        get { FamilyMembershipRole(rawValue: roleRawValue) ?? .child }
        set { roleRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        familyID: UUID,
        familyMemberID: UUID? = nil,
        appleID: String,
        role: FamilyMembershipRole,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.familyID = familyID
        self.familyMemberID = familyMemberID
        self.appleID = appleID
        self.roleRawValue = role.rawValue
        self.joinedAt = joinedAt
    }
}