import CloudKit
import Combine
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct FamilySharePayload: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maximumEncodedBytes = 10 * 1_024 * 1_024

    var schemaVersion = currentSchemaVersion
    let family: FamilyDTO
    let invitations: [InvitationDTO]
    let memberships: [MembershipDTO]
    let members: [MemberDTO]
    let rules: [RuleDTO]
    let riders: [RiderDTO]
    let entries: [EntryDTO]
    let settlements: [SettlementDTO]

    var familyID: UUID { family.id }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion, schemaVersion > 0 else {
            throw FamilySharingError.unsupportedSchema
        }
        guard Self.hasUniqueIDs(invitations),
              Self.hasUniqueIDs(memberships),
              Self.hasUniqueIDs(members),
              Self.hasUniqueIDs(rules),
              Self.hasUniqueIDs(riders),
              Self.hasUniqueIDs(entries),
              Self.hasUniqueIDs(settlements) else {
            throw FamilySharingError.duplicateIdentifier
        }

        let memberIDs = Set(members.map(\.id))
        let ruleIDs = Set(rules.map(\.id))
        guard invitations.allSatisfy({
            $0.familyID == family.id && $0.familyMemberID.map(memberIDs.contains) != false
        }), memberships.allSatisfy({
            $0.familyID == family.id && $0.familyMemberID.map(memberIDs.contains) != false
        }), members.allSatisfy({ $0.familyID == family.id }),
        rules.allSatisfy({ $0.familyID == family.id }),
        riders.allSatisfy({ ruleIDs.contains($0.ruleID) }),
        entries.allSatisfy({
            memberIDs.contains($0.memberID) && $0.ruleID.map(ruleIDs.contains) != false
        }), settlements.allSatisfy({ settlement in
            memberIDs.contains(settlement.childID) &&
                members.first(where: { $0.id == settlement.childID })?.roleRawValue == MemberRole.child.rawValue
        }) else {
            throw FamilySharingError.invalidFamilyBoundary
        }

        try validateRawValues()
        try validateMembershipsAndInvitations()
        try validateNumbersAndDates()
    }

    private func validateRawValues() throws {
        guard members.allSatisfy({ MemberRole(rawValue: $0.roleRawValue) != nil }),
              invitations.allSatisfy({
                  FamilyMembershipRole(rawValue: $0.roleRawValue) != nil &&
                      InvitationStatus(rawValue: $0.statusRawValue) != nil
              }), memberships.allSatisfy({ FamilyMembershipRole(rawValue: $0.roleRawValue) != nil }),
              rules.allSatisfy({ rule in
                  RuleCategory(rawValue: rule.categoryRawValue) != nil &&
                      EntryKind(rawValue: rule.kindRawValue) != nil &&
                      RuleMeasurementUnit(rawValue: rule.measurementUnitRawValue) != nil &&
                      RuleMaximumPeriod(rawValue: rule.maximumPeriodRawValue) != nil &&
                      RuleFrequencyKind(rawValue: rule.frequencyKindRawValue) != nil &&
                      RuleCountSchedule(rawValue: rule.countScheduleRawValue) != nil &&
                      RuleTimeUnit(rawValue: rule.timeUnitRawValue) != nil &&
                      RuleGrowthKind(rawValue: rule.growthKindRawValue) != nil &&
                      RuleMinimumPeriod(rawValue: rule.minimumPeriodRawValue) != nil &&
                      StoreInventoryPeriod(rawValue: rule.storeInventoryPeriodRawValue) != nil
              }), entries.allSatisfy({
                  EntryKind(rawValue: $0.kindRawValue) != nil &&
                      ApprovalStatus(rawValue: $0.statusRawValue) != nil &&
                      RuleMeasurementUnit(rawValue: $0.measurementUnitRawValue) != nil
              }) else {
            throw FamilySharingError.invalidRawValue
        }
    }

    private func validateMembershipsAndInvitations() throws {
        let membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let appleIDs = memberships.map { $0.appleID.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard appleIDs.allSatisfy({ !$0.isEmpty }), Set(appleIDs).count == appleIDs.count else {
            throw FamilySharingError.duplicateAppleIDMembership
        }

        let invitationCodes = invitations.map {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard invitationCodes.allSatisfy({ !$0.isEmpty }),
              Set(invitationCodes).count == invitationCodes.count else {
            throw FamilySharingError.duplicateInvitationCode
        }
        guard !Self.hasDuplicateActiveMemberIdentity(members) else {
            throw FamilySharingError.duplicateMemberIdentity
        }

        for membership in memberships {
            guard let memberID = membership.familyMemberID,
                  let member = membersByID[memberID],
                  member.isActive,
                  let role = FamilyMembershipRole(rawValue: membership.roleRawValue),
                  let profileRole = MemberRole(rawValue: member.roleRawValue),
                  role.isCompatible(with: profileRole) else {
                throw FamilySharingError.invalidRoleProfile
            }
        }
        for invitation in invitations {
            guard let role = FamilyMembershipRole(rawValue: invitation.roleRawValue) else {
                throw FamilySharingError.invalidRoleProfile
            }
            guard let memberID = invitation.familyMemberID else {
                guard role != .child, role != .viewer else {
                    throw FamilySharingError.invalidRoleProfile
                }
                continue
            }
            guard let member = membersByID[memberID],
                  member.isActive,
                  let profileRole = MemberRole(rawValue: member.roleRawValue),
                  role.isCompatible(with: profileRole) else {
                throw FamilySharingError.invalidRoleProfile
            }
        }
        guard members.allSatisfy({
            MemberRole(rawValue: $0.roleRawValue) != .child || $0.birthDate != nil
        }) else {
            throw FamilySharingError.invalidRoleProfile
        }
    }

    private func validateNumbersAndDates() throws {
        let dates = [family.createdAt] +
            invitations.flatMap { [$0.createdAt, $0.expiresAt].compactMap { $0 } } +
            memberships.map(\.joinedAt) +
            members.compactMap(\.birthDate) +
            entries.flatMap { [$0.occurredAt, $0.weekEnding, $0.reviewedAt].compactMap { $0 } } +
            settlements.flatMap { [$0.weekEnding, $0.confirmedAt] }
        guard dates.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              invitations.allSatisfy({ invitation in
                  invitation.expiresAt.map { $0 >= invitation.createdAt } ?? true
              }),
              Self.validDecimal(family.cashValuePerPoint, allowNegative: false),
              riders.allSatisfy({ Self.validFinite($0.multiplier, minimum: 0, maximum: 1_000_000) }),
              entries.allSatisfy({
                  Self.validFinite($0.quantity, minimum: 0, maximum: 1_000_000_000_000) &&
                      Self.validInt($0.points)
              }), rules.allSatisfy({ Self.validRule($0) }),
              settlements.allSatisfy({ settlement in
                  [settlement.startingPoints, settlement.debtCarriedIn, settlement.approvedEntryPoints,
                   settlement.parentPotShare, settlement.minimumMissDeductionPoints,
                   settlement.finalPoints, settlement.debtCarriedOut].allSatisfy({ Self.validInt($0) }) &&
                      Self.validDecimal(settlement.cashAmount, allowNegative: false)
              }) else {
            throw FamilySharingError.invalidNumericValue
        }
    }

    private static func validRule(_ rule: RuleDTO) -> Bool {
        let targets = [rule.minimumTarget, rule.maximumTarget].compactMap { $0 }
        let ages = [rule.minimumEligibleAge, rule.maximumEligibleAge].compactMap { $0 }
        return targets.allSatisfy { validFinite($0, minimum: 0, maximum: 1_000_000_000_000) } &&
            validFinite(rule.acceleratorMultiplier, minimum: 0, maximum: 1_000_000) &&
            validFinite(rule.frequencyValue, minimum: Double.leastNonzeroMagnitude, maximum: 1_000_000_000_000) &&
            validFinite(rule.growthAmount, minimum: -1_000_000, maximum: 1_000_000) &&
            validInt(rule.defaultPoints) && validInt(rule.warningUnits, allowNegative: false) &&
            validInt(rule.acceleratorStartsAt, allowNegative: false) &&
            validInt(rule.storeShelfPosition, allowNegative: false) &&
            rule.storeInventoryLimit.map { validInt($0, allowNegative: false) } != false &&
            ages.allSatisfy { (0...150).contains($0) } &&
            rule.minimumTarget.map { minimum in rule.maximumTarget.map { minimum <= $0 } ?? true } != false &&
            rule.minimumEligibleAge.map { minimum in rule.maximumEligibleAge.map { minimum <= $0 } ?? true } != false
    }

    private static func validFinite(_ value: Double, minimum: Double, maximum: Double) -> Bool {
        value.isFinite && value >= minimum && value <= maximum
    }

    private static func validInt(_ value: Int, allowNegative: Bool = true) -> Bool {
        let limit = 1_000_000_000_000_000
        return value <= limit && value >= (allowNegative ? -limit : 0)
    }

    private static func validDecimal(_ value: Decimal?, allowNegative: Bool) -> Bool {
        guard let value else { return true }
        let number = NSDecimalNumber(decimal: value)
        guard number != .notANumber else { return false }
        let limit = NSDecimalNumber(string: "1000000000000000")
        return number.compare(limit) != .orderedDescending &&
            (allowNegative || number.compare(NSDecimalNumber.zero) != .orderedAscending)
    }

    private static func hasDuplicateActiveMemberIdentity(_ values: [MemberDTO]) -> Bool {
        let active = values.filter(\.isActive)
        var contacts = Set<String>()
        var emails = Set<String>()
        var namesAndBirthdates = Set<String>()

        for member in active {
            if let contact = normalizedIdentityText(member.sourceContactIdentifier),
               !contacts.insert(contact).inserted { return true }
            if let email = normalizedIdentityText(member.emailAddress),
               !emails.insert(email).inserted { return true }
            if let name = normalizedIdentityText(member.name) {
                let birthdate = member.birthDate.map {
                    let components = Calendar.current.dateComponents([.year, .month, .day], from: $0)
                    return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
                } ?? "nil"
                if !namesAndBirthdates.insert("\(name)|\(birthdate)").inserted { return true }
            }
        }
        return false
    }

    private static func normalizedIdentityText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    private static func hasUniqueIDs<T: Identifiable>(_ values: [T]) -> Bool where T.ID == UUID {
        Set(values.map(\.id)).count == values.count
    }
}

struct FamilyDTO: Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let createdByAppleID: String
    let isActive: Bool
    let cashValuePerPoint: Decimal?

    init(_ value: AllowanceFamily) {
        id = value.id
        name = value.name
        createdAt = value.createdAt
        createdByAppleID = value.createdByAppleID
        isActive = value.isActive
        cashValuePerPoint = value.cashValuePerPoint
    }
}

