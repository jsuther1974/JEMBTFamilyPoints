import AppIntents
import SwiftData

@MainActor
enum AppRuntimeDependencies {
    static weak var appleIDManager: AppleIDManager?
    static var modelContainer: ModelContainer?
}

enum PointMutationCommandError: LocalizedError, Equatable {
    case invalidAmount
    case memberNotFound
    case ambiguousMember
    case noEligibleRule(EntryKind)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Choose a nonzero point amount."
        case .memberNotFound:
            "No active family member with that name can receive points in the signed-in family."
        case .ambiguousMember:
            "More than one family member has that name. Use a more specific name."
        case .noEligibleRule(let kind):
            switch kind {
            case .reward:
                "No enabled reward rule is currently eligible for that family member."
            case .penalty:
                "No enabled penalty rule is currently eligible for that family member."
            default:
                "No enabled rule is currently eligible for that family member."
            }
        }
    }
}

@MainActor
enum PointMutationCommandService {
    static func recordPointMutation(
        memberName: String,
        pointsDelta: Int,
        now: Date = .now,
        appleIDManager: AppleIDManager,
        modelContext: ModelContext
    ) throws -> LedgerEntry {
        guard pointsDelta != 0 else {
            throw PointMutationCommandError.invalidAmount
        }
        guard let familyID = appleIDManager.currentFamily?.id else {
            throw ProtectedMutationError.missingSession
        }

        let normalizedName = memberName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let recipientCandidates = try modelContext.fetch(FetchDescriptor<FamilyMember>()).filter {
            $0.familyID == familyID &&
            $0.isActive &&
            $0.role.participatesInPoints &&
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedName
        }
        guard !recipientCandidates.isEmpty else {
            throw PointMutationCommandError.memberNotFound
        }
        guard recipientCandidates.count == 1, let recipient = recipientCandidates.first else {
            throw PointMutationCommandError.ambiguousMember
        }

        let kind: EntryKind = pointsDelta > 0 ? .reward : .penalty
        let weekEnding = PointsEngine.weekEnding(containing: now)
        let rule = try bestRule(
            for: recipient,
            familyID: familyID,
            kind: kind,
            weekEnding: weekEnding,
            modelContext: modelContext
        )

        let session = MutationSession(appleIDManager: appleIDManager)
        let approvalStatus = try ProtectedMutationPolicy.activityApprovalStatus(
            session: session,
            recipient: recipient,
            rule: rule,
            kind: kind
        )

        let submissionKind = ActivitySubmissionPolicy.submissionKind(
            member: appleIDManager.currentFamilyMember,
            membershipRole: appleIDManager.currentMembership?.role
        )
        let recorder = appleIDManager.currentFamilyMember?.name ?? submissionKind.submittedBy
        let entry = LedgerEntry(
            memberID: recipient.id,
            ruleID: rule.id,
            occurredAt: now,
            weekEnding: weekEnding,
            title: rule.title,
            points: pointsDelta,
            kind: kind,
            status: approvalStatus,
            submittedBy: recorder,
            reviewedBy: approvalStatus == .approved ? recorder : nil,
            reviewedAt: approvalStatus == .approved ? now : nil,
            quantity: rule.defaultEntryQuantity,
            measurementUnit: rule.measurementUnit
        )
        modelContext.insert(entry)

        do {
            try FamilySharingCoordinator.shared.performProtectedMutation(session: session) {
                try modelContext.save()
            }
            return entry
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func bestRule(
        for recipient: FamilyMember,
        familyID: UUID,
        kind: EntryKind,
        weekEnding: Date,
        modelContext: ModelContext
    ) throws -> RuleTemplate {
        let rule = try modelContext.fetch(FetchDescriptor<RuleTemplate>())
            .filter {
                $0.familyID == familyID &&
                $0.isEnabled &&
                $0.kind == kind &&
                $0.isEligible(for: recipient, at: weekEnding)
            }
            .sorted {
                let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleOrder == .orderedSame {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return titleOrder == .orderedAscending
            }
            .first

        guard let rule else {
            throw PointMutationCommandError.noEligibleRule(kind)
        }
        return rule
    }
}

enum PointMutationSemantic: String, AppEnum {
    case award
    case reward
    case penalty

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Point Label")

    static var caseDisplayRepresentations: [PointMutationSemantic: DisplayRepresentation] = [
        .award: DisplayRepresentation(title: "Award"),
        .reward: DisplayRepresentation(title: "Reward"),
        .penalty: DisplayRepresentation(title: "Penalty")
    ]

    var kind: EntryKind {
        switch self {
        case .award, .reward:
            .reward
        case .penalty:
            .penalty
        }
    }
}

struct FamilyPointMemberEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Family Member")
    static var defaultQuery = FamilyPointMemberEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(member: FamilyMember) {
        id = member.id
        name = member.name
    }
}

struct FamilyPointMemberEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [FamilyPointMemberEntity] {
        let members = try scopedPointParticipants()
            .filter { identifiers.contains($0.id) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return order == .orderedAscending
            }
        return members.map(FamilyPointMemberEntity.init(member:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [FamilyPointMemberEntity] {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matches = try scopedPointParticipants()
            .filter {
                $0.name
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains(normalized)
            }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return order == .orderedAscending
            }
        return matches.map(FamilyPointMemberEntity.init(member:))
    }

    @MainActor
    func suggestedEntities() async throws -> [FamilyPointMemberEntity] {
        try scopedPointParticipants()
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return order == .orderedAscending
            }
            .map(FamilyPointMemberEntity.init(member:))
    }

    @MainActor
    private func scopedPointParticipants() throws -> [FamilyMember] {
        guard let appleIDManager = AppRuntimeDependencies.appleIDManager,
              let modelContext = AppRuntimeDependencies.modelContainer?.mainContext,
              let familyID = appleIDManager.currentFamily?.id else {
            return []
        }

        return try modelContext.fetch(FetchDescriptor<FamilyMember>()).filter {
            $0.familyID == familyID &&
            $0.isActive &&
            $0.role.participatesInPoints
        }
    }
}

struct GivePointsIntent: AppIntent {
    static var title: LocalizedStringResource = "Give Points"
    static var description = IntentDescription("Give points or a penalty to a family member in the active signed-in family.")

    @Parameter(title: "Family Member")
    var member: FamilyPointMemberEntity

    @Parameter(title: "Points", default: 10)
    var points: Int

    @Parameter(title: "Label", default: .award)
    var semantic: PointMutationSemantic

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appleIDManager = AppRuntimeDependencies.appleIDManager,
              let modelContext = AppRuntimeDependencies.modelContainer?.mainContext else {
            throw ProtectedMutationError.missingSession
        }

        let magnitude = max(1, abs(points))
        let delta = semantic.kind == .reward ? magnitude : -magnitude
        let entry = try PointMutationCommandService.recordPointMutation(
            memberName: member.name,
            pointsDelta: delta,
            appleIDManager: appleIDManager,
            modelContext: modelContext
        )

        let action = entry.points >= 0 ? "Added" : "Deducted"
        return .result(dialog: IntentDialog("\(action) \(abs(entry.points)) points for \(member.name)."))
    }
}

struct TakePointsIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Points"
    static var description = IntentDescription("Deduct points from a family member in the active signed-in family.")

    @Parameter(title: "Family Member")
    var member: FamilyPointMemberEntity

    @Parameter(title: "Points", default: 10)
    var points: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appleIDManager = AppRuntimeDependencies.appleIDManager,
              let modelContext = AppRuntimeDependencies.modelContainer?.mainContext else {
            throw ProtectedMutationError.missingSession
        }

        let entry = try PointMutationCommandService.recordPointMutation(
            memberName: member.name,
            pointsDelta: -max(1, abs(points)),
            appleIDManager: appleIDManager,
            modelContext: modelContext
        )
        return .result(dialog: IntentDialog("Deducted \(abs(entry.points)) points from \(member.name)."))
    }
}

struct FamilyPointsMutationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GivePointsIntent(),
            phrases: [
                "Give points to \(\.$member) in \(.applicationName)",
                "Award \(\.$member) in \(.applicationName)"
            ],
            shortTitle: "Give Points",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: TakePointsIntent(),
            phrases: [
                "Take points from \(\.$member) in \(.applicationName)",
                "Remove points from \(\.$member) in \(.applicationName)"
            ],
            shortTitle: "Take Points",
            systemImageName: "minus.circle.fill"
        )
    }
}
