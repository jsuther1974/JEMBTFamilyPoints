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

enum RuleCatalog: String, Codable, CaseIterable, Identifiable {
    case incentives
    case disincentives
    case tradingPost

    var id: Self { self }

    var title: String {
        switch self {
        case .incentives: "Earn Points"
        case .disincentives: "Lose Points"
        case .tradingPost: "Rewards Shop"
        }
    }

    var subtitle: String {
        switch self {
        case .incentives: "Tasks, activities, and behaviors that earn points"
        case .disincentives: "Behaviors and events that lose points"
        case .tradingPost: "Prizes that can be purchased with points"
        }
    }

    var iconName: String {
        switch self {
        case .incentives: "star.circle.fill"
        case .disincentives: "exclamationmark.octagon.fill"
        case .tradingPost: "storefront.fill"
        }
    }

    var entryKind: EntryKind {
        switch self {
        case .incentives: .reward
        case .disincentives: .penalty
        case .tradingPost: .purchase
        }
    }
}

enum RuleFrequencyKind: String, Codable, CaseIterable, Identifiable {
    case count
    case time

    var id: Self { self }
    var title: String { self == .count ? "Count" : "Time" }
}

enum RuleCountSchedule: String, Codable, CaseIterable, Identifiable {
    case once
    case every

    var id: Self { self }
    var title: String { self == .once ? "Once" : "Every…" }
}

enum RuleTimeUnit: String, Codable, CaseIterable, Identifiable {
    case minute
    case hour
    case day
    case week
    case month

    var id: Self { self }

    func label(for value: Double) -> String {
        let plural = value == 1 ? "" : "s"
        return "\(rawValue)\(plural)"
    }
}

enum RuleMinimumPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: Self { self }
    var title: String { self == .weekly ? "Weekly" : "Monthly" }
}

enum RuleGrowthKind: String, Codable, CaseIterable, Identifiable {
    case fixedPoints
    case percentage

    var id: Self { self }
    var title: String { self == .fixedPoints ? "Points" : "Percent" }
}

enum RuleMeasurementUnit: String, Codable, CaseIterable, Identifiable {
    case occurrence
    case day
    case minute
    case fifteenMinutes
    case thirtyMinutes
    case hour
    case item
    case task

    var id: Self { self }

    var title: String {
        switch self {
        case .occurrence: "Occurrence"
        case .day: "Day"
        case .minute: "Minute"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .hour: "Hour"
        case .item: "Item"
        case .task: "Completed task"
        }
    }

    func label(for value: Double) -> String {
        let plural = value == 1 ? "" : "s"
        return switch self {
        case .occurrence: "occurrence\(plural)"
        case .day: "day\(plural)"
        case .minute: "minute\(plural)"
        case .fifteenMinutes: "15-minute interval\(plural)"
        case .thirtyMinutes: "30-minute interval\(plural)"
        case .hour: "hour\(plural)"
        case .item: "item\(plural)"
        case .task: "task\(plural)"
        }
    }
}

@Model
final class FamilyMember {
    var id: UUID = UUID()
    var familyID: UUID = UUID()
    var name: String = ""
    var emailAddress: String?
    var birthDate: Date?
    var sourceContactIdentifier: String?
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
        sourceContactIdentifier: String? = nil,
        role: MemberRole,
        isActive: Bool = true
    ) {
        self.id = id
        self.familyID = familyID
        self.name = name
        self.emailAddress = emailAddress
        self.birthDate = birthDate
        self.sourceContactIdentifier = sourceContactIdentifier
        self.roleRawValue = role.rawValue
        self.isActive = isActive
    }
}

@Model
final class RuleTemplate {
    var id: UUID = UUID()
    var familyID: UUID?
    var title: String = ""
    var categoryRawValue: String = RuleCategory.household.rawValue
    var kindRawValue: String = EntryKind.adjustment.rawValue
    var defaultPoints: Int = 0
    var guidance: String = ""
    var requiresApproval: Bool = true
    var isEnabled: Bool = true
    var iconName: String = "star.fill"
    var measurementUnitRawValue: String = RuleMeasurementUnit.occurrence.rawValue
    var minimumTarget: Double?
    var maximumTarget: Double?
    var warningUnits: Int = 0
    var acceleratorEnabled: Bool = false
    var acceleratorStartsAt: Int = 2
    var acceleratorMultiplier: Double = 2
    var frequencyKindRawValue: String = RuleFrequencyKind.count.rawValue
    var countScheduleRawValue: String = RuleCountSchedule.every.rawValue
    var frequencyValue: Double = 1
    var timeUnitRawValue: String = RuleTimeUnit.day.rawValue
    var growthEnabled: Bool = false
    var growthKindRawValue: String = RuleGrowthKind.percentage.rawValue
    var growthAmount: Double = 100
    var deductStartingPointsWhenMinimumMissed: Bool = false
    var minimumPeriodRawValue: String = RuleMinimumPeriod.weekly.rawValue