struct InvitationDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let familyID: UUID
    let familyMemberID: UUID?
    let code: String
    let roleRawValue: String
    let statusRawValue: String
    let createdAt: Date
    let expiresAt: Date?

    init(_ value: FamilyInvitation) {
        id = value.id
        familyID = value.familyID
        familyMemberID = value.familyMemberID
        code = value.code
        roleRawValue = value.roleRawValue
        statusRawValue = value.statusRawValue
        createdAt = value.createdAt
        expiresAt = value.expiresAt
    }
}

struct MembershipDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let familyID: UUID
    let familyMemberID: UUID?
    let appleID: String
    let roleRawValue: String
    let joinedAt: Date

    init(_ value: FamilyMembership) {
        id = value.id
        familyID = value.familyID
        familyMemberID = value.familyMemberID
        appleID = value.appleID
        roleRawValue = value.roleRawValue
        joinedAt = value.joinedAt
    }
}

struct MemberDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let familyID: UUID
    let name: String
    let emailAddress: String?
    let birthDate: Date?
    let sourceContactIdentifier: String?
    let avatarData: Data?
    let roleRawValue: String
    let isActive: Bool

    init(_ value: FamilyMember) {
        id = value.id
        familyID = value.familyID
        name = value.name
        emailAddress = value.emailAddress
        birthDate = value.birthDate
        sourceContactIdentifier = value.sourceContactIdentifier
        avatarData = value.avatarData
        roleRawValue = value.roleRawValue
        isActive = value.isActive
    }
}

struct RiderDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let ruleID: UUID
    let title: String
    let details: String
    let multiplier: Double

    init(_ value: RuleRider) {
        id = value.id
        ruleID = value.ruleID
        title = value.title
        details = value.details
        multiplier = value.multiplier
    }
}

struct EntryDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let memberID: UUID
    let ruleID: UUID?
    let occurredAt: Date
    let weekEnding: Date
    let title: String
    let notes: String
    let points: Int
    let kindRawValue: String
    let statusRawValue: String
    let submittedBy: String
    let reviewedBy: String?
    let reviewedAt: Date?
    let quantity: Double
    let measurementUnitRawValue: String
    let riderTitle: String?

    init(_ value: LedgerEntry) {
        id = value.id
        memberID = value.memberID
        ruleID = value.ruleID
        occurredAt = value.occurredAt
        weekEnding = value.weekEnding
        title = value.title
        notes = value.notes
        points = value.points
        kindRawValue = value.kindRawValue
        statusRawValue = value.statusRawValue
        submittedBy = value.submittedBy
        reviewedBy = value.reviewedBy
        reviewedAt = value.reviewedAt
        quantity = value.quantity
        measurementUnitRawValue = value.measurementUnitRawValue
        riderTitle = value.riderTitle
    }
}

struct SettlementDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let childID: UUID
    let weekEnding: Date
    let startingPoints: Int
    let debtCarriedIn: Int
    let approvedEntryPoints: Int
    let parentPotShare: Int
    let minimumMissDeductionPoints: Int
    let minimumMissDeductionDetails: String
    let minimumMissReviewDetails: String?
    let finalPoints: Int
    let cashAmount: Decimal
    let debtCarriedOut: Int
    let confirmedAt: Date
    let confirmedBy: String
    let transactionFingerprint: String?

    init(_ value: WeeklySettlement) {
        id = value.id
        childID = value.childID
        weekEnding = value.weekEnding
        startingPoints = value.startingPoints
        debtCarriedIn = value.debtCarriedIn
        approvedEntryPoints = value.approvedEntryPoints
        parentPotShare = value.parentPotShare
        minimumMissDeductionPoints = value.minimumMissDeductionPoints
        minimumMissDeductionDetails = value.minimumMissDeductionDetails
        minimumMissReviewDetails = value.minimumMissReviewDetails
        finalPoints = value.finalPoints
        cashAmount = value.cashAmount
        debtCarriedOut = value.debtCarriedOut
        confirmedAt = value.confirmedAt
        confirmedBy = value.confirmedBy
        transactionFingerprint = value.transactionFingerprint
    }
}

struct RuleDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let familyID: UUID
    let title: String
    let categoryRawValue: String
    let kindRawValue: String
    let defaultPoints: Int
    let guidance: String
    let requiresApproval: Bool
    let isEnabled: Bool
    let iconName: String
    let measurementUnitRawValue: String
    let minimumTarget: Double?
    let maximumTarget: Double?
    let maximumPeriodRawValue: String
    let warningUnits: Int
    let acceleratorEnabled: Bool
    let acceleratorStartsAt: Int
    let acceleratorMultiplier: Double
    let frequencyKindRawValue: String
    let countScheduleRawValue: String
    let frequencyValue: Double
    let timeUnitRawValue: String
    let growthEnabled: Bool
    let growthKindRawValue: String
    let growthAmount: Double
    let deductStartingPointsWhenMinimumMissed: Bool
    let minimumPeriodRawValue: String
    let storeInventoryLimit: Int?
    let storeInventoryPeriodRawValue: String
    let storeShelfPosition: Int
    let minimumEligibleAge: Int?
    let maximumEligibleAge: Int?

    init(_ value: RuleTemplate, familyID: UUID) {
        id = value.id
        self.familyID = familyID
        title = value.title
        categoryRawValue = value.categoryRawValue
        kindRawValue = value.kindRawValue
        defaultPoints = value.defaultPoints
        guidance = value.guidance
        requiresApproval = value.requiresApproval
        isEnabled = value.isEnabled
        iconName = value.iconName
        measurementUnitRawValue = value.measurementUnitRawValue
        minimumTarget = value.minimumTarget
        maximumTarget = value.maximumTarget
        maximumPeriodRawValue = value.maximumPeriodRawValue
        warningUnits = value.warningUnits
        acceleratorEnabled = value.acceleratorEnabled
        acceleratorStartsAt = value.acceleratorStartsAt
        acceleratorMultiplier = value.acceleratorMultiplier
        frequencyKindRawValue = value.frequencyKindRawValue
        countScheduleRawValue = value.countScheduleRawValue
        frequencyValue = value.frequencyValue
        timeUnitRawValue = value.timeUnitRawValue
        growthEnabled = value.growthEnabled
        growthKindRawValue = value.growthKindRawValue
        growthAmount = value.growthAmount
        deductStartingPointsWhenMinimumMissed = value.deductStartingPointsWhenMinimumMissed
        minimumPeriodRawValue = value.minimumPeriodRawValue
        storeInventoryLimit = value.storeInventoryLimit
        storeInventoryPeriodRawValue = value.storeInventoryPeriodRawValue
        storeShelfPosition = value.storeShelfPosition
        minimumEligibleAge = value.minimumEligibleAge
        maximumEligibleAge = value.maximumEligibleAge
    }
}

