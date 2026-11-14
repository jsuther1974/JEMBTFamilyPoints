#if canImport(ContactsUI) && canImport(UIKit)
import ContactsUI
#endif
import SwiftData
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(ImagePlayground)
import ImagePlayground
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ManageFamilyView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(ReportingPeriod.self) private var reportingPeriod
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \FamilyInvitation.createdAt, order: .reverse) private var invitations: [FamilyInvitation]
    @Query private var entries: [LedgerEntry]
    @Query private var settlements: [WeeklySettlement]
    @Query private var rules: [RuleTemplate]
    @State private var showingFamilyNameEditor = false
    @State private var showingAddMember = false
    @State private var memberPendingRemoval: FamilyMember?
    @State private var inviteToPresentAfterAdd: PendingInviteShare?
    @State private var pendingInviteShare: PendingInviteShare?
    @State private var errorMessage: String?
    @State private var quickActivity: QuickActivityRequest?
    @State private var showingWeeklyLedger = false
    @State private var showingSettlement = false

    private var canEdit: Bool {
        appleIDManager.currentMembership?.role.canAdministerFamily == true
    }

    private var canChooseReportingPeriod: Bool {
        appleIDManager.currentMembership?.role.canManageRules == true
    }

    private var familyMembers: [FamilyMember] {
        guard let family = appleIDManager.currentFamily else { return [] }
        var visibleMembers = members.filter { $0.familyID == family.id && $0.isActive }
        if let currentMember = appleIDManager.currentFamilyMember,
           currentMember.isActive,
           !visibleMembers.contains(where: { $0.id == currentMember.id }) {
            visibleMembers.append(currentMember)
        }
        return visibleMembers.sorted(by: FamilyMember.comesBeforeInFamilyList)
    }

    private var weekEnding: Date {
        reportingPeriod.weekEnding
    }

    private var familyEntries: [LedgerEntry] {
        let memberIDs = Set(familyMembers.map(\.id))
        return entries.filter { memberIDs.contains($0.memberID) }
    }

    private var weeklyStandings: [SettlementDraft] {
        let memberIDs = Set(familyMembers.map(\.id))
        return PointsEngine.settlementDrafts(
            weekEnding: weekEnding,
            members: familyMembers,
            entries: familyEntries,
            settlements: settlements.filter { memberIDs.contains($0.childID) },
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id },
            cashValuePerPoint: appleIDManager.currentFamily?.effectiveCashValuePerPoint ?? Decimal(string: "0.01")!
        )
    }

    private var pendingApprovalCount: Int {
        familyEntries.count {
            $0.status == .pending &&
            Calendar.current.isDate($0.weekEnding, inSameDayAs: weekEnding)
        }
    }

    private var activePastWeekEndings: [Date] {
        PointsEngine.activePastWeekEndings(
            members: familyMembers,
            entries: familyEntries,
            settlements: settlements,
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id },
            cashValuePerPoint: appleIDManager.currentFamily?.effectiveCashValuePerPoint ?? Decimal(string: "0.01")!
        )
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if appleIDManager.currentFamilyMember == nil {
                Section {
                    Button("Restore my member profile") {
                        restoreCurrentProfileIfNeeded()
                    }
                } footer: {
                    Text("Use this only if your profile is missing after an older app-data migration.")
                }
            }

            if familyMembers.isEmpty {
                Section("Family members") {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.3",
                        description: Text(canEdit ? "Add your first family member." : "A family admin can add members.")
                    )
                }
            } else {
                memberSection(title: "Children", role: .child)
                memberSection(title: "Parents", role: .parent)
                memberSection(title: "Caregivers", role: .caregiver)
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            GeometryReader { proxy in
                Image("FamilyPageWallpaper")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay {
                        Rectangle()
                            .fill(.regularMaterial)
                    }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            familyOverviewBanner
        }
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    familyActionsMenu
                }
            }
        }
        .navigationDestination(isPresented: $showingWeeklyLedger) {
            WeeklyLedgerView()
        }
        .navigationDestination(isPresented: $showingSettlement) {
            SettlementView()
        }
        .sheet(isPresented: $showingFamilyNameEditor) {
            if let family = appleIDManager.currentFamily {
                FamilySettingsEditorView(
                    currentName: family.name,
                    currentCashValuePerPoint: family.effectiveCashValuePerPoint
                ) { newName, cashValuePerPoint in
                    try saveFamilySettings(name: newName, cashValuePerPoint: cashValuePerPoint, for: family)
                }
            }
        }
        .sheet(item: $quickActivity) { request in
            QuickActivityView(member: request.member, kind: request.kind, weekEnding: request.weekEnding)
        }
        .sheet(isPresented: $showingAddMember, onDismiss: presentPendingInvite) {
            MemberEditorView(title: "Add Family Member") { draft in
                try addMember(draft)
            }
        }
        .sheet(item: $pendingInviteShare) { invite in
            InviteShareSheet(invite: invite)
        }
        .confirmationDialog(
            "Remove family member?",
            isPresented: Binding(
                get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let memberPendingRemoval {
                    deactivate(memberPendingRemoval)
                }
                memberPendingRemoval = nil
            }
        } message: {
            Text("This removes the profile from active use but keeps its historical points records.")
        }
        .task(id: appleIDManager.currentMembership?.id) {
            restoreCurrentProfileIfNeeded()
        }
        .onAppear {
            restoreCurrentProfileIfNeeded()
        }
    }

    private var familyOverviewBanner: some View {
        HStack(spacing: 8) {
            Image("FamilyPageWallpaper")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            Text(displayedFamilyName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .accessibilityIdentifier("familyNameHeading")

            ReportingWeekPicker(isCompact: true)
                .frame(maxWidth: 170)

            Button {
                showingWeeklyLedger = true
            } label: {
                Image(systemName: pendingApprovalCount == 0
                    ? "list.bullet.clipboard"
                    : "list.bullet.clipboard.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(
                pendingApprovalCount == 0
                    ? "Weekly Ledger"
                    : "Weekly Ledger, \(pendingApprovalCount) waiting"
            )
            .accessibilityIdentifier("weeklyLedgerLink")

            if canChooseReportingPeriod && !activePastWeekEndings.isEmpty {
                Button {
                    showingSettlement = true
                } label: {
                    Image(systemName: "checkmark.seal.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Review and Close")
                .accessibilityIdentifier("familySettlementLink")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .clipped()
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("familyOverviewBanner")
    }

    @ViewBuilder
    private func memberSection(title: String, role: MemberRole) -> some View {
        let roleMembers = familyMembers.filter { $0.role == role }
        if !roleMembers.isEmpty {
            Section(title) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 4) {
                        ForEach(roleMembers) { member in
                            MemberAdministrationRow(
                                member: member,
                                points: member.role.participatesInPoints ? pointsSummary(for: member) : nil,
                                invitation: pendingInvitation(for: member),
                                canEdit: canEdit,
                                isCurrentMember: member.id == appleIDManager.currentFamilyMember?.id,
                                onReward: member.role == .child
                                    ? { quickActivity = QuickActivityRequest(member: member, kind: .reward, weekEnding: weekEnding) }
                                    : nil,
                                onPenalty: member.role.participatesInPoints
                                    ? { quickActivity = QuickActivityRequest(member: member, kind: .penalty, weekEnding: weekEnding) }
                                    : nil,
                                onGenerateCode: { generateCode(for: member) },
                                onShareInvitation: { invitation in
                                    pendingInviteShare = PendingInviteShare(invitation: invitation, memberName: member.name)
                                },
                                onSave: { draft in try update(member, with: draft) }
                            )
                            .containerRelativeFrame(.horizontal) { length, _ in
                                min(620, length * 0.94)
                            }
                            .scrollTransition(.interactive.threshold(.visible(0.55))) { card, phase in
                                card
                                    .scaleEffect(phase.isIdentity ? 1 : 0.84)
                                    .opacity(phase.isIdentity ? 1 : 0.62)
                                    .rotation3DEffect(
                                        .degrees(phase.value * -4),
                                        axis: (x: 0, y: 1, z: 0),
                                        perspective: 0.3
                                    )
                            }
                            .contextMenu {
                                if canEdit {
                                    Button("Remove family member", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                                        memberPendingRemoval = member
                                    }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .contentMargins(.horizontal, 2, for: .scrollContent)
                .frame(height: 240)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 8, trailing: 14))
            }
        }
    }

    private var familyActionsMenu: some View {
        Menu {
            Button("Edit family settings", systemImage: "slider.horizontal.3") {
                showingFamilyNameEditor = true
            }
            Button("Add family member", systemImage: "person.badge.plus") {
                showingAddMember = true
            }
        } label: {
            Label("Family actions", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("familyActions")
    }

    private func pointsSummary(for member: FamilyMember) -> MemberPointsSummary {
        let approvedEntries = familyEntries.filter {
            $0.memberID == member.id &&
            $0.status == .approved &&
            Calendar.current.isDate($0.weekEnding, inSameDayAs: weekEnding)
        }
        let earned = approvedEntries.reduce(0) { $0 + max(0, $1.points) }
        let lost = approvedEntries.reduce(0) { $0 + abs(min(0, $1.points)) }
        let draft = weeklyStandings.first { $0.child.id == member.id }
        let confirmed = settlements.first {
            $0.childID == member.id &&
            Calendar.current.isDate($0.weekEnding, inSameDayAs: weekEnding)
        }
        let pending = PointsEngine.pendingPointTotals(
            for: member.id,
            weekEnding: weekEnding,
            entries: familyEntries
        )

        return MemberPointsSummary(
            balance: confirmed?.finalPoints ?? draft?.finalPoints,
            base: confirmed?.startingPoints ?? draft?.startingPoints,
            earned: earned,
            lost: lost,
            pendingCount: pending.count,
            pendingEarned: pending.earned,
            pendingLost: pending.lost,
            debt: confirmed?.debtCarriedIn ?? draft?.debtCarriedIn ?? 0,
            parentPotShare: confirmed?.parentPotShare ?? draft?.parentPotShare ?? 0
        )
    }

    private var displayedFamilyName: String {
        let name = appleIDManager.currentFamily?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "My Family" : name
    }

    private func saveFamilySettings(name: String, cashValuePerPoint: Decimal, for family: AllowanceFamily) throws {
        let previousName = family.name
        let previousCashValue = family.cashValuePerPoint
        family.name = name
        family.cashValuePerPoint = max(0, cashValuePerPoint)
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            family.name = previousName
            family.cashValuePerPoint = previousCashValue
            errorMessage = "The family settings could not be saved: \(error.localizedDescription)"
            throw error
        }
    }

    private func pendingInvitation(for member: FamilyMember) -> FamilyInvitation? {
        invitations.first {
            $0.familyMemberID == member.id &&
            $0.status == .pending &&
            ($0.expiresAt == nil || $0.expiresAt! > .now)
        }
    }

    private func addMember(_ draft: MemberDraft) throws {
        guard let family = appleIDManager.currentFamily else {
            throw ManageFamilyError.noSelectedFamily
        }
        let result = try appleIDManager.addFamilyMember(
            family: family,
            name: draft.name,
            emailAddress: draft.emailAddress,
            birthDate: draft.birthDate,
            sourceContactIdentifier: draft.sourceContactIdentifier,
            avatarData: draft.avatarData,
            role: draft.role,
            modelContext: modelContext
        )
        if let invitation = result.invitation {
            inviteToPresentAfterAdd = PendingInviteShare(
                invitation: invitation,
                memberName: result.member.name
            )
        }
        errorMessage = nil
    }

    private func presentPendingInvite() {
        pendingInviteShare = inviteToPresentAfterAdd
        inviteToPresentAfterAdd = nil
    }


private struct PendingInviteShare: Identifiable {
    let id: UUID
    let memberName: String
    let code: String
    let expiresAt: Date?

    init(invitation: FamilyInvitation, memberName: String) {
        self.id = invitation.id
        self.memberName = memberName
        self.code = invitation.code
        self.expiresAt = invitation.expiresAt
    }

    var invitationSubject: String {
        "Join our Family Points group"
    }

    var invitationMessage: String {
        "You've been invited to join our family in Family Points. Open the app and enter this invitation code: \(code)"
    }
}

private struct InviteShareSheet: View {
    let invite: PendingInviteShare
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Invite Ready")
                        .font(.headline)
                    Text("Share this code with \(invite.memberName).")
                        .foregroundStyle(.secondary)
                    if let expiresAt = invite.expiresAt {
                        Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Invitation code") {
                    Text(invite.code)
                        .font(.title3.monospaced().bold())
                        .textSelection(.enabled)
                }

                Section {
                    ShareLink(
                        item: invite.invitationMessage,
                        subject: Text(invite.invitationSubject),
                        message: Text(invite.invitationMessage)
                    ) {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        copyToPasteboard(invite.code)
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Send Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
    private func update(_ member: FamilyMember, with draft: MemberDraft) throws {
        try appleIDManager.updateFamilyMember(
            member,
            name: draft.name,
            emailAddress: draft.emailAddress,
            birthDate: draft.birthDate,
            avatarData: draft.avatarData,
            role: draft.role,
            modelContext: modelContext
        )
        errorMessage = nil
    }

    private func restoreCurrentProfileIfNeeded() {
        guard
            let membership = appleIDManager.currentMembership,
            let family = appleIDManager.currentFamily
        else { return }

        do {
            _ = try appleIDManager.ensureProfile(
                for: membership,
                in: family,
                defaultName: membership.role.title,
                modelContext: modelContext
            )
        } catch {
            errorMessage = "Your member profile could not be restored: \(error.localizedDescription)"
        }
    }

    private func deactivate(_ member: FamilyMember) {
        do {
            try appleIDManager.deactivateFamilyMember(member, modelContext: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = "The family member could not be removed: \(error.localizedDescription)"
        }
    }

    private func generateCode(for member: FamilyMember) {
        guard let family = appleIDManager.currentFamily else {
            errorMessage = "No family is selected."
            return
        }
        do {
            _ = try appleIDManager.createInvitation(
                for: family,
                role: FamilyMembershipRole(profileRole: member.role),
                familyMemberID: member.id,
                modelContext: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "The invitation code could not be created: \(error.localizedDescription)"
        }
    }
}

private struct MemberPointsSummary {
    let balance: Int?
    let base: Int?
    let earned: Int
    let lost: Int
    let pendingCount: Int
    let pendingEarned: Int
    let pendingLost: Int
    let debt: Int
    let parentPotShare: Int

    var net: Int { earned - lost }
}

private struct MemberAdministrationRow: View {
    let member: FamilyMember
    let points: MemberPointsSummary?
    let invitation: FamilyInvitation?
    let canEdit: Bool
    let isCurrentMember: Bool
    let onReward: (() -> Void)?
    let onPenalty: (() -> Void)?
    let onGenerateCode: () -> Void
    let onShareInvitation: (FamilyInvitation) -> Void
    let onSave: (MemberDraft) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                MemberDetailView(
                    member: member,
                    points: points,
                    invitation: invitation,
                    canEdit: canEdit,
                    isCurrentMember: isCurrentMember,
                    onSave: onSave
                )
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        MemberAvatarView(member: member, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.name).font(.headline)
                                if isCurrentMember {
                                    Text("ME")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(accentColor.opacity(0.18), in: Capsule())
                                        .accessibilityIdentifier("currentMemberBadge-\(member.name)")
                                }
                            }
                            Text(ageDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let birthdayDescription {
                                Text(birthdayDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let points {
                            Text("\((points.balance ?? points.net).formatted()) pts")
                                .font(.title3.bold())
                                .foregroundStyle(accentColor)
                        }
                    }

                    if let points {
                        if let base = points.base {
                            Text("Base \(base.formatted())  •  Earned +\(points.earned.formatted())  •  Lost -\(points.lost.formatted())")
                                .accessibilityIdentifier("pointsSummary-\(member.name)")
                        } else {
                            Text("Earned +\(points.earned.formatted())  •  Lost -\(points.lost.formatted())")
                                .accessibilityIdentifier("pointsSummary-\(member.name)")
                        }
                        if points.debt != 0 || points.parentPotShare != 0 {
                            Text("Debt \(points.debt.formatted())  •  Parent pot +\(points.parentPotShare.formatted())")
                        }
                        if points.pendingCount > 0 {
                            Label(
                                "Waiting approval: +\(points.pendingEarned.formatted()) earned  •  -\(points.pendingLost.formatted()) lost",
                                systemImage: "clock.fill"
                            )
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("pendingPoints-\(member.name)")
                        }
                    }

                    if let email = member.emailAddress, !email.isEmpty {
                        Label(email, systemImage: "envelope")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .font(.caption)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("memberCard-\(member.name)")
            .accessibilityValue(isCurrentMember ? "Current member" : "")

            if hasActions {
                Divider().overlay(accentColor.opacity(0.35))
                HStack(spacing: 12) {
                    if !isCurrentMember {
                        if let invitation {
                            Text("Invite: \(invitation.code)")
                                .font(.caption.monospaced().bold())
                            Button {
                                onShareInvitation(invitation)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body)
                            }
                            .accessibilityLabel("Share invitation for \(member.name)")
                        } else if canEdit {
                            Button("Create invite", action: onGenerateCode)
                                .font(.caption)
                                .accessibilityLabel("Create invitation for \(member.name)")
                        }
                    }
                    Spacer()
                    if let onReward {
                        Button(action: onReward) {
                            Image(systemName: EntryKind.reward.quickActionSymbolName)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.green)
                                .frame(width: 48, height: 44)
                                .background(.green.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reward \(member.name)")
                    }
                    if let onPenalty {
                        Button(action: onPenalty) {
                            Image(systemName: EntryKind.penalty.quickActionSymbolName)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 48, height: 44)
                                .background(.red.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Penalize \(member.name)")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 215, alignment: .topLeading)
        .familyCardSurface(accent: accentColor)
    }

    private var ageDescription: String {
        if let age = member.currentAge {
            return "Age \(age)"
        }
        return "No birthdate"
    }

    private var birthdayDescription: String? {
        guard member.role == .child,
              let days = PointsEngine.daysUntilNextBirthday(from: member.birthDate) else { return nil }
        return days == 0 ? "Birthday today" : "Birthday in \(days) \(days == 1 ? "day" : "days")"
    }

    private var accentColor: Color {
        switch member.role {
        case .child: .blue
        case .parent: .purple
        case .caregiver: .teal
        }
    }

    private var hasActions: Bool {
        onReward != nil || onPenalty != nil || (!isCurrentMember && (invitation != nil || canEdit))
    }

    private var invitationSubject: String {
        "You're invited to join our allowance family"
    }

    private func invitationMessage(_ invitation: FamilyInvitation) -> String {
        var lines = [
            invitationSubject,
            "",
            "Name: \(member.name)",
            "Role: \(member.role.title)"
        ]
        if let email = member.emailAddress, !email.isEmpty {
            lines.append("Email: \(email)")
        }
        if let birthDate = member.birthDate {
            lines.append("Birthdate: \(birthDate.formatted(date: .long, time: .omitted))")
        } else {
            lines.append("Birthdate: Not provided")
        }
        if let age = member.currentAge {
            lines.append("Age: \(age)")
        }
        lines.append("Status: \(member.isActive ? "Active" : "Inactive")")
        lines.append("")
        lines.append("Invitation code: \(invitation.code)")
        if let expiresAt = invitation.expiresAt {
            lines.append("Expires: \(expiresAt.formatted(date: .long, time: .shortened))")
        }
        lines.append("This invitation can be used once.")
        lines.append("")
        lines.append("Open the allowance app, sign in, choose to join a family, and enter the invitation code above.")
        return lines.joined(separator: "\n")
    }
}

private struct MemberDetailView: View {
    let member: FamilyMember
    let points: MemberPointsSummary?
    let invitation: FamilyInvitation?
    let canEdit: Bool
    let isCurrentMember: Bool
    let onSave: (MemberDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ReportingPeriod.self) private var reportingPeriod
    @Query private var entries: [LedgerEntry]
    @State private var showingEditor = false

    private var insights: MemberActivityInsights {
        StatisticsEngine.memberInsights(
            memberID: member.id,
            entries: entries,
            endingAt: reportingPeriod.weekEnding
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        MemberAvatarView(member: member, size: 124)
                            .accessibilityIdentifier("memberDetailAvatar-\(member.name)")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Profile") {
                    LabeledContent("Name", value: member.name)
                    if let email = member.emailAddress, !email.isEmpty {
                        LabeledContent("Email", value: email)
                    }
                    if let birthDate = member.birthDate {
                        LabeledContent("Birthdate", value: birthDate.formatted(date: .long, time: .omitted))
                    }
                    if let age = member.currentAge {
                        LabeledContent("Age", value: "Age \(age)")
                    }
                    if member.role == .child,
                       let days = PointsEngine.daysUntilNextBirthday(from: member.birthDate) {
                        LabeledContent(
                            "Next birthday",
                            value: days == 0 ? "Today" : "In \(days) \(days == 1 ? "day" : "days")"
                        )
                    }
                    if isCurrentMember {
                        Label("This is your profile", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.tint)
                    }
                }

                if let points {
                    Section("This week") {
                        LabeledContent("Current points", value: "\((points.balance ?? points.net).formatted())")
                        if let base = points.base {
                            LabeledContent("Starting points", value: "\(base.formatted())")
                        }
                        LabeledContent("Earned", value: "+\(points.earned.formatted())")
                        LabeledContent("Lost", value: "-\(points.lost.formatted())")
                        if points.pendingCount > 0 {
                            LabeledContent("Waiting approval", value: "\(points.pendingCount)")
                        }
                    }
                }

                if member.role == .child {
                    Section("Activity trends") {
                        LabeledContent("Active weeks", value: insights.activeWeeks.formatted())
                        LabeledContent("Average weekly net", value: formattedAverage(insights.averageWeeklyNet))
                        LabeledContent("Recent 4-week average", value: formattedAverage(insights.recentFourWeekAverage))
                        LabeledContent("Trend vs previous 4 weeks", value: formattedAverage(insights.trendFromPreviousFourWeeks))
                    }

                    Section("Last week") {
                        insightRow(label: "Top award", summary: insights.topAwardLastWeek, pointsPrefix: "+")
                        insightRow(label: "Largest loss", summary: insights.topPenaltyLastWeek, pointsPrefix: "-")
                    }

                    if !insights.frequentAwards.isEmpty {
                        Section("Most frequent awards") {
                            ForEach(insights.frequentAwards) { summary in
                                activitySummaryRow(summary, pointsPrefix: "+")
                            }
                        }
                    }

                    if !insights.frequentPurchases.isEmpty {
                        Section("Store favorites") {
                            ForEach(insights.frequentPurchases) { summary in
                                activitySummaryRow(summary, pointsPrefix: "-")
                            }
                        }
                    }
                }

                if !isCurrentMember, let invitation {
                    Section("Invitation") {
                        LabeledContent("Code", value: invitation.code)
                        if let expiresAt = invitation.expiresAt {
                            LabeledContent("Expires", value: expiresAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Edit") { showingEditor = true }
                            .accessibilityIdentifier("editMemberFromDetails")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                MemberEditorView(title: "Edit Family Member", member: member, onSave: onSave)
            }
        }
        .accessibilityIdentifier("memberDetails-\(member.name)")
    }

    @ViewBuilder
    private func insightRow(
        label: String,
        summary: MemberActivityItemSummary?,
        pointsPrefix: String
    ) -> some View {
        if let summary {
            LabeledContent(label) {
                Text("\(summary.title)  \(pointsPrefix)\(summary.points.formatted()) pts")
                    .multilineTextAlignment(.trailing)
            }
        } else {
            LabeledContent(label, value: "None")
        }
    }

    private func activitySummaryRow(
        _ summary: MemberActivityItemSummary,
        pointsPrefix: String
    ) -> some View {
        HStack {
            Text(summary.title)
            Spacer()
            Text("\(summary.count)×  •  \(pointsPrefix)\(summary.points.formatted()) pts")
                .foregroundStyle(.secondary)
        }
    }

    private func formattedAverage(_ value: Double) -> String {
        String(format: "%+.1f pts", value)
    }
}

struct QuickActivityRequest: Identifiable {
    let member: FamilyMember
    let kind: EntryKind
    let weekEnding: Date

    var id: String { "\(member.id.uuidString)-\(kind.rawValue)" }
}

private struct QuickActivityDraft {
    var quantity: Double
    var points: Int
    var pointsOverridden: Bool
    var weekdays: Set<Int>
}

struct QuickActivityView: View {
    let member: FamilyMember
    let kind: EntryKind
    let weekEnding: Date

    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RuleTemplate.title) private var allRules: [RuleTemplate]
    @Query private var entries: [LedgerEntry]
    @State private var drafts: [UUID: QuickActivityDraft] = [:]
    @State private var notes = ""
    @State private var isConfiguring = false
    @State private var errorMessage: String?

    init(member: FamilyMember, kind: EntryKind, weekEnding: Date) {
        self.member = member
        self.kind = kind
        self.weekEnding = weekEnding
    }

    private var catalog: RuleCatalog { kind == .reward ? .incentives : .disincentives }

    private var rules: [RuleTemplate] {
        allRules.filter {
            $0.familyID == appleIDManager.currentFamily?.id &&
            $0.isEnabled &&
            $0.catalog == catalog &&
            $0.isEligible(for: member, at: weekEnding)
        }
    }

    private var selectedRules: [RuleTemplate] {
        rules.filter { drafts[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isConfiguring {
                    Section {
                        Label(
                            "Adjust days, quantities, point overrides, and notes before saving.",
                            systemImage: "slider.horizontal.3"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    ForEach(selectedRules) { rule in
                        Section(rule.title) {
                            WeekdaySelector(
                                weekEnding: weekEnding,
                                selection: weekdaysBinding(for: rule),
                                identifierPrefix: "activityDay-\(rule.title)"
                            )
                            if rule.frequencyKind == .time || rule.countSchedule == .every {
                                LabeledContent(quantityTitle(for: rule)) {
                                    HStack(spacing: 6) {
                                        TextField("Quantity", value: quantityBinding(for: rule), format: .number)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 90)
                                            .accessibilityIdentifier("quickActivityQuantity-\(rule.title)")
                                        Text(quantityUnit(for: rule))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            LabeledContent(pointsLabel(for: rule)) {
                                HStack(spacing: 8) {
                                    TextField("Points", value: pointsBinding(for: rule), format: .number)
                                        .keyboardType(.numbersAndPunctuation)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 90)
                                        .accessibilityIdentifier("quickActivityPoints-\(rule.title)")
                                    Stepper("", value: pointsBinding(for: rule), in: pointRange)
                                        .labelsHidden()
                                }
                            }
                            if let total = assignmentTotal(for: rule), selectedDateCount(for: rule) > 1 {
                                LabeledContent("Assignment total") {
                                    Text(total, format: .number)
                                        .fontWeight(.semibold)
                                        .accessibilityIdentifier("quickActivityTotal-\(rule.title)")
                                }
                            }
                            if drafts[rule.id]?.pointsOverridden == true {
                                Button("Use calculated points") {
                                    resetCalculatedPoints(for: rule)
                                }
                                .font(.caption)
                            }
                            if !rule.guidance.isEmpty {
                                Text(rule.guidance)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("All selected entries") {
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("quickActivityNotes")
                    }
                } else {
                    Section {
                        ForEach(rules) { rule in
                            Button {
                                select(rule)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: rule.iconName)
                                        .foregroundStyle(kind == .reward ? .green : .red)
                                        .frame(width: 28)
                                    Text(rule.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if drafts[rule.id] != nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityIdentifier("quickRule-\(rule.title)")
                        }
                    } header: {
                        Text(kind == .reward ? "Choose awards" : "Choose penalties")
                    } footer: {
                        Text("Select one or more items. Save immediately with the defaults, or configure days, quantities, points, and notes below.")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isConfiguring && !selectedRules.isEmpty {
                    Button {
                        isConfiguring = true
                    } label: {
                        Label(
                            "Configure \(selectedRules.count) selected \(selectedRules.count == 1 ? "item" : "items")",
                            systemImage: "slider.horizontal.3"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .accessibilityIdentifier("configureSelectedActivities")
                }
            }
            .navigationTitle("\(kind == .reward ? "Award" : "Penalty") • \(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isConfiguring ? "Back" : "Cancel") {
                        if isConfiguring { isConfiguring = false }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(selectedRules.isEmpty || selectedRules.contains { drafts[$0.id]?.weekdays.isEmpty != false })
                }
            }
        }
    }

    private var pointRange: ClosedRange<Int> {
        kind == .reward ? 0...10_000 : -10_000...0
    }

    private func select(_ rule: RuleTemplate) {
        if drafts.removeValue(forKey: rule.id) != nil {
            errorMessage = nil
            return
        }

        let quantity = rule.defaultEntryQuantity
        drafts[rule.id] = QuickActivityDraft(
            quantity: quantity,
            points: calculatedPoints(for: rule, quantity: quantity),
            pointsOverridden: false,
            weekdays: [PointsEngine.defaultWeekday(inWeekEnding: weekEnding)]
        )
        errorMessage = nil
    }

    private func quantityBinding(for rule: RuleTemplate) -> Binding<Double> {
        Binding(
            get: { drafts[rule.id]?.quantity ?? rule.defaultEntryQuantity },
            set: { quantity in
                let quantity = max(1, quantity)
                drafts[rule.id] = QuickActivityDraft(
                    quantity: quantity,
                    points: calculatedPoints(for: rule, quantity: quantity),
                    pointsOverridden: false,
                    weekdays: drafts[rule.id]?.weekdays ?? [PointsEngine.defaultWeekday(inWeekEnding: weekEnding)]
                )
            }
        )
    }

    private func pointsBinding(for rule: RuleTemplate) -> Binding<Int> {
        Binding(
            get: { drafts[rule.id]?.points ?? 0 },
            set: { points in
                guard var draft = drafts[rule.id] else { return }
                draft.points = min(max(points, pointRange.lowerBound), pointRange.upperBound)
                draft.pointsOverridden = true
                drafts[rule.id] = draft
            }
        )
    }

    private func weekdaysBinding(for rule: RuleTemplate) -> Binding<Set<Int>> {
        Binding(
            get: { drafts[rule.id]?.weekdays ?? [] },
            set: { weekdays in
                guard var draft = drafts[rule.id] else { return }
                draft.weekdays = weekdays
                drafts[rule.id] = draft
                if !draft.pointsOverridden {
                    resetCalculatedPoints(for: rule)
                }
            }
        )
    }

    private func quantityTitle(for rule: RuleTemplate) -> String {
        rule.frequencyKind == .time ? "Duration" : "Quantity"
    }

    private func quantityUnit(for rule: RuleTemplate) -> String {
        let quantity = drafts[rule.id]?.quantity ?? rule.defaultEntryQuantity
        return rule.frequencyKind == .time
            ? rule.timeUnit.label(for: quantity)
            : rule.measurementUnit.label(for: quantity)
    }

    private func resetCalculatedPoints(for rule: RuleTemplate) {
        guard var draft = drafts[rule.id] else { return }
        draft.points = calculatedPoints(for: rule, quantity: draft.quantity)
        draft.pointsOverridden = false
        drafts[rule.id] = draft
    }

    private func calculatedPoints(for rule: RuleTemplate, quantity: Double) -> Int {
        pointAllocations(for: rule, quantity: quantity).first ?? 0
    }

    private func selectedDates(for rule: RuleTemplate) -> [Date] {
        let weekdays = drafts[rule.id]?.weekdays ?? [PointsEngine.defaultWeekday(inWeekEnding: weekEnding)]
        return PointsEngine.dates(inWeekEnding: weekEnding, matchingWeekdays: weekdays)
    }

    private func selectedDateCount(for rule: RuleTemplate) -> Int {
        selectedDates(for: rule).count
    }

    private func pointsLabel(for rule: RuleTemplate) -> String {
        guard selectedDateCount(for: rule) > 1 else { return "Points" }
        return drafts[rule.id]?.pointsOverridden == true ? "Points per day" : "First day points"
    }

    private func pointAllocations(for rule: RuleTemplate, quantity: Double) -> [Int] {
        let dates = selectedDates(for: rule)
        return rule.incrementalPointAllocations(
            existingQuantities: dates.map { existingQuantity(for: rule, on: $0) },
            additionalQuantity: quantity
        ).map { min(max($0, pointRange.lowerBound), pointRange.upperBound) }
    }

    private func assignmentTotal(for rule: RuleTemplate) -> Int? {
        guard let draft = drafts[rule.id] else { return nil }
        if draft.pointsOverridden {
            return draft.points * selectedDateCount(for: rule)
        }
        return pointAllocations(for: rule, quantity: draft.quantity).reduce(0, +)
    }

    private func existingQuantity(for rule: RuleTemplate, on occurrenceDate: Date? = nil) -> Double {
        entries
            .filter {
                guard $0.memberID == member.id,
                      $0.ruleID == rule.id,
                      $0.status != .rejected,
                      Calendar.current.isDate($0.weekEnding, inSameDayAs: weekEnding) else {
                    return false
                }
                guard rule.maximumPeriod == .daily, let occurrenceDate else { return true }
                return Calendar.current.isDate(PointsEngine.occurrenceDate(for: $0), inSameDayAs: occurrenceDate)
            }
            .reduce(0.0) { $0 + max(0, $1.quantity) }
    }

    private func save() {
        let selectedDrafts = selectedRules.compactMap { rule in
            drafts[rule.id].map { (rule, $0) }
        }
        guard !selectedDrafts.isEmpty,
              selectedDrafts.allSatisfy({ !$0.1.weekdays.isEmpty && $0.0.isEligible(for: member, at: weekEnding) }) else {
            errorMessage = "One or more selected items are not available for this child’s age."
            return
        }

        let submissionKind = ActivitySubmissionPolicy.submissionKind(
            member: appleIDManager.currentFamilyMember,
            membershipRole: appleIDManager.currentMembership?.role
        )
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let recorder = appleIDManager.currentFamilyMember?.name ?? submissionKind.submittedBy
        for (rule, draft) in selectedDrafts {
            let occurrenceDates = PointsEngine.dates(
                inWeekEnding: weekEnding,
                matchingWeekdays: draft.weekdays
            )
            let calculatedPoints = pointAllocations(for: rule, quantity: draft.quantity)
            for (index, occurredAt) in occurrenceDates.enumerated() {
                let entryPoints = draft.pointsOverridden
                    ? draft.points
                    : calculatedPoints[index]
                modelContext.insert(
                    LedgerEntry(
                        memberID: member.id,
                        ruleID: rule.id,
                        occurredAt: occurredAt,
                        weekEnding: weekEnding,
                        title: rule.title,
                        notes: trimmedNotes,
                        points: entryPoints,
                        kind: kind,
                        status: submissionKind.requiresParentApproval ? .pending : .approved,
                        submittedBy: recorder,
                        reviewedBy: submissionKind.requiresParentApproval ? nil : recorder,
                        reviewedAt: submissionKind.requiresParentApproval ? nil : .now,
                        quantity: draft.quantity,
                        measurementUnit: rule.measurementUnit
                    )
                )
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The entries could not be saved: \(error.localizedDescription)"
        }
    }
}

struct WeekdaySelector: View {
    let weekEnding: Date
    @Binding var selection: Set<Int>
    var identifierPrefix = "activityDay"

    private var dates: [Date] { PointsEngine.dates(inWeekEnding: weekEnding) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(dates, id: \.self) { date in
                let weekday = Calendar.current.component(.weekday, from: date)
                let isSelected = selection.contains(weekday)
                Button {
                    if isSelected {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption.bold())
                        Text(date.formatted(.dateTime.day()))
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityIdentifier("\(identifierPrefix)-\(weekday)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct WeeklyLedgerView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(ReportingPeriod.self) private var reportingPeriod
    @Environment(\.modelContext) private var modelContext
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @Query private var rules: [RuleTemplate]
    @Query private var settlements: [WeeklySettlement]
    @State private var reviewErrorMessage: String?
    @State private var editingSummary: LedgerSummary?
    @State private var showingBulkCopy = false

    private var weekEnding: Date { reportingPeriod.weekEnding }

    private var canReview: Bool {
        appleIDManager.currentMembership?.role.canReviewLedger == true
    }

    private var familyMembers: [FamilyMember] {
        members.filter {
            $0.familyID == appleIDManager.currentFamily?.id && $0.role.participatesInPoints
        }
    }

    private var summaries: [LedgerSummary] {
        PointsEngine.ledgerSummaries(
            weekEnding: weekEnding,
            memberIDs: Set(familyMembers.map(\.id)),
            entries: entries,
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id }
        )
    }

    private var dayGroups: [LedgerDayGroup] {
        let grouped = Dictionary(grouping: summaries) {
            LedgerDayGroup.Key(
                memberID: $0.memberID,
                occurredAt: Calendar.current.startOfDay(for: $0.occurredAt)
            )
        }
        let memberOrder = Dictionary(uniqueKeysWithValues: sortedMembers.enumerated().map { ($0.element.id, $0.offset) })
        return grouped.map { key, summaries in
            LedgerDayGroup(key: key, summaries: summaries.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            })
        }
        .sorted {
            let lhsOrder = memberOrder[$0.memberID] ?? .max
            let rhsOrder = memberOrder[$1.memberID] ?? .max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return $0.occurredAt < $1.occurredAt
        }
    }

    private var sortedMembers: [FamilyMember] {
        familyMembers.sorted(by: FamilyMember.comesBeforeInFamilyList)
    }

    private var hasRows: Bool {
        sortedMembers.contains { $0.role == .child } || !summaries.isEmpty
    }

    private var pendingEntriesForWeek: [LedgerEntry] {
        PointsEngine.pendingEntriesForReview(
            weekEnding: weekEnding,
            memberIDs: Set(familyMembers.map(\.id)),
            entries: entries
        )
    }

    private var activePastWeekEndings: [Date] {
        PointsEngine.activePastWeekEndings(
            members: familyMembers,
            entries: entries,
            settlements: settlements,
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id },
            cashValuePerPoint: appleIDManager.currentFamily?.effectiveCashValuePerPoint ?? Decimal(string: "0.01")!
        )
    }

    var body: some View {
        Group {
            if !hasRows {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "list.bullet.clipboard",
                    description: Text("No rewards or penalties were recorded for this week.")
                )
            } else {
                List {
                    Section("Starting points") {
                        ForEach(sortedMembers.filter { $0.role == .child }) { member in
                            HStack {
                                Label(member.name, systemImage: "flag.checkered")
                                Spacer()
                                Text(signed(PointsEngine.startingPoints(for: member, weekEnding: weekEnding)))
                                    .fontWeight(.semibold)
                            }
                            .accessibilityIdentifier("ledgerStartingValue-\(member.name)")
                        }
                    }

                    Section("Activity by day") {
                        ForEach(dayGroups) { group in
                            LedgerDayDisclosureRow(
                                group: group,
                                memberName: memberName(for: group.memberID),
                                entries: entries,
                                canReview: canReview,
                                onEdit: { editingSummary = $0 },
                                onReviewSummary: { summary, status in review(summary, as: status) },
                                onReviewEntry: { entry, status in review([entry], as: status) }
                            )
                        }
                    }
                }
                .accessibilityIdentifier("weeklyLedgerHeader")
            }
        }
        .navigationTitle("Weekly Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canReview && !pendingEntriesForWeek.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Review All", systemImage: "checklist") {
                        Button("Approve all waiting", systemImage: "checkmark.circle.fill") {
                            reviewAll(as: .approved)
                        }
                        Button("Reject all waiting", systemImage: "xmark.circle.fill", role: .destructive) {
                            reviewAll(as: .rejected)
                        }
                    }
                    .accessibilityIdentifier("reviewAllLedger")
                }
            }
            if canReview {
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy Week", systemImage: "doc.on.doc") {
                        showingBulkCopy = true
                    }
                    .accessibilityIdentifier("copyLedgerWeek")
                }
            }
        }
        .sheet(item: $editingSummary) { summary in
            LedgerEntryEditorView(
                entries: entries.filter { Set(summary.entryIDs).contains($0.id) },
                memberName: memberName(for: summary.memberID),
                weekEnding: weekEnding,
                canEdit: canReview
            )
        }
        .sheet(isPresented: $showingBulkCopy) {
            BulkCopyWeekView(
                members: familyMembers,
                entries: entries,
                currentWeekEnding: PointsEngine.weekEnding(containing: .now)
            )
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 4) {
                ReportingWeekPicker()
                    .padding(.horizontal, 12)
                if canReview && !activePastWeekEndings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You have \(activePastWeekEndings.count) past \(activePastWeekEndings.count == 1 ? "week" : "weeks") with active transactions:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            SettlementView()
                        } label: {
                            HStack {
                                Label("Review and Close", systemImage: "checkmark.seal.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ledgerSettlementLink")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 8)
                }
                if let reviewErrorMessage {
                    Text(reviewErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func memberName(for id: UUID) -> String {
        familyMembers.first { $0.id == id }?.name ?? "Unknown"
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
    }

    private func review(_ summary: LedgerSummary, as status: ApprovalStatus) {
        review(
            PointsEngine.pendingEntriesForReview(
                weekEnding: weekEnding,
                memberIDs: Set(familyMembers.map(\.id)),
                entries: entries,
                matchingEntryIDs: Set(summary.pendingEntryIDs)
            ),
            as: status
        )
    }

    private func reviewAll(as status: ApprovalStatus) {
        review(pendingEntriesForWeek, as: status)
    }

    private func review(_ pendingEntries: [LedgerEntry], as status: ApprovalStatus) {
        guard canReview, !pendingEntries.isEmpty else { return }
        let reviewer = appleIDManager.currentFamilyMember?.name ?? "Parent"
        let reviewedAt = Date.now
        PointsEngine.applyReview(
            to: pendingEntries,
            status: status,
            reviewedBy: reviewer,
            reviewedAt: reviewedAt
        )
        do {
            try modelContext.save()
            reviewErrorMessage = nil
        } catch {
            modelContext.rollback()
            reviewErrorMessage = "The review could not be saved: \(error.localizedDescription)"
        }
    }
}

private struct LedgerDayGroup: Identifiable {
    struct Key: Hashable {
        let memberID: UUID
        let occurredAt: Date
    }

    let key: Key
    let summaries: [LedgerSummary]

    var id: String { "\(memberID.uuidString)-\(occurredAt.timeIntervalSinceReferenceDate)" }
    var memberID: UUID { key.memberID }
    var occurredAt: Date { key.occurredAt }
    var activeCount: Int { summaries.reduce(0) { $0 + $1.approvedCount + $1.pendingCount } }
    var activePoints: Int { summaries.reduce(0) { $0 + $1.approvedPoints + $1.pendingPoints } }
    var pendingCount: Int { summaries.reduce(0) { $0 + $1.pendingCount } }
}

private struct LedgerDayDisclosureRow: View {
    let group: LedgerDayGroup
    let memberName: String
    let entries: [LedgerEntry]
    let canReview: Bool
    let onEdit: (LedgerSummary) -> Void
    let onReviewSummary: (LedgerSummary, ApprovalStatus) -> Void
    let onReviewEntry: (LedgerEntry, ApprovalStatus) -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(group.summaries) { summary in
                LedgerItemDisclosureRow(
                    summary: summary,
                    memberName: memberName,
                    entries: entries.filter { Set(summary.entryIDs).contains($0.id) },
                    canReview: canReview,
                    onEdit: { onEdit(summary) },
                    onReviewSummary: { onReviewSummary(summary, $0) },
                    onReviewEntry: onReviewEntry
                )
                .padding(.leading, 8)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memberName).font(.headline)
                    Text(group.occurredAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if group.pendingCount > 0 {
                    Label(group.pendingCount.formatted(), systemImage: "clock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                Text("\(group.activeCount) \(group.activeCount == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(signed(group.activePoints))
                    .font(.headline)
            }
            .contentShape(Rectangle())
            .accessibilityIdentifier("ledgerDay-\(memberName)-\(group.occurredAt.formatted(.dateTime.year().month().day()))")
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
    }
}

private struct LedgerItemDisclosureRow: View {
    let summary: LedgerSummary
    let memberName: String
    let entries: [LedgerEntry]
    let canReview: Bool
    let onEdit: () -> Void
    let onReviewSummary: (ApprovalStatus) -> Void
    let onReviewEntry: (LedgerEntry, ApprovalStatus) -> Void
    @State private var isExpanded = false

    private var needsSubmissionBreakdown: Bool {
        entries.count > 1 || Set(entries.map(\.submittedBy)).count > 1
    }

    var body: some View {
        Group {
            if needsSubmissionBreakdown {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(entries.sorted { $0.submittedBy.localizedCaseInsensitiveCompare($1.submittedBy) == .orderedAscending }) { entry in
                        LedgerSubmissionRow(
                            entry: entry,
                            canReview: canReview,
                            onReview: { onReviewEntry(entry, $0) }
                        )
                        .padding(.leading, 8)
                    }
                } label: {
                    itemLabel
                }
            } else {
                itemLabel
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityIdentifier("ledgerSummary-\(memberName)-\(summary.title)")
    }

    private var itemLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.iconName)
                .foregroundStyle(summary.kind == .penalty ? .red : summary.kind == .purchase ? .purple : .green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title).fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canReview && summary.hasPendingEntries {
                Menu {
                    Button("Approve all waiting", systemImage: "checkmark.circle.fill") {
                        onReviewSummary(.approved)
                    }
                    Button("Reject all waiting", systemImage: "xmark.circle.fill", role: .destructive) {
                        onReviewSummary(.rejected)
                    }
                } label: {
                    Image(systemName: "clock.fill").foregroundStyle(.orange)
                }
            }
            Text(signed(summary.approvedPoints + summary.pendingPoints))
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let activeCount = summary.approvedCount + summary.pendingCount
        let recorders = summary.submittedBy.isEmpty ? "Unknown recorder" : summary.submittedBy
        return "\(activeCount) \(activeCount == 1 ? "record" : "records") • \(recorders)"
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
    }
}

private struct LedgerSubmissionRow: View {
    let entry: LedgerEntry
    let canReview: Bool
    let onReview: (ApprovalStatus) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.submittedBy.isEmpty ? "Unknown recorder" : entry.submittedBy)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(entry.quantity.formatted())
                    Text((RuleMeasurementUnit(rawValue: entry.measurementUnitRawValue) ?? .occurrence).label(for: entry.quantity))
                    if !entry.notes.isEmpty { Text("• \(entry.notes)").lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signed(entry.points)).fontWeight(.semibold)
            if canReview && entry.status == .pending {
                Menu {
                    Button("Approve this submission", systemImage: "checkmark.circle.fill") { onReview(.approved) }
                    Button("Reject this submission", systemImage: "xmark.circle.fill", role: .destructive) { onReview(.rejected) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("ledgerSubmission-\(entry.id.uuidString)")
    }

    private var statusIcon: String {
        switch entry.status {
        case .pending: "clock.fill"
        case .approved: "checkmark.circle.fill"
        case .rejected: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .pending: .orange
        case .approved: .green
        case .rejected: .red
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
    }
}

private struct BulkCopyWeekView: View {
    let members: [FamilyMember]
    let entries: [LedgerEntry]
    let currentWeekEnding: Date

    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var sourceWeekEnding: Date
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var errorMessage: String?

    init(members: [FamilyMember], entries: [LedgerEntry], currentWeekEnding: Date) {
        self.members = members
        self.entries = entries
        self.currentWeekEnding = currentWeekEnding
        _sourceWeekEnding = State(initialValue: PointsEngine.previousWeekEnding(before: currentWeekEnding))
    }

    private var copyableEntries: [LedgerEntry] {
        PointsEngine.copyableEntries(
            weekEnding: sourceWeekEnding,
            memberIDs: Set(members.filter(\.isActive).map(\.id)),
            entries: entries
        )
    }

    private var selectedEntries: [LedgerEntry] {
        copyableEntries.filter { selectedEntryIDs.contains($0.id) }
    }

    private var sourceWeekEndings: [Date] {
        (1...260).compactMap { offset in
            Calendar.current.date(
                byAdding: .day,
                value: offset * -7,
                to: currentWeekEnding
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Copy from") {
                    Picker("Week ending", selection: $sourceWeekEnding) {
                        ForEach(sourceWeekEndings, id: \.self) { weekEnding in
                            Text(weekEnding.formatted(date: .abbreviated, time: .omitted))
                                .tag(weekEnding)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("copySourceWeek")
                    Text("Approved rewards and fines are copied to the same weekdays in the current week ending \(currentWeekEnding.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if copyableEntries.isEmpty {
                        ContentUnavailableView(
                            "Nothing to Copy",
                            systemImage: "doc.on.doc",
                            description: Text("This week has no approved rewards or fines.")
                        )
                    } else {
                        ForEach(copyableEntries) { entry in
                            Toggle(isOn: selectionBinding(for: entry.id)) {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(entry.kind.activityEmoji)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).fontWeight(.semibold)
                                        Text("\(memberName(for: entry.memberID)) • \(PointsEngine.occurrenceDate(for: entry).formatted(.dateTime.weekday(.wide)))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(signed(entry.points))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(entry.points < 0 ? .red : .green)
                                    }
                                }
                            }
                            .accessibilityIdentifier("copyEntry-\(entry.id.uuidString)")
                        }
                    }
                } header: {
                    HStack {
                        Text("Items")
                        Spacer()
                        if !copyableEntries.isEmpty {
                            Button(selectedEntryIDs.count == copyableEntries.count ? "Select None" : "Select All") {
                                if selectedEntryIDs.count == copyableEntries.count {
                                    selectedEntryIDs.removeAll()
                                } else {
                                    selectAll()
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Copy Rewards & Fines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Current Week", action: copyEntries)
                        .disabled(selectedEntries.isEmpty)
                        .accessibilityIdentifier("confirmCopyWeek")
                }
            }
            .onAppear(perform: selectAll)
            .onChange(of: sourceWeekEnding) {
                selectAll()
            }
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedEntryIDs.contains(id) },
            set: { selected in
                if selected { selectedEntryIDs.insert(id) }
                else { selectedEntryIDs.remove(id) }
            }
        )
    }

    private func selectAll() {
        selectedEntryIDs = Set(copyableEntries.map(\.id))
    }

    private func memberName(for id: UUID) -> String {
        members.first { $0.id == id }?.name ?? "Unknown"
    }

    private func signed(_ points: Int) -> String {
        points > 0 ? "+\(points.formatted()) points" : "\(points.formatted()) points"
    }

    private func copyEntries() {
        guard appleIDManager.currentMembership?.role.canReviewLedger == true,
              !selectedEntries.isEmpty else { return }
        let recorder = appleIDManager.currentFamilyMember?.name ?? "Parent"
        let copies = PointsEngine.duplicateEntries(
            selectedEntries,
            toWeekEnding: currentWeekEnding,
            submittedBy: recorder
        )
        copies.forEach(modelContext.insert)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "The items could not be copied: \(error.localizedDescription)"
        }
    }
}

private enum WeeklyLedgerColumns {
    static let type: CGFloat = 34
    static let item: CGFloat = 150
    static let person: CGFloat = 100
    static let day: CGFloat = 72
    static let recordedBy: CGFloat = 110
    static let count: CGFloat = 42
    static let points: CGFloat = 72
    static let next: CGFloat = 64
    static let status: CGFloat = 44
    static let spacing: CGFloat = 8
    static let tableWidth = type + status + day + person + item + recordedBy + count + points + next + spacing * 8
}

private struct WeeklyLedgerHeader: View {
    let sortDescriptors: [LedgerSortDescriptor]
    let onSelectSort: (LedgerSortColumn) -> Void

    var body: some View {
        HStack(spacing: WeeklyLedgerColumns.spacing) {
            header("Type", .type, width: WeeklyLedgerColumns.type)
            header("Status", .status, width: WeeklyLedgerColumns.status)
            header("Day", .day, width: WeeklyLedgerColumns.day, alignment: .leading)
            header("Receiver", .person, width: WeeklyLedgerColumns.person, alignment: .leading)
            header("Item", .item, width: WeeklyLedgerColumns.item, alignment: .leading)
            header("Recorded by", .recordedBy, width: WeeklyLedgerColumns.recordedBy, alignment: .leading)
            header("#", .count, width: WeeklyLedgerColumns.count, alignment: .trailing)
            header("Week", .points, width: WeeklyLedgerColumns.points, alignment: .trailing)
            header("Next", .next, width: WeeklyLedgerColumns.next, alignment: .trailing)
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weeklyLedgerHeader")
    }

    private func header(
        _ title: String,
        _ column: LedgerSortColumn,
        width: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        let index = sortDescriptors.firstIndex { $0.column == column }
        let descriptor = index.map { sortDescriptors[$0] }
        return Button {
            onSelectSort(column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if let descriptor, let index {
                    Image(systemName: descriptor.ascending ? "arrow.up" : "arrow.down")
                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
        .accessibilityValue(descriptor == nil ? "Not selected" : "Priority \((index ?? 0) + 1), \(descriptor!.ascending ? "ascending" : "descending")")
        .accessibilityIdentifier("ledgerSort-\(column.rawValue)")
    }
}

private struct WeeklyLedgerStartingRow: View {
    let memberName: String
    let points: Int

    var body: some View {
        HStack(spacing: WeeklyLedgerColumns.spacing) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.secondary)
                .frame(width: WeeklyLedgerColumns.type)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: WeeklyLedgerColumns.status)
                .accessibilityLabel("Approved")
            placeholder(width: WeeklyLedgerColumns.day)
            Text(memberName).frame(width: WeeklyLedgerColumns.person, alignment: .leading)
            Text("Starting value")
                .fontWeight(.semibold)
                .frame(width: WeeklyLedgerColumns.item, alignment: .leading)
            placeholder(width: WeeklyLedgerColumns.recordedBy)
            placeholder(width: WeeklyLedgerColumns.count)
            Text(signed(points)).frame(width: WeeklyLedgerColumns.points, alignment: .trailing)
            placeholder(width: WeeklyLedgerColumns.next)
        }
        .font(.caption)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ledgerStartingValue-\(memberName)")
    }

    private func placeholder(width: CGFloat) -> some View {
        Text("—").foregroundStyle(.tertiary).frame(width: width, alignment: .trailing)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
    }
}

private struct WeeklyLedgerRow: View {
    let summary: LedgerSummary
    let memberName: String
    let canReview: Bool
    let onEdit: () -> Void
    let onApproveItem: () -> Void
    let onRejectItem: () -> Void

    var body: some View {
        HStack(spacing: WeeklyLedgerColumns.spacing) {
            Text(summary.kind.activityEmoji)
                .frame(width: WeeklyLedgerColumns.type)
                .accessibilityHidden(true)
            statusControl
                .frame(width: WeeklyLedgerColumns.status)
            Text(summary.occurredAt.formatted(.dateTime.weekday(.abbreviated)))
                .frame(width: WeeklyLedgerColumns.day, alignment: .leading)
            Text(memberName)
                .lineLimit(1)
                .frame(width: WeeklyLedgerColumns.person, alignment: .leading)
            HStack(spacing: 5) {
                Image(systemName: summary.hasPendingEntries ? "clock.fill" : summary.iconName)
                    .foregroundStyle(summary.hasPendingEntries ? .orange : (summary.kind == .penalty ? .indigo : .green))
                Text(summary.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .frame(width: WeeklyLedgerColumns.item, alignment: .leading)
            Text(summary.submittedBy.isEmpty ? "Unknown" : summary.submittedBy)
                .lineLimit(1)
                .frame(width: WeeklyLedgerColumns.recordedBy, alignment: .leading)
            Text(summary.weeklyCount.formatted())
                .frame(width: WeeklyLedgerColumns.count, alignment: .trailing)
            Text(signed(summary.weeklyPoints))
                .fontWeight(.semibold)
                .frame(width: WeeklyLedgerColumns.points, alignment: .trailing)
            Text(summary.nextPoints.map(signed) ?? "—")
                .frame(width: WeeklyLedgerColumns.next, alignment: .trailing)
        }
        .font(.caption)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.kind == .reward ? "Reward" : "Penalty"), \(summary.title), \(memberName), " +
            "\(summary.occurredAt.formatted(.dateTime.weekday(.wide))), recorded by \(summary.submittedBy), " +
            "\(summary.weeklyCount) this week, \(signed(summary.weeklyPoints)) points, " +
            "next \(summary.nextPoints.map(signed) ?? "not available")" +
            ", \(statusText)"
        )
        .accessibilityIdentifier("ledgerSummary-\(memberName)-\(summary.title)")
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
    }

    @ViewBuilder
    private var statusControl: some View {
        if canReview && summary.hasPendingEntries {
            Menu {
                Button("Leave Waiting", systemImage: "clock.fill") {}
                Button("Approve", systemImage: "checkmark.circle.fill", action: onApproveItem)
                Button("Reject", systemImage: "xmark.circle.fill", role: .destructive, action: onRejectItem)
            } label: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }
            .accessibilityLabel(statusText)
            .accessibilityIdentifier("ledgerStatus-\(memberName)-\(summary.title)")
        } else {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusText)
                .accessibilityIdentifier("ledgerStatus-\(memberName)-\(summary.title)")
        }
    }

    private var statusText: String {
        if summary.pendingCount > 0 {
            if summary.approvedCount > 0 {
                return "\(summary.pendingCount) need action • \(summary.approvedCount) approved"
            }
            return "\(summary.pendingCount) need action"
        }
        if summary.approvedCount > 0 && summary.rejectedCount > 0 {
            return "\(summary.approvedCount) approved • \(summary.rejectedCount) rejected"
        }
        if summary.approvedCount > 0 { return "Approved" }
        return "Rejected"
    }

    private var statusIcon: String {
        if summary.pendingCount > 0 { return "clock.fill" }
        if summary.approvedCount > 0 { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private var statusColor: Color {
        if summary.pendingCount > 0 { return .orange }
        if summary.approvedCount > 0 { return .green }
        return .red
    }
}

private struct LedgerEntryEditorView: View {
    let entries: [LedgerEntry]
    let memberName: String
    let weekEnding: Date
    let canEdit: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var occurredAt: Date
    @State private var totalPoints: Int
    @State private var totalQuantity: Double
    @State private var notes: String
    @State private var errorMessage: String?

    init(entries: [LedgerEntry], memberName: String, weekEnding: Date, canEdit: Bool) {
        self.entries = entries
        self.memberName = memberName
        self.weekEnding = weekEnding
        self.canEdit = canEdit
        _occurredAt = State(initialValue: entries.first.map { PointsEngine.occurrenceDate(for: $0) } ?? weekEnding)
        _totalPoints = State(initialValue: entries.reduce(0) { $0 + $1.points })
        _totalQuantity = State(initialValue: entries.reduce(0) { $0 + $1.quantity })
        let distinctNotes = Set(entries.map(\.notes))
        _notes = State(initialValue: distinctNotes.count == 1 ? distinctNotes.first ?? "" : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    LabeledContent("Item", value: entries.first?.title ?? "Unknown")
                    LabeledContent("Person", value: memberName)
                    LabeledContent("Recorded by", value: recorderNames)
                    LabeledContent("Status", value: statusDescription)
                    LabeledContent("Records", value: entries.count.formatted())
                }
                Section("Activity") {
                    DatePicker(
                        "Day occurred",
                        selection: $occurredAt,
                        in: dateRange,
                        displayedComponents: .date
                    )
                    Stepper("Total points: \(totalPoints)", value: $totalPoints, in: -100_000...100_000)
                    Stepper(quantityDescription, value: $totalQuantity, in: 1...100_000, step: 1)
                        .disabled(hasMixedMeasurementUnits)
                        .accessibilityIdentifier("ledgerQuantity")
                    if hasMixedMeasurementUnits {
                        Label("These records use different quantity units. Edit them separately to change quantity.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                .disabled(!canEdit)
                if !canEdit {
                    Label("Only a parent can edit ledger entries.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(canEdit ? "Edit Ledger Item" : "Ledger Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                    }
                }
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let dates = PointsEngine.dates(inWeekEnding: weekEnding)
        return (dates.first ?? weekEnding)...(dates.last ?? weekEnding)
    }

    private var recorderNames: String {
        Array(Set(entries.map(\.submittedBy).filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    private var statusDescription: String {
        let statuses = Set(entries.map(\.statusRawValue))
        return statuses.count == 1 ? statuses.first?.capitalized ?? "Unknown" : "Mixed"
    }

    private var quantityDescription: String {
        let units = Set(entries.map(\.measurementUnitRawValue))
        guard units.count == 1, let rawValue = units.first,
              let unit = RuleMeasurementUnit(rawValue: rawValue) else {
            return "Total quantity: \(totalQuantity.formatted()) (mixed units)"
        }
        return "Total quantity: \(totalQuantity.formatted()) \(unit.label(for: totalQuantity))"
    }

    private var hasMixedMeasurementUnits: Bool {
        Set(entries.map(\.measurementUnitRawValue)).count != 1
    }

    private func save() {
        guard canEdit, !entries.isEmpty else { return }
        let pointDistribution = distribute(totalPoints, across: entries.count)
        let quantityPerEntry = totalQuantity / Double(entries.count)
        for (index, entry) in entries.enumerated() {
            entry.occurredAt = Calendar.current.startOfDay(for: occurredAt)
            entry.weekEnding = weekEnding
            entry.points = pointDistribution[index]
            if !hasMixedMeasurementUnits {
                entry.quantity = quantityPerEntry
            }
            entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "The ledger item could not be saved: \(error.localizedDescription)"
        }
    }

    private func distribute(_ total: Int, across count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let quotient = total / count
        let remainder = total % count
        return (0..<count).map { index in
            quotient + (index < abs(remainder) ? (remainder > 0 ? 1 : -1) : 0)
        }
    }
}

private struct MemberDraft {
    var name = ""
    var emailAddress = ""
    var birthDate: Date?
    var sourceContactIdentifier: String?
    var avatarData: Data?
    var role: MemberRole = .child
}

private struct FamilySettingsEditorView: View {
    let onSave: (String, Decimal) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var cashValuePerPoint: Double
    @State private var validationMessage: String?

    init(
        currentName: String,
        currentCashValuePerPoint: Decimal,
        onSave: @escaping (String, Decimal) throws -> Void
    ) {
        self.onSave = onSave
        _name = State(initialValue: currentName)
        _cashValuePerPoint = State(initialValue: NSDecimalNumber(decimal: currentCashValuePerPoint).doubleValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Family name") {
                    TextField("Family name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    LabeledContent("1 point =") {
                        TextField("Cash value", value: $cashValuePerPoint, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("familyCashValuePerPoint")
                    }
                } header: {
                    Text("Point value")
                } footer: {
                    Text("This is an informational cash value, not a presumed payout.")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Family Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a family name."
            return
        }

        do {
            try onSave(trimmedName, Decimal(max(0, cashValuePerPoint)))
            dismiss()
        } catch {
            validationMessage = "The family settings could not be saved: \(error.localizedDescription)"
        }
    }
}

private struct MemberEditorView: View {
    let title: String
    let isAddingMember: Bool
    let onSave: (MemberDraft) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MemberDraft
    @State private var validationMessage: String?
#if canImport(PhotosUI)
    @State private var selectedAvatarItem: PhotosPickerItem?
#endif
    @FocusState private var focusedField: Field?
#if canImport(ContactsUI) && canImport(UIKit)
    @State private var contactPickerPurpose: ContactPickerPurpose?
    @State private var contactImportMessage: String?
#endif

    private enum Field: Hashable {
        case contacts
        case name
        case emailAddress
        case role
        case birthday
        case removeBirthday
    }

#if canImport(ContactsUI) && canImport(UIKit)
    private enum ContactPickerPurpose: String, Identifiable {
        case profile
        case avatar

        var id: Self { self }
    }
#endif

    init(
        title: String,
        member: FamilyMember? = nil,
        onSave: @escaping (MemberDraft) throws -> Void
    ) {
        #if DEBUG
        let defaultRole = ProcessInfo.processInfo.environment["UITEST_DEFAULT_MEMBER_ROLE"]
            .flatMap(MemberRole.init(rawValue:)) ?? .child
        #else
        let defaultRole = MemberRole.child
        #endif
        self.title = title
        self.isAddingMember = member == nil
        self.onSave = onSave
        _draft = State(initialValue: MemberDraft(
            name: member?.name ?? "",
            emailAddress: member?.emailAddress ?? "",
            birthDate: member?.birthDate,
            sourceContactIdentifier: member?.sourceContactIdentifier,
            avatarData: member?.avatarData,
            role: member?.role ?? defaultRole
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
#if canImport(ContactsUI) && canImport(UIKit)
                if isAddingMember {
                    Section {
                        Button {
                            contactPickerPurpose = .profile
                        } label: {
                            Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
                        }
                        .focusable(interactions: .edit)
                        .focused($focusedField, equals: .contacts)
                        if let contactImportMessage {
                            Text(contactImportMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Import a name, first email address, and full birthday when available. Review the details and choose a role before saving.")
                    }
                }
#endif

                Section {
                    HStack {
                        Spacer()
                        Menu {
#if canImport(PhotosUI)
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                Label("Choose from Photos", systemImage: "photo.badge.plus")
                            }
#endif
#if canImport(ContactsUI) && canImport(UIKit)
                            Button {
                                contactPickerPurpose = .avatar
                            } label: {
                                Label("Choose Contact Photo", systemImage: "person.crop.circle.badge.plus")
                            }
#endif
#if canImport(ImagePlayground) && canImport(UIKit)
                            if #available(iOS 26.0, *) {
                                GenmojiAvatarButton(concept: genmojiConcept) { data in
                                    if let normalizedData = normalizedAvatarData(data) {
                                        draft.avatarData = normalizedData
#if canImport(PhotosUI)
                                        selectedAvatarItem = nil
#endif
                                    } else {
                                        validationMessage = "The selected Genmoji could not be used as an avatar."
                                    }
                                }
                            }
#endif
                            if draft.avatarData != nil {
                                Divider()
                                Button("Remove Avatar", systemImage: "trash", role: .destructive) {
                                    draft.avatarData = nil
#if canImport(PhotosUI)
                                    selectedAvatarItem = nil
#endif
                                }
                            }
                        } label: {
                            ZStack(alignment: .bottom) {
                                MemberAvatarView(
                                    avatarData: draft.avatarData,
                                    name: draft.name,
                                    role: draft.role,
                                    size: 112
                                )
                                Text("Edit")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.68), in: Capsule())
                                    .offset(y: 8)
                            }
                            .padding(.bottom, 8)
                            .contentShape(Circle())
                            .hoverEffect(.lift)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit avatar")
                        .accessibilityIdentifier("chooseMemberAvatar")
                        Spacer()
                    }
                    TextField("Name", text: $draft.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .emailAddress
                        }
                    TextField("Email address (optional)", text: $draft.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .emailAddress)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .role
                        }

                    #if canImport(UIKit)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        LabeledContent("Role") {
                            Picker("Role", selection: $draft.role) {
                                Text("Child").tag(MemberRole.child)
                                Text("Parent").tag(MemberRole.parent)
                                Text("Caregiver").tag(MemberRole.caregiver)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("memberRolePicker")
                        }

                        LabeledContent(draft.role == .child ? "Birthdate" : "Birthday (optional)") {
                            if draft.birthDate != nil {
                                DatePicker(
                                    "Birthdate",
                                    selection: birthDateBinding,
                                    in: ...Date.now,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .accessibilityIdentifier("memberBirthdatePicker")
                            } else {
                                Button(draft.role == .child ? "Enter birthdate" : "Add birthday") {
                                    focusedField = nil
                                    draft.birthDate = Calendar.current.date(
                                        byAdding: .year,
                                        value: draft.role == .child ? -10 : -30,
                                        to: .now
                                    ) ?? .now
                                }
                                .accessibilityIdentifier("addMemberBirthdate")
                            }
                        }
                    } else {
                        LabeledContent("Role") {
                            RoleInputField(
                                role: $draft.role,
                                isFocused: focusBinding(for: .role),
                                onNext: { focusedField = .birthday },
                                onPrevious: { focusedField = .emailAddress }
                            )
                            .frame(width: 180, height: 32)
                        }

                        LabeledContent(draft.role == .child ? "Birthdate" : "Birthday (optional)") {
                            BirthdayInputField(
                                birthDate: $draft.birthDate,
                                defaultAge: draft.role == .child ? 10 : 30,
                                isFocused: focusBinding(for: .birthday),
                                onNext: {
                                    focusedField = draft.role != .child && draft.birthDate != nil
                                        ? .removeBirthday
                                        : nil
                                },
                                onPrevious: { focusedField = .role }
                            )
                            .frame(width: 180, height: 32)
                        }
                    }
                    if draft.role != .child, draft.birthDate != nil {
                        Button("Clear optional birthday") {
                            draft.birthDate = nil
                        }
                        .focused($focusedField, equals: .removeBirthday)
                    }
                    #else
                    Picker("Role", selection: $draft.role) {
                        Text("Child").tag(MemberRole.child)
                        Text("Parent").tag(MemberRole.parent)
                        Text("Caregiver").tag(MemberRole.caregiver)
                    }
                    .focused($focusedField, equals: .role)

                    if draft.birthDate != nil {
                        DatePicker(
                            draft.role == .child ? "Birthdate" : "Birthday (optional)",
                            selection: birthDateBinding,
                            displayedComponents: .date
                        )
                        .focused($focusedField, equals: .birthday)
                    } else {
                        Button(draft.role == .child ? "Enter birthdate" : "Add birthday") {
                            focusedField = .birthday
                        }
                        .focused($focusedField, equals: .birthday)
                    }
                    #endif

                    if draft.role == .child {
                        LabeledContent("Current default points") {
                            if draft.birthDate == nil {
                                Text("Enter birthdate")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(currentDefaultPoints.formatted()) points")
                            }
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Select Edit on the avatar to choose a photo, import a contact image, or create a Genmoji on a supported device. A birthdate is required for children because starting points are calculated from age; it is optional for adults.")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultFocus($focusedField, .name)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                focusedField = .name
            }
#if canImport(PhotosUI)
            .task(id: selectedAvatarItem) {
                guard let selectedAvatarItem,
                      let data = try? await selectedAvatarItem.loadTransferable(type: Data.self) else { return }
                guard let normalizedData = normalizedAvatarData(data) else {
                    validationMessage = "The selected image could not be used as an avatar."
                    return
                }
                draft.avatarData = normalizedData
                validationMessage = nil
            }
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
#if canImport(ContactsUI) && canImport(UIKit)
        .sheet(item: $contactPickerPurpose) { purpose in
            FamilyMemberContactPicker { contact in
                switch purpose {
                case .profile:
                    importContact(contact)
                case .avatar:
                    importContactPhoto(contact)
                }
                contactPickerPurpose = nil
            } onCancel: {
                contactPickerPurpose = nil
            }
        }
#endif
    }

#if canImport(ContactsUI) && canImport(UIKit)
    private func importContact(_ contact: CNContact) {
        draft.sourceContactIdentifier = contact.identifier
        if contact.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]) {
            draft.name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        } else {
            draft.name = ""
        }
        draft.emailAddress = contact.isKeyAvailable(CNContactEmailAddressesKey)
            ? contact.emailAddresses.first.map { $0.value as String } ?? ""
            : ""

        let contactImageData: Data?
        if contact.isKeyAvailable(CNContactThumbnailImageDataKey), let data = contact.thumbnailImageData {
            contactImageData = data
        } else if contact.isKeyAvailable(CNContactImageDataKey), let data = contact.imageData {
            contactImageData = data
        } else {
            contactImageData = nil
        }
        let importedContactPhoto: Bool
        if let contactImageData, let normalizedData = normalizedAvatarData(contactImageData) {
            draft.avatarData = normalizedData
            importedContactPhoto = true
#if canImport(PhotosUI)
            selectedAvatarItem = nil
#endif
        } else {
            importedContactPhoto = false
        }

        let birthdayComponents: DateComponents?
        if contact.isKeyAvailable(CNContactBirthdayKey), let birthday = contact.birthday {
            birthdayComponents = birthday
        } else if contact.isKeyAvailable(CNContactNonGregorianBirthdayKey),
                  let birthday = contact.nonGregorianBirthday {
            birthdayComponents = birthday
        } else {
            birthdayComponents = nil
        }

        // A month/day-only birthday must never become a fabricated age.
        draft.birthDate = birthdayComponents.flatMap { ContactBirthdayConverter.date(from: $0) }
        if let birthDate = draft.birthDate {
            draft.role = ContactBirthdayConverter.isAdult(birthDate) ? .caregiver : .child
        }
        validationMessage = nil
        let importedPhoto = importedContactPhoto ? " The contact photo was also imported." : ""
        contactImportMessage = draft.birthDate == nil
            ? "No full birthdate was available. Enter one for a child; it is optional for adults.\(importedPhoto)"
            : "Contact details imported.\(importedPhoto) Review them and choose the member’s role before saving."
        focusedField = .role
    }

    private func importContactPhoto(_ contact: CNContact) {
        let imageData: Data?
        if contact.isKeyAvailable(CNContactThumbnailImageDataKey), let data = contact.thumbnailImageData {
            imageData = data
        } else if contact.isKeyAvailable(CNContactImageDataKey), let data = contact.imageData {
            imageData = data
        } else {
            imageData = nil
        }

        guard let imageData, let normalizedData = normalizedAvatarData(imageData) else {
            validationMessage = "That contact does not have a usable photo."
            return
        }
        draft.avatarData = normalizedData
        validationMessage = nil
#if canImport(PhotosUI)
        selectedAvatarItem = nil
#endif
    }
#endif

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.emailAddress = draft.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            validationMessage = "Enter a name."
            focusedField = .name
            return
        }
        guard draft.role != .child || draft.birthDate != nil else {
            validationMessage = "Enter a birthdate for a child profile."
            focusedField = .birthday
            return
        }
        do {
            try onSave(draft)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { draft.birthDate ?? .now },
            set: { draft.birthDate = $0 }
        )
    }

    private func focusBinding(for field: Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { isFocused in
                if isFocused {
                    focusedField = field
                } else if focusedField == field {
                    focusedField = nil
                }
            }
        )
    }

    private var currentDefaultPoints: Int {
        PointsEngine.startingPoints(
            forBirthDate: draft.birthDate,
            role: draft.role,
            weekEnding: PointsEngine.weekEnding(containing: .now)
        )
    }

    private var genmojiConcept: String {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "A friendly family member" : "A friendly avatar for \(trimmedName)"
    }

    private func normalizedAvatarData(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let maximumDimension: CGFloat = 512
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let side = min(image.size.width, image.size.height)
        let outputSide = min(maximumDimension, side)
        let outputSize = CGSize(width: outputSide, height: outputSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let resized = renderer.image { _ in
            let scale = max(outputSide / image.size.width, outputSide / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (outputSide - drawSize.width) / 2,
                y: (outputSide - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        return resized.pngData()
        #else
        return data
        #endif
    }
}

#if canImport(ImagePlayground) && canImport(UIKit)
@available(iOS 26.0, *)
private struct GenmojiAvatarButton: View {
    let concept: String
    let onSelect: (Data) -> Void
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var showingImagePlayground = false

    var body: some View {
        if supportsImagePlayground {
            Button {
                showingImagePlayground = true
            } label: {
                Label("Create Genmoji", systemImage: "wand.and.sparkles")
            }
            .imagePlaygroundSheet(
                isPresented: $showingImagePlayground,
                concept: concept,
                onCompletion: { url in
                    if let data = try? Data(contentsOf: url) {
                        onSelect(data)
                    }
                },
                onAdaptiveImageGlyphCreation: { glyph in
                    onSelect(glyph.imageContent)
                }
            )
            .imagePlaygroundGenerationStyle(.emoji, in: [.emoji])
        }
    }
}
#endif

private struct MemberAvatarView: View {
    let avatarData: Data?
    let name: String
    let role: MemberRole
    let size: CGFloat

    init(member: FamilyMember, size: CGFloat) {
        avatarData = member.avatarData
        name = member.name
        role = member.role
        self.size = size
    }

    init(avatarData: Data?, name: String, role: MemberRole, size: CGFloat) {
        self.avatarData = avatarData
        self.name = name
        self.role = role
        self.size = size
    }

    var body: some View {
        Group {
            if let avatarImage {
                avatarImage
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(accentColor.gradient)
                    Text(initials)
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: max(1, size * 0.025)) }
        .shadow(color: .black.opacity(0.16), radius: size * 0.04, y: size * 0.02)
        .accessibilityLabel("Avatar for \(name.isEmpty ? "family member" : name)")
    }

    private var avatarImage: Image? {
        guard let avatarData else { return nil }
        #if canImport(UIKit)
        return UIImage(data: avatarData).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        return NSImage(data: avatarData).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }

    private var initials: String {
        let letters = name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var accentColor: Color {
        switch role {
        case .child: .blue
        case .parent: .purple
        case .caregiver: .teal
        }
    }
}

private struct FamilyCardSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(accent.opacity(0.045))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

private extension View {
    func familyCardSurface(accent: Color) -> some View {
        modifier(FamilyCardSurface(accent: accent))
    }
}

#if canImport(UIKit)
private struct RoleInputField: UIViewRepresentable {
    @Binding var role: MemberRole
    @Binding var isFocused: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void

    private let roles: [MemberRole] = [.child, .parent, .caregiver]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TabNavigatingTextField {
        let textField = TabNavigatingTextField()
        textField.delegate = context.coordinator
        textField.textAlignment = .right
        textField.tintColor = .clear
        textField.accessibilityLabel = "Role"

        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        textField.inputView = picker
        context.coordinator.picker = picker
        return textField
    }

    func updateUIView(_ textField: TabNavigatingTextField, context: Context) {
        context.coordinator.parent = self
        textField.onNext = onNext
        textField.onPrevious = onPrevious
        textField.text = role.title
        textField.accessibilityValue = role.title
        if let index = roles.firstIndex(of: role) {
            context.coordinator.picker?.selectRow(index, inComponent: 0, animated: false)
        }
        synchronizeFocus(of: textField)
    }

    private func synchronizeFocus(of textField: UITextField) {
        if isFocused, !textField.isFirstResponder, textField.window != nil {
            DispatchQueue.main.async { textField.becomeFirstResponder() }
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: RoleInputField
        weak var picker: UIPickerView?

        init(parent: RoleInputField) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.roles.count
        }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            parent.roles[row].title
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.role = parent.roles[row]
        }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.isFocused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            false
        }
    }
}

private struct BirthdayInputField: UIViewRepresentable {
    @Binding var birthDate: Date?
    let defaultAge: Int
    @Binding var isFocused: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TabNavigatingTextField {
        let textField = TabNavigatingTextField()
        textField.delegate = context.coordinator
        textField.textAlignment = .right
        textField.tintColor = .clear
        textField.accessibilityLabel = "Birthdate"

        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = .now
        textField.inputView = picker
        context.coordinator.picker = picker

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "Use This Date", style: .done, target: context.coordinator, action: #selector(Coordinator.useSelectedDate))
        ]
        textField.inputAccessoryView = toolbar
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ textField: TabNavigatingTextField, context: Context) {
        context.coordinator.parent = self
        textField.onNext = onNext
        textField.onPrevious = onPrevious
        textField.placeholder = birthDate == nil ? "Enter birthdate" : nil
        textField.text = birthDate?.formatted(date: .abbreviated, time: .omitted)
        textField.accessibilityValue = textField.text ?? "Not entered"
        if let birthDate {
            context.coordinator.picker?.setDate(birthDate, animated: false)
        }
        synchronizeFocus(of: textField, coordinator: context.coordinator)
    }

    private func synchronizeFocus(of textField: UITextField, coordinator: Coordinator) {
        if isFocused, !textField.isFirstResponder, textField.window != nil {
            coordinator.prepareDateIfNeeded()
            DispatchQueue.main.async { textField.becomeFirstResponder() }
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: BirthdayInputField
        weak var picker: UIDatePicker?
        weak var textField: UITextField?

        init(parent: BirthdayInputField) {
            self.parent = parent
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            prepareDateIfNeeded()
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            false
        }

        func prepareDateIfNeeded() {
            guard parent.birthDate == nil else { return }
            let date = Calendar.current.date(byAdding: .year, value: -parent.defaultAge, to: .now) ?? .now
            picker?.date = date
        }

        @objc func useSelectedDate() {
            if let picker {
                parent.birthDate = picker.date
            }
            textField?.resignFirstResponder()
        }
    }
}

private final class TabNavigatingTextField: UITextField {
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let next = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(moveToNextField))
        let previous = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(moveToPreviousField))
        next.wantsPriorityOverSystemBehavior = true
        previous.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [next, previous]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key, key.keyCode == .keyboardTab {
            if key.modifierFlags.contains(.shift) {
                onPrevious?()
            } else {
                onNext?()
            }
            return
        }
        super.pressesBegan(presses, with: event)
    }

    @objc private func moveToNextField() {
        onNext?()
    }

    @objc private func moveToPreviousField() {
        onPrevious?()
    }
}
#endif

private enum ManageFamilyError: LocalizedError {
    case noSelectedFamily

    var errorDescription: String? {
        "No family is selected."
    }
}

#if canImport(ContactsUI) && canImport(UIKit)
private struct FamilyMemberContactPicker: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> ContactPickerHostController {
        ContactPickerHostController(onSelect: onSelect, onCancel: onCancel)
    }

    func updateUIViewController(_ controller: ContactPickerHostController, context: Context) {}

    // The picker must have its own UIKit presenter. Its automatic dismissal
    // must not target the SwiftUI presentation that owns the member editor.
    final class ContactPickerHostController: UIViewController, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        let onCancel: () -> Void
        private var hasPresentedPicker = false

        init(onSelect: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPresentedPicker else { return }
            hasPresentedPicker = true
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.predicateForSelectionOfContact = NSPredicate(value: true)
            picker.displayedPropertyKeys = [
                CNContactEmailAddressesKey,
                CNContactBirthdayKey,
                CNContactNonGregorianBirthdayKey,
                CNContactImageDataAvailableKey
            ]
            picker.modalPresentationStyle = .fullScreen
            present(picker, animated: true)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Finish UIKit's presentation before removing the SwiftUI wrapper.
            picker.dismiss(animated: true) { [self] in
                loadSelectedContactDetails(for: contact)
            }
        }

        private func loadSelectedContactDetails(for pickerContact: CNContact) {
            if (pickerContact.isKeyAvailable(CNContactBirthdayKey) ||
                pickerContact.isKeyAvailable(CNContactNonGregorianBirthdayKey)) &&
                (pickerContact.isKeyAvailable(CNContactThumbnailImageDataKey) ||
                pickerContact.isKeyAvailable(CNContactImageDataKey)) {
                onSelect(pickerContact)
                return
            }

            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .authorized || isLimited(status) {
                refetchAndSelect(pickerContact)
            } else if status == .notDetermined {
                let store = CNContactStore()
                store.requestAccess(for: .contacts) { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if granted {
                            self.refetchAndSelect(pickerContact, store: store)
                        } else {
                            self.onSelect(pickerContact)
                        }
                    }
                }
            } else {
                onSelect(pickerContact)
            }
        }

        private func refetchAndSelect(
            _ pickerContact: CNContact,
            store: CNContactStore = CNContactStore()
        ) {
            let keysToFetch = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactBirthdayKey as CNKeyDescriptor,
                CNContactNonGregorianBirthdayKey as CNKeyDescriptor,
                CNContactImageDataAvailableKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
                CNContactImageDataKey as CNKeyDescriptor
            ]

            do {
                let contact = try store.unifiedContact(
                    withIdentifier: pickerContact.identifier,
                    keysToFetch: keysToFetch
                )
                onSelect(contact)
            } catch {
                onSelect(pickerContact)
            }
        }

        private func isLimited(_ status: CNAuthorizationStatus) -> Bool {
            if #available(iOS 18.0, *) {
                return status == .limited
            }
            return false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true) { [self] in
                onCancel()
            }
        }
    }
}
#endif

enum ContactBirthdayConverter {
    static func isAdult(
        _ birthDate: Date,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        (PointsEngine.age(from: birthDate, at: date, calendar: calendar) ?? 0) >= 18
    }

    static func date(from components: DateComponents, now: Date = .now) -> Date? {
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              year > 1,
              year != NSDateComponentUndefined,
              month != NSDateComponentUndefined,
              day != NSDateComponentUndefined else {
            return nil
        }

        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var normalized = DateComponents()
        normalized.calendar = calendar
        normalized.timeZone = calendar.timeZone
        normalized.era = components.era
        normalized.year = year
        normalized.month = month
        normalized.day = day
        normalized.isLeapMonth = components.isLeapMonth
        normalized.hour = 12

        guard let date = calendar.date(from: normalized) else { return nil }

        let resolved = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
        guard resolved.year == normalized.year,
              resolved.month == normalized.month,
              resolved.day == normalized.day,
              calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) else {
            return nil
        }
        if let era = normalized.era, resolved.era != era { return nil }
        if let isLeapMonth = normalized.isLeapMonth, resolved.isLeapMonth != isLeapMonth { return nil }

        return date
    }
}

#Preview {
    NavigationStack {
        ManageFamilyView()
            .environment(AppleIDManager())
            .environment(ReportingPeriod())
            .environment(SoundscapeDirector())
            .modelContainer(for: [
                AllowanceFamily.self,
                FamilyInvitation.self,
                FamilyMembership.self,
                FamilyMember.self
            ])
    }
}