    var category: RuleCategory {
        get { RuleCategory(rawValue: categoryRawValue) ?? .household }
        set { categoryRawValue = newValue.rawValue }
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRawValue) ?? .adjustment }
        set { kindRawValue = newValue.rawValue }
    }

    var catalog: RuleCatalog {
        switch kind {
        case .reward: .incentives
        case .penalty: .disincentives
        case .purchase: .tradingPost
        case .adjustment: defaultPoints < 0 ? .disincentives : .incentives
        }
    }

    var measurementUnit: RuleMeasurementUnit {
        get { RuleMeasurementUnit(rawValue: measurementUnitRawValue) ?? .occurrence }
        set { measurementUnitRawValue = newValue.rawValue }
    }

    var frequencyKind: RuleFrequencyKind {
        get { RuleFrequencyKind(rawValue: frequencyKindRawValue) ?? .count }
        set { frequencyKindRawValue = newValue.rawValue }
    }

    var countSchedule: RuleCountSchedule {
        get { RuleCountSchedule(rawValue: countScheduleRawValue) ?? .every }
        set { countScheduleRawValue = newValue.rawValue }
    }

    var timeUnit: RuleTimeUnit {
        get { RuleTimeUnit(rawValue: timeUnitRawValue) ?? .day }
        set { timeUnitRawValue = newValue.rawValue }
    }

    var growthKind: RuleGrowthKind {
        get { RuleGrowthKind(rawValue: growthKindRawValue) ?? .percentage }
        set { growthKindRawValue = newValue.rawValue }
    }

    var minimumPeriod: RuleMinimumPeriod {
        get { RuleMinimumPeriod(rawValue: minimumPeriodRawValue) ?? .weekly }
        set { minimumPeriodRawValue = newValue.rawValue }
    }

    var firstAwardNumber: Int {
        max(1, Int(minimumTarget ?? 1), warningUnits + 1)
    }

    var lastAwardNumber: Int? {
        maximumTarget.map { Int($0) }
    }

    var maximumInputQuantity: Double {
        max(1, (maximumTarget ?? 1_000) * max(1, frequencyValue))
    }

    func awardCount(for quantity: Double) -> Int {
        guard quantity > 0 else { return 0 }
        if frequencyKind == .count && countSchedule == .once { return 1 }
        return Int((quantity / max(1, frequencyValue)).rounded(.down))
    }

    func quantityDescription(_ quantity: Double) -> String {
        if frequencyKind == .count {
            return "\(quantity.formatted()) time\(quantity == 1 ? "" : "s")"
        }
        return "\(quantity.formatted()) \(timeUnit.label(for: quantity))"
    }

    init(
        id: UUID = UUID(),
        familyID: UUID? = nil,
        title: String,
        category: RuleCategory,
        kind: EntryKind,
        defaultPoints: Int,
        guidance: String = "",
        requiresApproval: Bool = true,
        isEnabled: Bool = true,
        iconName: String = "star.fill",
        measurementUnit: RuleMeasurementUnit = .occurrence,
        minimumTarget: Double? = nil,
        maximumTarget: Double? = nil,
        warningUnits: Int = 0,
        acceleratorEnabled: Bool = false,
        acceleratorStartsAt: Int = 2,
        acceleratorMultiplier: Double = 2,
        frequencyKind: RuleFrequencyKind = .count,
        countSchedule: RuleCountSchedule = .every,
        frequencyValue: Double = 1,
        timeUnit: RuleTimeUnit = .day,
        growthEnabled: Bool = false,
        growthKind: RuleGrowthKind = .percentage,
        growthAmount: Double = 100,
        deductStartingPointsWhenMinimumMissed: Bool = false,
        minimumPeriod: RuleMinimumPeriod = .weekly
    ) {
        self.id = id
        self.familyID = familyID
        self.title = title
        self.categoryRawValue = category.rawValue
        self.kindRawValue = kind.rawValue
        self.defaultPoints = defaultPoints
        self.guidance = guidance
        self.requiresApproval = requiresApproval
        self.isEnabled = isEnabled
        self.iconName = iconName
        self.measurementUnitRawValue = measurementUnit.rawValue
        self.minimumTarget = minimumTarget
        self.maximumTarget = maximumTarget
        self.warningUnits = warningUnits
        self.acceleratorEnabled = acceleratorEnabled
        self.acceleratorStartsAt = acceleratorStartsAt
        self.acceleratorMultiplier = acceleratorMultiplier
        self.frequencyKindRawValue = frequencyKind.rawValue
        self.countScheduleRawValue = countSchedule.rawValue
        self.frequencyValue = frequencyValue
        self.timeUnitRawValue = timeUnit.rawValue
        self.growthEnabled = growthEnabled
        self.growthKindRawValue = growthKind.rawValue
        self.growthAmount = growthAmount
        self.deductStartingPointsWhenMinimumMissed = deductStartingPointsWhenMinimumMissed
        self.minimumPeriodRawValue = minimumPeriod.rawValue
    }

    func calculatedPoints(quantity: Double, riderMultiplier: Double = 1) -> Int {
        let awardCount = awardCount(for: quantity)
        let firstAward = firstAwardNumber
        let lastAward = min(awardCount, Int(maximumTarget ?? Double(awardCount)))
        guard lastAward >= firstAward else { return 0 }

        var total = 0.0
        for awardNumber in firstAward...lastAward {
            let growthStep = awardNumber - firstAward
            if growthEnabled {
                switch growthKind {
                case .fixedPoints:
                    let direction = defaultPoints < 0 ? -1.0 : 1.0
                    total += Double(defaultPoints) + direction * growthAmount * Double(growthStep)
                case .percentage:
                    total += Double(defaultPoints) * pow(1 + max(0, growthAmount) / 100, Double(growthStep))
                }
            } else if acceleratorEnabled {
                let exponent = max(0, awardNumber - max(firstAward, acceleratorStartsAt) + 1)
                total += Double(defaultPoints) * pow(max(1, acceleratorMultiplier), Double(exponent))
            } else {
                total += Double(defaultPoints)
            }
        }
        return Int((total * max(0, riderMultiplier)).rounded())
    }
}