struct FetchedFamilySharePayload: Equatable {
    let familyID: UUID
    let data: Data
    let changeTag: String?
}

protocol FamilyShareTransport {
    func createShare(familyID: UUID, familyName: String, payload: Data) async throws -> FamilyShareHandle
    func publish(familyID: UUID, payload: Data) async throws
    func resolveConflictKeepingLocal(_ fetched: FetchedFamilySharePayload, payload: Data) async throws
    func accept(_ metadata: CKShare.Metadata) async throws
    func fetchSharedPayloads() async throws -> [FetchedFamilySharePayload]
    func acknowledgeFetchedPayload(_ payload: FetchedFamilySharePayload) async throws
}

struct FamilyShareHandle: Identifiable {
    let share: CKShare
    let container: CKContainer
    var id: CKRecord.ID { share.recordID }
}

enum FamilySharingError: LocalizedError, Equatable {
    case notAuthorized
    case unauthorizedSharedFamily
    case invalidFamilyBoundary
    case duplicateIdentifier
    case duplicateAppleIDMembership
    case duplicateInvitationCode
    case duplicateMemberIdentity
    case invalidPayload
    case payloadTooLarge
    case invalidRawValue
    case invalidNumericValue
    case invalidRoleProfile
    case foreignIdentifierCollision
    case familyNotPublished
    case conflictingChange
    case localAndRemoteChangesConflict
    case missingPayload
    case unsupportedSchema
    case fetchedRecordMismatch

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "This account is not authorized to share this family."
        case .unauthorizedSharedFamily:
            "The shared family is not eligible for the active account or invitation code."
        case .invalidFamilyBoundary:
            "Shared data crossed a family boundary and was rejected."
        case .duplicateIdentifier:
            "Shared data contains duplicate record identifiers."
        case .duplicateAppleIDMembership:
            "Shared data contains duplicate or empty Apple ID memberships."
        case .duplicateInvitationCode:
            "Shared data contains duplicate or empty invitation codes."
        case .duplicateMemberIdentity:
            "Shared data contains duplicate active member identities."
        case .invalidPayload:
            "The shared family payload is malformed."
        case .payloadTooLarge:
            "The shared family payload exceeds the supported size limit."
        case .invalidRawValue:
            "Shared data contains an unsupported role, status, kind, or unit."
        case .invalidNumericValue:
            "Shared data contains an invalid or unsafe numeric value."
        case .invalidRoleProfile:
            "Shared membership and profile roles are inconsistent."
        case .foreignIdentifierCollision:
            "A shared record identifier is already owned by another local family. No data was changed."
        case .familyNotPublished:
            "This family does not have an iCloud share yet. An administrator must create one."
        case .conflictingChange:
            "The server changed since the last successful synchronization. Local data was preserved. Resolve the conflict explicitly."
        case .localAndRemoteChangesConflict:
            "Both local and shared family data changed since the last successful synchronization. Local data was preserved; explicit conflict resolution is required."
        case .missingPayload:
            "The shared family data is unavailable."
        case .unsupportedSchema:
            "This shared family uses an unsupported data version."
        case .fetchedRecordMismatch:
            "The CloudKit record identity does not match its family snapshot."
        }
    }
}

@MainActor
final class FamilySharingCoordinator: ObservableObject {
    struct PublicationIntent: Equatable {
        fileprivate let id: UUID
        let familyID: UUID
        fileprivate let previousDirtyIntent: FamilySharePublicationState.DirtyIntent?
        fileprivate let generation: Int
        fileprivate let isEnabled: Bool
    }

    static let shared = FamilySharingCoordinator()

    @Published private(set) var lastError: String?
    @Published private(set) var isSynchronizing = false
    @Published private(set) var conflictingFamilyIDs: Set<UUID> = []
    private(set) var modelContainer: ModelContainer?
    private var transport: FamilyShareTransport
    private let publicationDelay: Duration
    private var pendingPublishTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingPublishTokens: [UUID: UUID] = [:]
    private var pendingConflicts: [UUID: FetchedFamilySharePayload] = [:]
    private var preparedPublicationIntentIDs: [UUID: Set<UUID>] = [:]