@Model
final class RuleRider {
    var id: UUID = UUID()
    var ruleID: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var multiplier: Double = 2

    init(id: UUID = UUID(), ruleID: UUID, title: String, details: String = "", multiplier: Double = 2) {
        self.id = id
        self.ruleID = ruleID
        self.title = title
        self.details = details
        self.multiplier = multiplier
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
    var quantity: Double = 1
    var measurementUnitRawValue: String = RuleMeasurementUnit.occurrence.rawValue
    var riderTitle: String?

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
        reviewedAt: Date? = nil,
        quantity: Double = 1,
        measurementUnit: RuleMeasurementUnit = .occurrence,
        riderTitle: String? = nil
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
        self.quantity = quantity
        self.measurementUnitRawValue = measurementUnit.rawValue
        self.riderTitle = riderTitle
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

    var minimumMissDeductionPoints: Int = 0

    var minimumMissDeductionDetails: String = ""
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

        minimumMissDeductionPoints: Int = 0,

        minimumMissDeductionDetails: String = "",
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

        self.minimumMissDeductionPoints = minimumMissDeductionPoints

        self.minimumMissDeductionDetails = minimumMissDeductionDetails
        self.finalPoints = finalPoints
        self.cashAmount = cashAmount
        self.debtCarriedOut = debtCarriedOut
        self.confirmedAt = confirmedAt
        self.confirmedBy = confirmedBy
    }
}

struct MinimumMissDeduction: Identifiable {
    let ruleID: UUID
    let title: String
    let period: RuleMinimumPeriod
    let completedQuantity: Double
    let requiredQuantity: Double
    let points: Int

    var id: UUID { ruleID }
}



struct SettlementDraft: Identifiable {
    let child: FamilyMember
    let weekEnding: Date
    let startingPoints: Int
    let debtCarriedIn: Int
    let approvedEntryPoints: Int
    let parentPotShare: Int

    let minimumMissDeductions: [MinimumMissDeduction]
    let finalPoints: Int
    let cashAmount: Decimal
    let debtCarriedOut: Int

    var id: UUID { child.id }

    func deductionPoints(applying ruleIDs: Set<UUID>) -> Int {
        minimumMissDeductions
            .filter { ruleIDs.contains($0.ruleID) }
            .reduce(0) { $0 + $1.points }
    }

    func finalPoints(applying ruleIDs: Set<UUID>) -> Int {
        finalPoints - deductionPoints(applying: ruleIDs)
    }

    func cashAmount(applying ruleIDs: Set<UUID>) -> Decimal {
        Decimal(max(0, finalPoints(applying: ruleIDs))) / 100
    }

    func debtCarriedOut(applying ruleIDs: Set<UUID>) -> Int {
        min(0, finalPoints(applying: ruleIDs))
    }
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

    var firstNameForSorting: String {
        name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? name
    }

    static func comesBeforeInFamilyList(_ lhs: FamilyMember, _ rhs: FamilyMember) -> Bool {
        if lhs.role.familyListSortOrder != rhs.role.familyListSortOrder {
            return lhs.role.familyListSortOrder < rhs.role.familyListSortOrder
        }
        let firstNameComparison = lhs.firstNameForSorting.localizedCaseInsensitiveCompare(rhs.firstNameForSorting)
        if firstNameComparison != .orderedSame {
            return firstNameComparison == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
    var familyListSortOrder: Int {
        switch self {
        case .parent: 0
        case .child: 1
        case .caregiver: 2
        }
    }

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

    var canManageRules: Bool {
        self == .familyAdmin || self == .owner || self == .parent
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