    init(
        transport: FamilyShareTransport? = nil,
        publicationDelay: Duration = .milliseconds(300)
    ) {
        self.transport = transport ?? CloudKitFamilyShareTransport()
        self.publicationDelay = publicationDelay
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func prepareShare(session: MutationSession) async throws -> FamilyShareHandle {
        guard let context = modelContainer?.mainContext else {
            throw FamilySharingError.missingPayload
        }
        let family = try authorize(session: session, requireAdministrator: true)
        let publishedGeneration = FamilySharePublicationState.dirtyIntent(familyID: family.id)?.generation
        let payload = try FamilyShareStore.export(family: family, from: context)
        let handle = try await perform {
            try await transport.createShare(familyID: family.id, familyName: family.name, payload: payload)
        }
        FamilyShareBaseline.remember(payload: payload, familyID: family.id)
        FamilySharePublicationState.clearDirtyIfCurrent(
            familyID: family.id,
            publishedGeneration: publishedGeneration
        )
        return handle
    }

    func publish(session: MutationSession) async throws {
        let family = try authorize(session: session, requireAdministrator: false)
        try await publish(family: family, publishedGeneration: FamilySharePublicationState.dirtyIntent(
            familyID: family.id
        )?.generation)
    }

    private func publish(family: AllowanceFamily, publishedGeneration: Int?) async throws {
        guard let context = modelContainer?.mainContext else {
            throw FamilySharingError.missingPayload
        }
        let payload = try FamilyShareStore.export(family: family, from: context)
        try await perform {
            try await transport.publish(familyID: family.id, payload: payload)
        }
        FamilyShareBaseline.remember(payload: payload, familyID: family.id)
        FamilySharePublicationState.clearDirtyIfCurrent(
            familyID: family.id,
            publishedGeneration: publishedGeneration
        )
    }

    func publishAfterLocalMutation(session: MutationSession) async throws {
        guard ProcessInfo.processInfo.environment["UITEST_ISOLATED_STORE"] != "1" else { return }
        let family = try authorize(session: session, requireAdministrator: false)
        FamilySharePublicationState.markDirty(familyID: family.id)
        try await publish(session: session)
    }

    func retryPendingPublication(session: MutationSession) async throws {
        guard ProcessInfo.processInfo.environment["UITEST_ISOLATED_STORE"] != "1" else { return }
        guard let family = session.family,
              let dirtyIntent = FamilySharePublicationState.dirtyIntent(familyID: family.id) else { return }
        switch dirtyIntent.authorization {
        case .general:
            _ = try authorize(session: session, requireAdministrator: false)
        case .invitationRedemption(let authorization):
            try authorizeInvitationRedemption(
                authorization,
                familyID: family.id,
                session: session
            )
        }
        try await publish(family: family, publishedGeneration: dirtyIntent.generation)
    }

    func prepareProtectedMutationPublication(session: MutationSession) throws -> PublicationIntent {
        let family = try authorize(session: session, requireAdministrator: false)
        return preparePublicationIntent(familyID: family.id)
    }

    func prepareInvitationRedemptionPublication(
        code rawCode: String,
        appleID rawAppleID: String,
        modelContext: ModelContext,
        now: Date = .now
    ) throws -> PublicationIntent {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let invitations = try modelContext.fetch(FetchDescriptor<FamilyInvitation>()).filter {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(code) == .orderedSame &&
                $0.isActivePending(at: now)
        }
        guard invitations.count == 1, let invitation = invitations.first else {
            throw InvitationError.invalidOrExpired
        }
        let familyID = invitation.familyID
        guard try modelContext.fetch(
            FetchDescriptor<AllowanceFamily>(predicate: #Predicate { $0.id == familyID })
        ).first?.isActive == true else {
            throw InvitationError.familyUnavailable
        }
        let appleID = rawAppleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appleID.isEmpty,
              let role = FamilyMembershipRole(rawValue: invitation.roleRawValue) else {
            throw InvitationError.invalidProfile
        }
        return preparePublicationIntent(
            familyID: familyID,
            authorization: .invitationRedemption(.init(
                invitationID: invitation.id,
                appleID: appleID,
                roleRawValue: role.rawValue,
                familyMemberID: invitation.familyMemberID
            ))
        )
    }

    private func preparePublicationIntent(
        familyID: UUID,
        authorization: FamilySharePublicationState.Authorization = .general
    ) -> PublicationIntent {
        let isEnabled = ProcessInfo.processInfo.environment["UITEST_ISOLATED_STORE"] != "1"
        let previousDirtyIntent = isEnabled ? FamilySharePublicationState.dirtyIntent(familyID: familyID) : nil
        let generation = isEnabled
            ? FamilySharePublicationState.markDirty(familyID: familyID, authorization: authorization)
            : 0
        let intent = PublicationIntent(
            id: UUID(),
            familyID: familyID,
            previousDirtyIntent: previousDirtyIntent,
            generation: generation,
            isEnabled: isEnabled
        )
        guard isEnabled else { return intent }
        preparedPublicationIntentIDs[familyID, default: []].insert(intent.id)
        return intent
    }

    func commitProtectedMutationPublication(_ intent: PublicationIntent, session: MutationSession) {
        guard intent.isEnabled else { return }
        guard authorizeCommittedIntent(intent, session: session) else {
            preparedPublicationIntentIDs[intent.familyID]?.remove(intent.id)
            lastError = FamilySharingError.notAuthorized.localizedDescription
            return
        }
        preparedPublicationIntentIDs[intent.familyID]?.remove(intent.id)
        schedulePendingPublication(familyID: intent.familyID, session: session)
    }

    func rollbackProtectedMutationPublication(_ intent: PublicationIntent) {
        guard intent.isEnabled else { return }
        preparedPublicationIntentIDs[intent.familyID]?.remove(intent.id)
        if preparedPublicationIntentIDs[intent.familyID]?.isEmpty != false {
            FamilySharePublicationState.restoreDirty(
                familyID: intent.familyID,
                replacingGeneration: intent.generation,
                with: intent.previousDirtyIntent
            )
        }
    }

    private func authorizeCommittedIntent(_ intent: PublicationIntent, session: MutationSession) -> Bool {
        guard let dirtyIntent = FamilySharePublicationState.dirtyIntent(familyID: intent.familyID),
              dirtyIntent.generation == intent.generation else { return false }
        switch dirtyIntent.authorization {
        case .general:
            return (try? authorize(session: session, requireAdministrator: false).id) == intent.familyID
        case .invitationRedemption(let authorization):
            return (try? authorizeInvitationRedemption(
                authorization,
                familyID: intent.familyID,
                session: session
            )) != nil
        }
    }

    private func authorizeInvitationRedemption(
        _ authorization: FamilySharePublicationState.InvitationRedemptionAuthorization,
        familyID: UUID,
        session: MutationSession
    ) throws {
        guard let context = modelContainer?.mainContext,
              let appleID = session.appleID,
              let family = session.family,
              let membership = session.membership,
              let member = session.member,
              appleID == authorization.appleID,
              family.id == familyID, family.isActive,
              membership.familyID == familyID,
              membership.appleID == authorization.appleID,
              membership.roleRawValue == authorization.roleRawValue,
              membership.familyMemberID == member.id,
              member.familyID == familyID, member.isActive,
              authorization.familyMemberID == nil || authorization.familyMemberID == member.id,
              membership.role.isCompatible(with: member.role) else {
            throw FamilySharingError.notAuthorized
        }
        let invitationID = authorization.invitationID
        let storedInvitations = try context.fetch(
            FetchDescriptor<FamilyInvitation>(predicate: #Predicate { $0.id == invitationID })
        )
        let membershipID = membership.id
        let storedMemberships = try context.fetch(
            FetchDescriptor<FamilyMembership>(predicate: #Predicate { $0.id == membershipID })
        )
        guard storedInvitations.count == 1, let invitation = storedInvitations.first,
              invitation.familyID == familyID,
              invitation.status == .accepted,
              invitation.roleRawValue == authorization.roleRawValue,
              invitation.familyMemberID == authorization.familyMemberID,
              storedMemberships.count == 1, let storedMembership = storedMemberships.first,
              storedMembership.familyID == familyID,
              storedMembership.appleID == authorization.appleID,
              storedMembership.roleRawValue == authorization.roleRawValue,
              storedMembership.familyMemberID == member.id else {
            throw FamilySharingError.notAuthorized
        }
    }

    @discardableResult
    func performProtectedMutation<T>(
        session: MutationSession,
        _ mutation: () throws -> T
    ) throws -> T {
        let intent = try prepareProtectedMutationPublication(session: session)
        do {
            let result = try mutation()
            commitProtectedMutationPublication(intent, session: session)
            return result
        } catch {
            rollbackProtectedMutationPublication(intent)
            throw error
        }
    }

    func publishAfterProtectedMutation(session: MutationSession) {
        do {
            let intent = try prepareProtectedMutationPublication(session: session)
            commitProtectedMutationPublication(intent, session: session)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func schedulePendingPublication(familyID: UUID, session: MutationSession) {
        pendingPublishTasks[familyID]?.cancel()
        let token = UUID()
        pendingPublishTokens[familyID] = token
        pendingPublishTasks[familyID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if pendingPublishTokens[familyID] == token {
                    pendingPublishTasks[familyID] = nil
                    pendingPublishTokens[familyID] = nil
                }
            }
            do {
                try await Task.sleep(for: publicationDelay)
                try Task.checkCancellation()
                try await retryPendingPublication(session: session)
                lastError = nil
            } catch is CancellationError {
                return
            } catch FamilySharingError.familyNotPublished {
                // A local-only family remains dirty until an administrator creates a share.
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func synchronize(session: MutationSession) async throws {
        _ = try await fetchSharedFamilies(session: session)
        do {
            try await retryPendingPublication(session: session)
        } catch FamilySharingError.familyNotPublished {
            // A local-only family remains dirty until an administrator creates a share.
        }
    }

    func hasConflict(for familyID: UUID?) -> Bool {
        familyID.map(conflictingFamilyIDs.contains) == true
    }

    func resolveConflictKeepingLocal(session: MutationSession) async throws {
        guard let context = modelContainer?.mainContext else {
            throw FamilySharingError.missingPayload
        }
        let family = try authorize(session: session, requireAdministrator: false)
        guard let fetched = pendingConflicts[family.id] else {
            throw FamilySharingError.missingPayload
        }
        let remote = try FamilyShareStore.decodeAndValidate(fetched.data)
        guard remote.familyID == family.id,
              Self.isEligible(payload: remote, session: session, signedInAppleID: nil, invitationCode: nil) else {
            throw FamilySharingError.unauthorizedSharedFamily
        }
        let localPayload = try FamilyShareStore.export(family: family, from: context)
        let publishedGeneration = FamilySharePublicationState.markDirty(familyID: family.id)
        try await perform {
            try await transport.resolveConflictKeepingLocal(fetched, payload: localPayload)
        }
        FamilyShareBaseline.remember(payload: localPayload, familyID: family.id)
        FamilySharePublicationState.clearDirtyIfCurrent(
            familyID: family.id,
            publishedGeneration: publishedGeneration
        )
        clearConflict(familyID: family.id)
    }

    func resolveConflictUsingCloudCopy(session: MutationSession) async throws {
        guard Self.isValidFetchSession(session),
              let family = session.family,
              let fetched = pendingConflicts[family.id],
              let context = modelContainer?.mainContext else {
            throw FamilySharingError.notAuthorized
        }
        let resolvingGeneration = FamilySharePublicationState.dirtyIntent(familyID: family.id)?.generation
        let remote = try FamilyShareStore.decodeAndValidate(fetched.data)
        guard remote.familyID == fetched.familyID,
              remote.familyID == family.id,
              Self.isEligible(payload: remote, session: session, signedInAppleID: nil, invitationCode: nil) else {
            throw FamilySharingError.unauthorizedSharedFamily
        }
        try await perform {
            let canonicalRemoteData = try FamilyShareStore.replaceWithRemoteCopy(fetched.data, into: context)
            do {
                try await transport.acknowledgeFetchedPayload(fetched)
            } catch {
                FamilySharePublicationState.markDirty(familyID: family.id)
                throw error
            }
            FamilyShareBaseline.remember(payload: canonicalRemoteData, familyID: family.id)
        }
        FamilySharePublicationState.clearDirtyIfCurrent(
            familyID: family.id,
            publishedGeneration: resolvingGeneration
        )
        clearConflict(familyID: family.id)
    }

    private func clearConflict(familyID: UUID) {
        pendingConflicts[familyID] = nil
        conflictingFamilyIDs.remove(familyID)
    }

    @discardableResult
    func fetchSharedFamilies(
        session: MutationSession? = nil,
        signedInAppleID: String? = nil,
        invitationCode: String? = nil
    ) async throws -> [UUID] {
        let normalizedAppleID = signedInAppleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInvitationCode = invitationCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidFetchSession(session) ||
                normalizedAppleID?.isEmpty == false || normalizedInvitationCode?.isEmpty == false else {
            throw FamilySharingError.notAuthorized
        }
        guard let context = modelContainer?.mainContext else {
            throw FamilySharingError.missingPayload
        }
        return try await perform {
            let fetchedPayloads = try await transport.fetchSharedPayloads()
            var imported: [UUID] = []
            for fetched in fetchedPayloads {
                let payload = try FamilyShareStore.decodeAndValidate(fetched.data)
                guard payload.familyID == fetched.familyID else {
                    throw FamilySharingError.fetchedRecordMismatch
                }
                guard Self.isEligible(
                    payload: payload,
                    session: session,
                    signedInAppleID: normalizedAppleID,
                    invitationCode: normalizedInvitationCode
                ) else {
                    continue
                }
                do {
                    let familyID = try FamilyShareStore.importPayload(fetched.data, into: context)
                    try await transport.acknowledgeFetchedPayload(fetched)
                    clearConflict(familyID: familyID)
                    imported.append(familyID)
                } catch FamilySharingError.localAndRemoteChangesConflict {
                    pendingConflicts[fetched.familyID] = fetched
                    conflictingFamilyIDs.insert(fetched.familyID)
                    throw FamilySharingError.localAndRemoteChangesConflict
                }
            }
            return imported
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await perform { try await transport.accept(metadata) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func isEligible(
        payload: FamilySharePayload,
        session: MutationSession?,
        signedInAppleID: String?,
        invitationCode: String?
    ) -> Bool {
        if isValidFetchSession(session),
           let session, let family = session.family, let membership = session.membership {
            return payload.familyID == family.id && payload.memberships.contains {
                $0.id == membership.id && $0.familyID == family.id &&
                    $0.familyMemberID == membership.familyMemberID &&
                    $0.appleID == membership.appleID && $0.roleRawValue == membership.roleRawValue
            }
        }
        if let appleID = signedInAppleID,
           payload.memberships.contains(where: { $0.appleID == appleID }) {
            return true
        }
        if let invitationCode {
            return payload.invitations.contains {
                $0.code.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(invitationCode) == .orderedSame &&
                    $0.statusRawValue == InvitationStatus.pending.rawValue &&
                    $0.expiresAt.map { $0 > Date.now } != false
            }
        }
        return false
    }

    private static func isValidFetchSession(_ session: MutationSession?) -> Bool {
        guard let session, let appleID = session.appleID,
              let family = session.family, let membership = session.membership, let member = session.member,
              family.isActive, member.isActive,
              membership.appleID == appleID, membership.familyID == family.id,
              member.familyID == family.id, membership.familyMemberID == member.id,
              membership.role.isCompatible(with: member.role) else {
            return false
        }
        return true
    }

    private func authorize(session: MutationSession, requireAdministrator: Bool) throws -> AllowanceFamily {
        guard let appleID = session.appleID,
              let family = session.family,
              let membership = session.membership,
              let member = session.member,
              family.isActive,
              membership.appleID == appleID,
              membership.familyID == family.id,
              member.familyID == family.id,
              membership.familyMemberID == member.id,
              member.isActive,
              membership.role != .viewer,
              membership.role.profileRole == member.role,
              !requireAdministrator || membership.role.canAdministerFamily else {
            throw FamilySharingError.notAuthorized
        }
        return family
    }

    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        while isSynchronizing {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
        }
        isSynchronizing = true
        defer { isSynchronizing = false }
        do {
            let value = try await operation()
            lastError = nil
            return value
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}

final class CloudKitFamilyShareTransport: FamilyShareTransport {
    static let containerIdentifier = "iCloud.com.jeffreysutherland.jembtfamilypointstracker"
    private let container: CKContainer

    init(container: CKContainer = CKContainer(identifier: containerIdentifier)) {
        self.container = container
    }

    func createShare(familyID: UUID, familyName: String, payload: Data) async throws -> FamilyShareHandle {
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: "Family-\(familyID.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let recordID = CKRecord.ID(recordName: familyID.uuidString, zoneID: zoneID)

        if let existingRecord = try? await database.record(for: recordID),
           let shareReference = existingRecord.share,
           let existingShare = try await database.record(for: shareReference.recordID) as? CKShare {
            try requireCurrentChangeTag(for: existingRecord, familyID: familyID)
            let assetURL = try apply(payload: payload, familyID: familyID, to: existingRecord)
            defer { try? FileManager.default.removeItem(at: assetURL) }
            let result = try await database.modifyRecords(
                saving: [existingRecord],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            guard let savedRecord = try result.saveResults[recordID]?.get() else {
                throw FamilySharingError.missingPayload
            }
            rememberChangeTag(savedRecord.recordChangeTag, familyID: familyID)
            return FamilyShareHandle(share: existingShare, container: container)
        }

        let record = CKRecord(recordType: "SharedFamily", recordID: recordID)
        let assetURL = try apply(payload: payload, familyID: familyID, to: record)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = familyName as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.jembt.family-points.family" as CKRecordValue
        share.publicPermission = .none
        let result = try await database.modifyRecords(
            saving: [record, share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard let savedRecord = try result.saveResults[record.recordID]?.get(),
              let savedShare = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw FamilySharingError.missingPayload
        }
        rememberChangeTag(savedRecord.recordChangeTag, familyID: familyID)
        return FamilyShareHandle(share: savedShare, container: container)
    }

    func publish(familyID: UUID, payload: Data) async throws {
        for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            for zone in try await database.allRecordZones()
                where zone.zoneID.zoneName == "Family-\(familyID.uuidString)" {
                let id = CKRecord.ID(recordName: familyID.uuidString, zoneID: zone.zoneID)
                do {
                    let record = try await database.record(for: id)
                    try requireCurrentChangeTag(for: record, familyID: familyID)
                    let assetURL = try apply(payload: payload, familyID: familyID, to: record)
                    defer { try? FileManager.default.removeItem(at: assetURL) }
                    let result = try await database.modifyRecords(
                        saving: [record],
                        deleting: [],
                        savePolicy: .ifServerRecordUnchanged,
                        atomically: true
                    )
                    guard let saved = try result.saveResults[id]?.get() else {
                        throw FamilySharingError.missingPayload
                    }
                    rememberChangeTag(saved.recordChangeTag, familyID: familyID)
                    return
                } catch let error as CKError where error.code == .serverRecordChanged {
                    throw FamilySharingError.conflictingChange
                }
            }
        }
        throw FamilySharingError.familyNotPublished
    }

    func resolveConflictKeepingLocal(_ fetched: FetchedFamilySharePayload, payload: Data) async throws {
        let familyID = fetched.familyID
        for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            for zone in try await database.allRecordZones()
                where zone.zoneID.zoneName == "Family-\(familyID.uuidString)" {
                let id = CKRecord.ID(recordName: familyID.uuidString, zoneID: zone.zoneID)
                do {
                    let record = try await database.record(for: id)
                    guard record.recordChangeTag == fetched.changeTag else {
                        throw FamilySharingError.conflictingChange
                    }
                    let assetURL = try apply(payload: payload, familyID: familyID, to: record)
                    defer { try? FileManager.default.removeItem(at: assetURL) }
                    let result = try await database.modifyRecords(
                        saving: [record], deleting: [],
                        savePolicy: .ifServerRecordUnchanged, atomically: true
                    )
                    guard let saved = try result.saveResults[id]?.get() else {
                        throw FamilySharingError.missingPayload
                    }
                    rememberChangeTag(saved.recordChangeTag, familyID: familyID)
                    return
                } catch let error as CKError where error.code == .serverRecordChanged {
                    throw FamilySharingError.conflictingChange
                }
            }
        }
        throw FamilySharingError.familyNotPublished
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        try await withCheckedThrowingContinuation { continuation in
            operation.acceptSharesResultBlock = { continuation.resume(with: $0) }
            container.add(operation)
        }
    }

    func fetchSharedPayloads() async throws -> [FetchedFamilySharePayload] {
        var payloadsByFamily: [UUID: FetchedFamilySharePayload] = [:]
        for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            for zone in try await database.allRecordZones()
                where zone.zoneID.zoneName.hasPrefix("Family-") {
                let recordName = String(zone.zoneID.zoneName.dropFirst("Family-".count))
                guard let familyID = UUID(uuidString: recordName) else { continue }
                let recordID = CKRecord.ID(recordName: familyID.uuidString, zoneID: zone.zoneID)
                let record = try await database.record(for: recordID)
                guard record.recordType == "SharedFamily",
                      record["familyID"] as? String == familyID.uuidString,
                      record["schemaVersion"] as? Int64 == Int64(FamilySharePayload.currentSchemaVersion) else {
                    throw FamilySharingError.fetchedRecordMismatch
                }
                guard let asset = record["payload"] as? CKAsset,
                      let url = asset.fileURL,
                      FileManager.default.fileExists(atPath: url.path) else {
                    throw FamilySharingError.missingPayload
                }
                payloadsByFamily[familyID] = FetchedFamilySharePayload(
                    familyID: familyID,
                    data: try Data(contentsOf: url),
                    changeTag: record.recordChangeTag
                )
            }
        }
        return payloadsByFamily.keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { payloadsByFamily[$0] }
    }

    func acknowledgeFetchedPayload(_ payload: FetchedFamilySharePayload) async throws {
        rememberChangeTag(payload.changeTag, familyID: payload.familyID)
    }

    private func requireCurrentChangeTag(for record: CKRecord, familyID: UUID) throws {
        guard rememberedChangeTag(familyID: familyID) == record.recordChangeTag else {
            throw FamilySharingError.conflictingChange
        }
    }

    private func rememberedChangeTag(familyID: UUID) -> String? {
        UserDefaults.standard.string(forKey: "FamilyShareChangeTag.\(familyID.uuidString)")
    }

    private func rememberChangeTag(_ tag: String?, familyID: UUID) {
        UserDefaults.standard.set(tag, forKey: "FamilyShareChangeTag.\(familyID.uuidString)")
    }

    @discardableResult
    private func apply(payload: Data, familyID: UUID, to record: CKRecord) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("family-\(familyID.uuidString)-\(UUID().uuidString).json")
        try payload.write(to: url, options: .atomic)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FamilySharingError.missingPayload
        }
        record["familyID"] = familyID.uuidString as CKRecordValue
        record["schemaVersion"] = FamilySharePayload.currentSchemaVersion as CKRecordValue
        record["payload"] = CKAsset(fileURL: url)
        return url
    }
}

@MainActor
enum FamilyShareStore {
    static func export(family: AllowanceFamily, from context: ModelContext) throws -> Data {
        let familyID = family.id
        let members = try context.fetch(FetchDescriptor<FamilyMember>())
            .filter { $0.familyID == familyID }
            .sorted(by: idOrder)
        let memberIDs = Set(members.map(\.id))
        let rules = try context.fetch(FetchDescriptor<RuleTemplate>())
            .filter { $0.familyID == familyID }
            .sorted(by: idOrder)
        let ruleIDs = Set(rules.map(\.id))
        let payload = FamilySharePayload(
            family: FamilyDTO(family),
            invitations: try context.fetch(FetchDescriptor<FamilyInvitation>())
                .filter { $0.familyID == familyID }.sorted(by: idOrder).map(InvitationDTO.init),
            memberships: try context.fetch(FetchDescriptor<FamilyMembership>())
                .filter { $0.familyID == familyID }.sorted(by: idOrder).map(MembershipDTO.init),
            members: members.map(MemberDTO.init),
            rules: rules.map { RuleDTO($0, familyID: familyID) },
            riders: try context.fetch(FetchDescriptor<RuleRider>())
                .filter { ruleIDs.contains($0.ruleID) }.sorted(by: idOrder).map(RiderDTO.init),
            entries: try context.fetch(FetchDescriptor<LedgerEntry>())
                .filter { memberIDs.contains($0.memberID) }.sorted(by: idOrder).map(EntryDTO.init),
            settlements: try context.fetch(FetchDescriptor<WeeklySettlement>())
                .filter { memberIDs.contains($0.childID) }.sorted(by: idOrder).map(SettlementDTO.init)
        )
        try payload.validate()
        let data = try JSONEncoder.familyShare.encode(payload)
        guard data.count <= FamilySharePayload.maximumEncodedBytes else {
            throw FamilySharingError.payloadTooLarge
        }
        return data
    }

    static func decodeAndValidate(_ data: Data) throws -> FamilySharePayload {
        guard data.count <= FamilySharePayload.maximumEncodedBytes else {
            throw FamilySharingError.payloadTooLarge
        }
        let payload: FamilySharePayload
        do {
            payload = try JSONDecoder.familyShare.decode(FamilySharePayload.self, from: data)
        } catch {
            throw FamilySharingError.invalidPayload
        }
        try payload.validate()
        return payload
    }

    static func importPayload(_ data: Data, into context: ModelContext) throws -> UUID {
        let payload = try decodeAndValidate(data)
        let canonicalRemoteData = try JSONEncoder.familyShare.encode(payload)
        let snapshot = try LocalSnapshot(context: context)
        try snapshot.validateNoForeignCollisions(with: payload)

        if let localFamily = snapshot.families.first(where: { $0.id == payload.familyID }) {
            let localData = try export(family: localFamily, from: context)
            let localFingerprint = FamilyShareBaseline.fingerprint(localData)
            let remoteFingerprint = FamilyShareBaseline.fingerprint(canonicalRemoteData)
            if let baseline = FamilyShareBaseline.fingerprint(familyID: payload.familyID) {
                let localChanged = localFingerprint != baseline
                let remoteChanged = remoteFingerprint != baseline
                if localChanged && remoteChanged && localFingerprint != remoteFingerprint {
                    throw FamilySharingError.localAndRemoteChangesConflict
                }
                if localChanged && !remoteChanged {
                    return payload.familyID
                }
            } else if localFingerprint != remoteFingerprint {
                throw FamilySharingError.localAndRemoteChangesConflict
            }
        }

        do {
            try upsert(payload, into: context, snapshot: snapshot)
            reconcileLocalFamily(with: payload, in: context, snapshot: snapshot)
            try context.save()
            FamilyShareBaseline.remember(payload: canonicalRemoteData, familyID: payload.familyID)
            return payload.familyID
        } catch {
            context.rollback()
            throw error
        }
    }

    static func replaceWithRemoteCopy(_ data: Data, into context: ModelContext) throws -> Data {
        let payload = try decodeAndValidate(data)
        let canonicalRemoteData = try JSONEncoder.familyShare.encode(payload)
        let snapshot = try LocalSnapshot(context: context)
        try snapshot.validateNoForeignCollisions(with: payload)
        do {
            try upsert(payload, into: context, snapshot: snapshot)
            reconcileLocalFamily(with: payload, in: context, snapshot: snapshot)
            try context.save()
            return canonicalRemoteData
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func reconcileLocalFamily(
        with payload: FamilySharePayload,
        in context: ModelContext,
        snapshot: LocalSnapshot
    ) {
        let familyID = payload.familyID
        let memberIDs = Set(snapshot.members.filter { $0.familyID == familyID }.map(\.id))
        let ruleIDs = Set(snapshot.rules.filter { $0.familyID == familyID }.map(\.id))
        let retainedMembers = Set(payload.members.map(\.id))
        let retainedRules = Set(payload.rules.map(\.id))
        let retainedInvitations = Set(payload.invitations.map(\.id))
        let retainedMemberships = Set(payload.memberships.map(\.id))
        let retainedRiders = Set(payload.riders.map(\.id))
        let retainedEntries = Set(payload.entries.map(\.id))
        let retainedSettlements = Set(payload.settlements.map(\.id))

        snapshot.invitations.filter {
            $0.familyID == familyID && !retainedInvitations.contains($0.id)
        }.forEach(context.delete)
        snapshot.memberships.filter {
            $0.familyID == familyID && !retainedMemberships.contains($0.id)
        }.forEach(context.delete)
        snapshot.riders.filter {
            ruleIDs.contains($0.ruleID) && !retainedRiders.contains($0.id)
        }.forEach(context.delete)
        snapshot.entries.filter {
            memberIDs.contains($0.memberID) && !retainedEntries.contains($0.id)
        }.forEach(context.delete)
        snapshot.settlements.filter {
            memberIDs.contains($0.childID) && !retainedSettlements.contains($0.id)
        }.forEach(context.delete)
        snapshot.rules.filter {
            $0.familyID == familyID && !retainedRules.contains($0.id)
        }.forEach(context.delete)
        snapshot.members.filter {
            $0.familyID == familyID && !retainedMembers.contains($0.id)
        }.forEach(context.delete)
    }

    private static func upsert(
        _ payload: FamilySharePayload,
        into context: ModelContext,
        snapshot: LocalSnapshot
    ) throws {
        if let value = snapshot.families.first(where: { $0.id == payload.family.id }) {
            value.name = payload.family.name
            value.createdAt = payload.family.createdAt
            value.createdByAppleID = payload.family.createdByAppleID
            value.isActive = payload.family.isActive
            value.cashValuePerPoint = payload.family.cashValuePerPoint
        } else {
            context.insert(AllowanceFamily(
                id: payload.family.id,
                name: payload.family.name,
                createdAt: payload.family.createdAt,
                createdByAppleID: payload.family.createdByAppleID,
                isActive: payload.family.isActive,
                cashValuePerPoint: payload.family.cashValuePerPoint ?? 0.01
            ))
        }

        for item in payload.members {
            if let value = snapshot.members.first(where: { $0.id == item.id }) {
                value.name = item.name
                value.emailAddress = item.emailAddress
                value.birthDate = item.birthDate
                value.sourceContactIdentifier = item.sourceContactIdentifier
                value.avatarData = item.avatarData
                value.roleRawValue = item.roleRawValue
                value.isActive = item.isActive
            } else {
                context.insert(FamilyMember(
                    id: item.id,
                    familyID: item.familyID,
                    name: item.name,
                    emailAddress: item.emailAddress,
                    birthDate: item.birthDate,
                    sourceContactIdentifier: item.sourceContactIdentifier,
                    avatarData: item.avatarData,
                    role: try required(MemberRole(rawValue: item.roleRawValue)),
                    isActive: item.isActive
                ))
            }
        }
        for item in payload.invitations {
            if let value = snapshot.invitations.first(where: { $0.id == item.id }) {
                value.familyMemberID = item.familyMemberID
                value.code = item.code
                value.roleRawValue = item.roleRawValue
                value.statusRawValue = item.statusRawValue
                value.createdAt = item.createdAt
                value.expiresAt = item.expiresAt
            } else {
                context.insert(FamilyInvitation(
                    id: item.id, familyID: item.familyID, familyMemberID: item.familyMemberID,
                    code: item.code, role: try required(FamilyMembershipRole(rawValue: item.roleRawValue)),
                    status: try required(InvitationStatus(rawValue: item.statusRawValue)),
                    createdAt: item.createdAt, expiresAt: item.expiresAt
                ))
            }
        }
        for item in payload.memberships {
            if let value = snapshot.memberships.first(where: { $0.id == item.id }) {
                value.familyMemberID = item.familyMemberID
                value.appleID = item.appleID
                value.roleRawValue = item.roleRawValue
                value.joinedAt = item.joinedAt
            } else {
                context.insert(FamilyMembership(
                    id: item.id, familyID: item.familyID, familyMemberID: item.familyMemberID,
                    appleID: item.appleID,
                    role: try required(FamilyMembershipRole(rawValue: item.roleRawValue)),
                    joinedAt: item.joinedAt
                ))
            }
        }
        for item in payload.rules {
            let existing = snapshot.rules.first(where: { $0.id == item.id })
            let isNew = existing == nil
            let value: RuleTemplate
            if let existing {
                value = existing
            } else {
                value = RuleTemplate(
                    id: item.id, familyID: item.familyID, title: item.title,
                    category: try required(RuleCategory(rawValue: item.categoryRawValue)),
                    kind: try required(EntryKind(rawValue: item.kindRawValue)),
                    defaultPoints: item.defaultPoints
                )
            }
            if isNew { context.insert(value) }
            value.title = item.title
            value.categoryRawValue = item.categoryRawValue
            value.kindRawValue = item.kindRawValue
            value.defaultPoints = item.defaultPoints
            value.guidance = item.guidance
            value.requiresApproval = item.requiresApproval
            value.isEnabled = item.isEnabled
            value.iconName = item.iconName
            value.measurementUnitRawValue = item.measurementUnitRawValue
            value.minimumTarget = item.minimumTarget
            value.maximumTarget = item.maximumTarget
            value.maximumPeriodRawValue = item.maximumPeriodRawValue
            value.warningUnits = item.warningUnits
            value.acceleratorEnabled = item.acceleratorEnabled
            value.acceleratorStartsAt = item.acceleratorStartsAt
            value.acceleratorMultiplier = item.acceleratorMultiplier
            value.frequencyKindRawValue = item.frequencyKindRawValue
            value.countScheduleRawValue = item.countScheduleRawValue
            value.frequencyValue = item.frequencyValue
            value.timeUnitRawValue = item.timeUnitRawValue
            value.growthEnabled = item.growthEnabled
            value.growthKindRawValue = item.growthKindRawValue
            value.growthAmount = item.growthAmount
            value.deductStartingPointsWhenMinimumMissed = item.deductStartingPointsWhenMinimumMissed
            value.minimumPeriodRawValue = item.minimumPeriodRawValue
            value.storeInventoryLimit = item.storeInventoryLimit
            value.storeInventoryPeriodRawValue = item.storeInventoryPeriodRawValue
            value.storeShelfPosition = item.storeShelfPosition
            value.minimumEligibleAge = item.minimumEligibleAge
            value.maximumEligibleAge = item.maximumEligibleAge
        }
        for item in payload.riders {
            if let value = snapshot.riders.first(where: { $0.id == item.id }) {
                value.title = item.title
                value.details = item.details
                value.multiplier = item.multiplier
            } else {
                context.insert(RuleRider(
                    id: item.id, ruleID: item.ruleID, title: item.title,
                    details: item.details, multiplier: item.multiplier
                ))
            }
        }
        for item in payload.entries {
            if let value = snapshot.entries.first(where: { $0.id == item.id }) {
                value.ruleID = item.ruleID
                value.occurredAt = item.occurredAt
                value.weekEnding = item.weekEnding
                value.title = item.title
                value.notes = item.notes
                value.points = item.points
                value.kindRawValue = item.kindRawValue
                value.statusRawValue = item.statusRawValue
                value.submittedBy = item.submittedBy
                value.reviewedBy = item.reviewedBy
                value.reviewedAt = item.reviewedAt
                value.quantity = item.quantity
                value.measurementUnitRawValue = item.measurementUnitRawValue
                value.riderTitle = item.riderTitle
            } else {
                context.insert(LedgerEntry(
                    id: item.id, memberID: item.memberID, ruleID: item.ruleID,
                    occurredAt: item.occurredAt, weekEnding: item.weekEnding,
                    title: item.title, notes: item.notes, points: item.points,
                    kind: try required(EntryKind(rawValue: item.kindRawValue)),
                    status: try required(ApprovalStatus(rawValue: item.statusRawValue)),
                    submittedBy: item.submittedBy, reviewedBy: item.reviewedBy,
                    reviewedAt: item.reviewedAt, quantity: item.quantity,
                    measurementUnit: try required(RuleMeasurementUnit(rawValue: item.measurementUnitRawValue)),
                    riderTitle: item.riderTitle
                ))
            }
        }
        for item in payload.settlements {
            if let value = snapshot.settlements.first(where: { $0.id == item.id }) {
                value.weekEnding = item.weekEnding
                value.startingPoints = item.startingPoints
                value.debtCarriedIn = item.debtCarriedIn
                value.approvedEntryPoints = item.approvedEntryPoints
                value.parentPotShare = item.parentPotShare
                value.minimumMissDeductionPoints = item.minimumMissDeductionPoints
                value.minimumMissDeductionDetails = item.minimumMissDeductionDetails
                value.minimumMissReviewDetails = item.minimumMissReviewDetails
                value.finalPoints = item.finalPoints
                value.cashAmount = item.cashAmount
                value.debtCarriedOut = item.debtCarriedOut
                value.confirmedAt = item.confirmedAt
                value.confirmedBy = item.confirmedBy
                value.transactionFingerprint = item.transactionFingerprint
            } else {
                context.insert(WeeklySettlement(
                    id: item.id, childID: item.childID, weekEnding: item.weekEnding,
                    startingPoints: item.startingPoints, debtCarriedIn: item.debtCarriedIn,
                    approvedEntryPoints: item.approvedEntryPoints, parentPotShare: item.parentPotShare,
                    minimumMissDeductionPoints: item.minimumMissDeductionPoints,
                    minimumMissDeductionDetails: item.minimumMissDeductionDetails,
                    minimumMissReviewDetails: item.minimumMissReviewDetails,
                    finalPoints: item.finalPoints, cashAmount: item.cashAmount,
                    debtCarriedOut: item.debtCarriedOut,
                    transactionFingerprint: item.transactionFingerprint,
                    confirmedAt: item.confirmedAt, confirmedBy: item.confirmedBy
                ))
            }
        }
    }

    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw FamilySharingError.invalidRawValue }
        return value
    }

    private static func idOrder<T: Identifiable>(_ lhs: T, _ rhs: T) -> Bool where T.ID == UUID {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private struct LocalSnapshot {
        let families: [AllowanceFamily]
        let invitations: [FamilyInvitation]
        let memberships: [FamilyMembership]
        let members: [FamilyMember]
        let rules: [RuleTemplate]
        let riders: [RuleRider]
        let entries: [LedgerEntry]
        let settlements: [WeeklySettlement]

        init(context: ModelContext) throws {
            families = try context.fetch(FetchDescriptor<AllowanceFamily>())
            invitations = try context.fetch(FetchDescriptor<FamilyInvitation>())
            memberships = try context.fetch(FetchDescriptor<FamilyMembership>())
            members = try context.fetch(FetchDescriptor<FamilyMember>())
            rules = try context.fetch(FetchDescriptor<RuleTemplate>())
            riders = try context.fetch(FetchDescriptor<RuleRider>())
            entries = try context.fetch(FetchDescriptor<LedgerEntry>())
            settlements = try context.fetch(FetchDescriptor<WeeklySettlement>())
        }

        func validateNoForeignCollisions(with payload: FamilySharePayload) throws {
            let hasCollision = payload.members.contains { item in
                members.first(where: { $0.id == item.id }).map { $0.familyID != item.familyID } == true
            } || payload.rules.contains { item in
                rules.first(where: { $0.id == item.id }).map { $0.familyID != item.familyID } == true
            } || payload.invitations.contains { item in
                invitations.first(where: { $0.id == item.id }).map { $0.familyID != item.familyID } == true
            } || payload.memberships.contains { item in
                memberships.first(where: { $0.id == item.id }).map { $0.familyID != item.familyID } == true
            } || payload.riders.contains { item in
                riders.first(where: { $0.id == item.id }).map { $0.ruleID != item.ruleID } == true
            } || payload.entries.contains { item in
                entries.first(where: { $0.id == item.id }).map { $0.memberID != item.memberID } == true
            } || payload.settlements.contains { item in
                settlements.first(where: { $0.id == item.id }).map { $0.childID != item.childID } == true
            }
            guard !hasCollision else { throw FamilySharingError.foreignIdentifierCollision }
        }
    }
}

enum FamilySharePublicationState {
    struct InvitationRedemptionAuthorization: Codable, Equatable {
        let invitationID: UUID
        let appleID: String
        let roleRawValue: String
        let familyMemberID: UUID?
    }

    enum Authorization: Codable, Equatable {
        case general
        case invitationRedemption(InvitationRedemptionAuthorization)
    }

    struct DirtyIntent: Codable, Equatable {
        let generation: Int
        let authorization: Authorization
    }

    private static let dirtyKeyPrefix = "FamilySharePublicationDirty."
    private static let intentKeyPrefix = "FamilySharePublicationIntent."
    private static let generationKeyPrefix = "FamilySharePublicationGeneration."

    static func isDirty(familyID: UUID) -> Bool {
        dirtyIntent(familyID: familyID) != nil
    }

    static func dirtyIntent(familyID: UUID) -> DirtyIntent? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: intentKeyPrefix + familyID.uuidString),
           let intent = try? JSONDecoder().decode(DirtyIntent.self, from: data) {
            return intent
        }
        guard defaults.bool(forKey: dirtyKeyPrefix + familyID.uuidString) else { return nil }
        let migrated = DirtyIntent(
            generation: max(1, defaults.integer(forKey: generationKeyPrefix + familyID.uuidString)),
            authorization: .general
        )
        persist(migrated, familyID: familyID)
        return migrated
    }

    @discardableResult
    static func markDirty(
        familyID: UUID,
        authorization: Authorization = .general
    ) -> Int {
        let defaults = UserDefaults.standard
        let generation = max(
            dirtyIntent(familyID: familyID)?.generation ?? 0,
            defaults.integer(forKey: generationKeyPrefix + familyID.uuidString)
        ) + 1
        defaults.set(generation, forKey: generationKeyPrefix + familyID.uuidString)
        persist(DirtyIntent(generation: generation, authorization: authorization), familyID: familyID)
        return generation
    }

    static func clearDirty(familyID: UUID) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dirtyKeyPrefix + familyID.uuidString)
        defaults.removeObject(forKey: intentKeyPrefix + familyID.uuidString)
    }

    static func clearDirtyIfCurrent(familyID: UUID, publishedGeneration: Int?) {
        guard dirtyIntent(familyID: familyID)?.generation == publishedGeneration else { return }
        clearDirty(familyID: familyID)
    }

    static func restoreDirty(
        familyID: UUID,
        replacingGeneration: Int,
        with previousIntent: DirtyIntent?
    ) {
        guard dirtyIntent(familyID: familyID)?.generation == replacingGeneration else { return }
        if let previousIntent {
            persist(previousIntent, familyID: familyID)
        } else {
            clearDirtyIfCurrent(familyID: familyID, publishedGeneration: replacingGeneration)
        }
    }

    private static func persist(_ intent: DirtyIntent, familyID: UUID) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: dirtyKeyPrefix + familyID.uuidString)
        defaults.set(data, forKey: intentKeyPrefix + familyID.uuidString)
    }
}

enum FamilyShareBaseline {
    private static let keyPrefix = "FamilySharePayloadFingerprint."

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(familyID: UUID) -> String? {
        UserDefaults.standard.string(forKey: keyPrefix + familyID.uuidString)
    }

    static func remember(payload: Data, familyID: UUID) {
        UserDefaults.standard.set(fingerprint(payload), forKey: keyPrefix + familyID.uuidString)
    }

    static func clear(familyID: UUID) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + familyID.uuidString)
    }
}

private extension JSONEncoder {
    static var familyShare: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var familyShare: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

final class FamilySharingAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await FamilySharingCoordinator.shared.accept(metadata)
        }
    }
}

struct CloudSharingControllerView: UIViewControllerRepresentable {
    let handle: FamilyShareHandle

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: handle.share, container: handle.container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}