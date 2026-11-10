#if canImport(ContactsUI) && canImport(UIKit)
import ContactsUI
#endif
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ManageFamilyView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \FamilyInvitation.createdAt, order: .reverse) private var invitations: [FamilyInvitation]
    @Query private var entries: [LedgerEntry]
    @Query private var settlements: [WeeklySettlement]
    @Query private var rules: [RuleTemplate]
    @State private var showingFamilyNameEditor = false
    @State private var showingAddMember = false
    @State private var editingMember: FamilyMember?
    @State private var memberPendingRemoval: FamilyMember?
    @State private var inviteToPresentAfterAdd: PendingInviteShare?
    @State private var pendingInviteShare: PendingInviteShare?
    @State private var errorMessage: String?
    @State private var selectedWeekEnding = PointsEngine.weekEnding(containing: .now)
    @State private var showingReportingPeriodPicker = false
    @State private var quickActivity: QuickActivityRequest?

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
        selectedWeekEnding
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
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id }
        )
    }

    private var pendingApprovalCount: Int {
        familyEntries.count {
            $0.status == .pending &&
            Calendar.current.isDate($0.weekEnding, inSameDayAs: weekEnding)
        }
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

            Section("Pending approval") {
                NavigationLink {
                    WeeklyLedgerView(weekEnding: weekEnding)
                } label: {
                    LabeledContent("View weekly ledger") {
                        Text(pendingApprovalCount == 0
                             ? "No pending submissions"
                             : "\(pendingApprovalCount) waiting")
                            .foregroundStyle(pendingApprovalCount == 0 ? Color.secondary : Color.orange)
                    }
                }
                .accessibilityIdentifier("weeklyLedgerLink")
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
        .navigationTitle(displayedFamilyName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canChooseReportingPeriod {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingReportingPeriodPicker = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Reporting period ending \(weekEnding.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            if canEdit {
                ToolbarItemGroup(placement: .primaryAction) {
                    familyNameEditButton
                    Button {
                        showingAddMember = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Add family member")
                }
            }
        }
        .sheet(isPresented: $showingFamilyNameEditor) {
            if let family = appleIDManager.currentFamily {
                FamilyNameEditorView(currentName: family.name) { newName in
                    try saveFamilyName(newName, for: family)
                }
            }
        }
        .sheet(isPresented: $showingReportingPeriodPicker) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Week ending",
                        selection: Binding(
                            get: { selectedWeekEnding },
                            set: { selectedWeekEnding = PointsEngine.weekEnding(containing: $0) }
                        ),
                        displayedComponents: .date
                    )
                }
                .navigationTitle("Reporting Period")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingReportingPeriodPicker = false }
                    }
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
        .sheet(item: $editingMember) { member in
            MemberEditorView(title: "Edit Family Member", member: member) { draft in
                try update(member, with: draft)
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

    @ViewBuilder
    private func memberSection(title: String, role: MemberRole) -> some View {
        let roleMembers = familyMembers.filter { $0.role == role }
        if !roleMembers.isEmpty {
            Section(title) {
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
                        onEdit: { editingMember = member }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canEdit {
                            Button("Remove", role: .destructive) {
                                memberPendingRemoval = member
                            }
                        }
                    }
                }
            }
        }
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

    private var familyNameEditButton: some View {
        Button("Edit") {
            showingFamilyNameEditor = true
        }
        .accessibilityLabel("Edit family name")
        .accessibilityHint("Opens a form for changing the family name.")
    }

    private func saveFamilyName(_ name: String, for family: AllowanceFamily) throws {
        let previousName = family.name
        family.name = name
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            family.name = previousName
            errorMessage = "The family name could not be saved: \(error.localizedDescription)"
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
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(memberDisplayName)
                        .font(.headline)
                }
                Spacer()
                if let points {
                    Text("\((points.balance ?? points.net).formatted()) pts")
                        .font(.title3.bold())
                }
                if !member.isActive {
                    Text("Inactive")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                if canEdit {
                    Button(action: onEdit) {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Edit \(member.name)")
                }
            }

            if let points {
                if let base = points.base {
                    Text("Base \(base.formatted())  •  Earned +\(points.earned.formatted())  •  Lost -\(points.lost.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pointsSummary-\(member.name)")
                    if points.debt != 0 || points.parentPotShare != 0 {
                        Text("Debt \(points.debt.formatted())  •  Parent pot +\(points.parentPotShare.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Earned +\(points.earned.formatted())  •  Lost -\(points.lost.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pointsSummary-\(member.name)")
                }

                if points.pendingCount > 0 {
                    Label {
                        Text("Waiting approval: +\(points.pendingEarned.formatted()) earned  •  -\(points.pendingLost.formatted()) lost")
                    } icon: {
                        Image(systemName: "clock.fill")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("pendingPoints-\(member.name)")
                }

                HStack(spacing: 12) {
                    if let onReward {
                        Button(action: onReward) {
                            Text(EntryKind.reward.activityEmoji)
                                .font(.title2)
                                .frame(width: 40, height: 36)
                                .background(.green.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reward \(member.name)")
                    }
                    if let onPenalty {
                        Button(action: onPenalty) {
                            Text(EntryKind.penalty.activityEmoji)
                                .font(.title2)
                                .frame(width: 40, height: 36)
                                .background(.indigo.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Penalize \(member.name)")
                    }
                }
            }

            if let email = member.emailAddress, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isCurrentMember {
                HStack {
                    if let invitation {
                        Text("Invite code: \(invitation.code)")
                            .font(.caption.monospaced().bold())
                        Spacer()
                        ShareLink(
                            item: invitationMessage(invitation),
                            subject: Text(invitationSubject)
                        ) {
                            Label("Share invitation", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Share invitation for \(member.name)")
                    } else if canEdit {
                        Button("Generate invitation code", action: onGenerateCode)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var memberDisplayName: String {
        var name = member.name
        if isCurrentMember {
            name += " (me)"
        }
        if let age = member.currentAge {
            name += " – \(age) \(age == 1 ? "year" : "years") old"
        } else {
            name += " – No birthdate"
        }
        return name
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

private struct QuickActivityRequest: Identifiable {
    let member: FamilyMember
    let kind: EntryKind
    let weekEnding: Date

    var id: String { "\(member.id.uuidString)-\(kind.rawValue)" }
}

private struct QuickActivityDraft {
    var quantity: Double
    var points: Int
    var weekdays: Set<Int>
}

private struct QuickActivityView: View {
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
            $0.catalog == catalog
        }
    }

    private var selectedRules: [RuleTemplate] {
        rules.filter { drafts[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind == .reward ? "Choose an award" : "Choose a penalty") {
                    ForEach(rules) { rule in
                        Button {
                            select(rule)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: rule.iconName)
                                    .foregroundStyle(kind == .reward ? .green : .indigo)
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
                }

                ForEach(selectedRules) { rule in
                    Section(rule.title) {
                        WeekdaySelector(
                            weekEnding: weekEnding,
                            selection: weekdaysBinding(for: rule),
                            identifierPrefix: "activityDay-\(rule.title)"
                        )
                        if rule.frequencyKind == .time {
                            LabeledContent("Quantity") {
                                HStack(spacing: 6) {
                                    TextField("Quantity", value: quantityBinding(for: rule), format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 90)
                                        .accessibilityIdentifier("quickActivityQuantity-\(rule.title)")
                                    Text(rule.timeUnit.label(for: drafts[rule.id]?.quantity ?? rule.defaultEntryQuantity))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        LabeledContent("Points") {
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
                        if !rule.guidance.isEmpty {
                            Text(rule.guidance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !selectedRules.isEmpty {
                    Section("All selected entries") {
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("quickActivityNotes")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("\(kind.activityEmoji) \(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            }
        )
    }

    private func calculatedPoints(for rule: RuleTemplate, quantity: Double) -> Int {
        let points = rule.incrementalPoints(
            existingQuantity: existingQuantity(for: rule),
            additionalQuantity: quantity
        )
        return min(max(points, pointRange.lowerBound), pointRange.upperBound)
    }

    private func existingQuantity(for rule: RuleTemplate) -> Double {
        entries
            .filter {
                $0.memberID == member.id &&
                $0.ruleID == rule.id &&
                $0.status != .rejected &&
                Calendar.current.isDate($0.weekEnding, inSameDayAs: weekEnding)
            }
            .reduce(0.0) { $0 + max(0, $1.quantity) }
    }

    private func save() {
        let selectedDrafts = selectedRules.compactMap { rule in
            drafts[rule.id].map { (rule, $0) }
        }
        guard !selectedDrafts.isEmpty,
              selectedDrafts.allSatisfy({ !$0.1.weekdays.isEmpty }) else { return }

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
            for occurredAt in occurrenceDates {
                modelContext.insert(
                    LedgerEntry(
                        memberID: member.id,
                        ruleID: rule.id,
                        occurredAt: occurredAt,
                        weekEnding: weekEnding,
                        title: rule.title,
                        notes: trimmedNotes,
                        points: draft.points,
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
    let weekEnding: Date

    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @Query private var rules: [RuleTemplate]
    @State private var reviewErrorMessage: String?
    @State private var sortDescriptors = PointsEngine.defaultLedgerSort
    @State private var editingSummary: LedgerSummary?
    @State private var showingBulkCopy = false

    private var canReview: Bool {
        appleIDManager.currentMembership?.role.canReviewLedger == true
    }

    private var familyMembers: [FamilyMember] {
        members.filter {
            $0.familyID == appleIDManager.currentFamily?.id && $0.role.participatesInPoints
        }
    }

    private var summaries: [LedgerSummary] {
        let summaries = PointsEngine.ledgerSummaries(
            weekEnding: weekEnding,
            memberIDs: Set(familyMembers.map(\.id)),
            entries: entries,
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id }
        )
        return PointsEngine.sortLedgerSummaries(
            summaries,
            by: sortDescriptors,
            memberNames: Dictionary(uniqueKeysWithValues: familyMembers.map { ($0.id, $0.name) })
        )
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

    var body: some View {
        Group {
            if !hasRows {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "list.bullet.clipboard",
                    description: Text("No rewards or penalties were recorded for this week.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(sortedMembers.filter { $0.role == .child }) { member in
                                WeeklyLedgerStartingRow(
                                    memberName: member.name,
                                    points: PointsEngine.startingPoints(for: member, weekEnding: weekEnding)
                                )
                            }
                            ForEach(summaries) { summary in
                                WeeklyLedgerRow(
                                    summary: summary,
                                    memberName: memberName(for: summary.memberID),
                                    canReview: canReview,
                                    onEdit: { editingSummary = summary },
                                    onApproveItem: { review(summary, as: .approved) },
                                    onRejectItem: { review(summary, as: .rejected) },
                                    onApproveAll: { reviewAll(as: .approved) },
                                    onRejectAll: { reviewAll(as: .rejected) }
                                )
                            }
                        } header: {
                            WeeklyLedgerHeader(
                                sortDescriptors: sortDescriptors,
                                onSelectSort: selectSort
                            )
                        }
                    }
                    .frame(minWidth: WeeklyLedgerColumns.tableWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .navigationTitle("Weekly Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canReview {
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy Week", systemImage: "doc.on.doc") {
                        showingBulkCopy = true
                    }
                    .accessibilityIdentifier("copyLedgerWeek")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Reset Sort", systemImage: "arrow.up.arrow.down") {
                    sortDescriptors = PointsEngine.defaultLedgerSort
                }
                .disabled(sortDescriptors == PointsEngine.defaultLedgerSort)
                .accessibilityIdentifier("resetLedgerSort")
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
                Text("Week ending \(weekEnding.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func selectSort(_ column: LedgerSortColumn) {
        if sortDescriptors == PointsEngine.defaultLedgerSort {
            sortDescriptors = [LedgerSortDescriptor(column: column, ascending: true)]
            return
        }
        if let index = sortDescriptors.firstIndex(where: { $0.column == column }) {
            let current = sortDescriptors[index]
            sortDescriptors[index] = LedgerSortDescriptor(column: column, ascending: !current.ascending)
        } else {
            sortDescriptors.append(LedgerSortDescriptor(column: column, ascending: true))
        }
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

    var body: some View {
        NavigationStack {
            List {
                Section("Copy from") {
                    DatePicker(
                        "Week ending",
                        selection: $sourceWeekEnding,
                        in: ...PointsEngine.previousWeekEnding(before: currentWeekEnding),
                        displayedComponents: .date
                    )
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
                let normalized = PointsEngine.weekEnding(containing: sourceWeekEnding)
                if !Calendar.current.isDate(normalized, inSameDayAs: sourceWeekEnding) {
                    sourceWeekEnding = normalized
                } else {
                    selectAll()
                }
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
    static let recordCount: CGFloat = 56
    static let points: CGFloat = 72
    static let recordPoints: CGFloat = 78
    static let next: CGFloat = 64
    static let status: CGFloat = 150
    static let review: CGFloat = 150
    static let spacing: CGFloat = 8
    static let tableWidth = type + item + person + day + recordedBy + count + recordCount + points + recordPoints + next + status + review + spacing * 11
}

private struct WeeklyLedgerHeader: View {
    let sortDescriptors: [LedgerSortDescriptor]
    let onSelectSort: (LedgerSortColumn) -> Void

    var body: some View {
        HStack(spacing: WeeklyLedgerColumns.spacing) {
            header("Type", .type, width: WeeklyLedgerColumns.type)
            header("Item", .item, width: WeeklyLedgerColumns.item, alignment: .leading)
            header("Status", .status, width: WeeklyLedgerColumns.status, alignment: .leading)
            Text("Review").frame(width: WeeklyLedgerColumns.review)
            header("Person", .person, width: WeeklyLedgerColumns.person, alignment: .leading)
            header("Day", .day, width: WeeklyLedgerColumns.day, alignment: .leading)
            header("Recorded by", .recordedBy, width: WeeklyLedgerColumns.recordedBy, alignment: .leading)
            header("#", .count, width: WeeklyLedgerColumns.count, alignment: .trailing)
            header("Max #", .recordCount, width: WeeklyLedgerColumns.recordCount, alignment: .trailing)
            header("Week", .points, width: WeeklyLedgerColumns.points, alignment: .trailing)
            header("Record", .recordPoints, width: WeeklyLedgerColumns.recordPoints, alignment: .trailing)
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
            Text("Starting value")
                .fontWeight(.semibold)
                .frame(width: WeeklyLedgerColumns.item, alignment: .leading)
            Text("Approved")
                .foregroundStyle(.green)
                .frame(width: WeeklyLedgerColumns.status, alignment: .leading)
            placeholder(width: WeeklyLedgerColumns.review)
            Text(memberName).frame(width: WeeklyLedgerColumns.person, alignment: .leading)
            placeholder(width: WeeklyLedgerColumns.day)
            placeholder(width: WeeklyLedgerColumns.recordedBy)
            placeholder(width: WeeklyLedgerColumns.count)
            placeholder(width: WeeklyLedgerColumns.recordCount)
            Text(signed(points)).frame(width: WeeklyLedgerColumns.points, alignment: .trailing)
            placeholder(width: WeeklyLedgerColumns.recordPoints)
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
    let onApproveAll: () -> Void
    let onRejectAll: () -> Void

    var body: some View {
        HStack(spacing: WeeklyLedgerColumns.spacing) {
            Text(summary.kind.activityEmoji)
                .frame(width: WeeklyLedgerColumns.type)
                .accessibilityHidden(true)
            HStack(spacing: 5) {
                Image(systemName: summary.hasPendingEntries ? "clock.fill" : summary.iconName)
                    .foregroundStyle(summary.hasPendingEntries ? .orange : (summary.kind == .penalty ? .indigo : .green))
                Text(summary.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .frame(width: WeeklyLedgerColumns.item, alignment: .leading)
            Label(statusText, systemImage: statusIcon)
                .lineLimit(1)
                .foregroundStyle(statusColor)
                .frame(width: WeeklyLedgerColumns.status, alignment: .leading)
                .accessibilityIdentifier("ledgerStatus-\(memberName)-\(summary.title)")
            if canReview && summary.hasPendingEntries {
                HStack(spacing: 5) {
                    Menu("Reject") {
                        Button("This item", role: .destructive, action: onRejectItem)
                        Button("All pending this week", role: .destructive, action: onRejectAll)
                    }
                    .accessibilityIdentifier("rejectLedger-\(memberName)-\(summary.title)")
                    Menu("Approve") {
                        Button("This item", action: onApproveItem)
                        Button("All pending this week", action: onApproveAll)
                    }
                    .accessibilityIdentifier("approveLedger-\(memberName)-\(summary.title)")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(width: WeeklyLedgerColumns.review)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(width: WeeklyLedgerColumns.review)
            }
            Text(memberName)
                .lineLimit(1)
                .frame(width: WeeklyLedgerColumns.person, alignment: .leading)
            Text(summary.occurredAt.formatted(.dateTime.weekday(.abbreviated)))
                .frame(width: WeeklyLedgerColumns.day, alignment: .leading)
            Text(summary.submittedBy.isEmpty ? "Unknown" : summary.submittedBy)
                .lineLimit(1)
                .frame(width: WeeklyLedgerColumns.recordedBy, alignment: .leading)
            Text(summary.weeklyCount.formatted())
                .frame(width: WeeklyLedgerColumns.count, alignment: .trailing)
            Text(summary.recordWeeklyCount.formatted())
                .frame(width: WeeklyLedgerColumns.recordCount, alignment: .trailing)
            Text(signed(summary.weeklyPoints))
                .fontWeight(.semibold)
                .frame(width: WeeklyLedgerColumns.points, alignment: .trailing)
            Text(signed(summary.recordWeeklyPoints))
                .frame(width: WeeklyLedgerColumns.recordPoints, alignment: .trailing)
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
            "record \(summary.recordWeeklyCount) times and \(signed(summary.recordWeeklyPoints)) points, " +
            "next \(summary.nextPoints.map(signed) ?? "not available")" +
            ", \(statusText)"
        )
        .accessibilityIdentifier("ledgerSummary-\(memberName)-\(summary.title)")
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value.formatted())" : value.formatted()
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
        if summary.pendingCount > 0 { return "exclamationmark.circle.fill" }
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
                    Stepper("Total quantity: \(totalQuantity.formatted())", value: $totalQuantity, in: 1...100_000, step: 1)
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

    private func save() {
        guard canEdit, !entries.isEmpty else { return }
        let pointDistribution = distribute(totalPoints, across: entries.count)
        let quantityPerEntry = totalQuantity / Double(entries.count)
        for (index, entry) in entries.enumerated() {
            entry.occurredAt = Calendar.current.startOfDay(for: occurredAt)
            entry.weekEnding = weekEnding
            entry.points = pointDistribution[index]
            entry.quantity = quantityPerEntry
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
    var role: MemberRole = .child
}

private struct FamilyNameEditorView: View {
    let onSave: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var validationMessage: String?

    init(currentName: String, onSave: @escaping (String) throws -> Void) {
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Family name") {
                    TextField("Family name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Family Name")
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
            try onSave(trimmedName)
            dismiss()
        } catch {
            validationMessage = "The family name could not be saved: \(error.localizedDescription)"
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
    @FocusState private var focusedField: Field?
#if canImport(ContactsUI) && canImport(UIKit)
    @State private var showingContactPicker = false
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
                            showingContactPicker = true
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
                    Text("A birthdate is required for children because starting points are calculated from age. It is optional for parents and caregivers.")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .defaultFocus($focusedField, .name)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                focusedField = .name
            }
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
        .sheet(isPresented: $showingContactPicker) {
            FamilyMemberContactPicker { contact in
                importContact(contact)
                showingContactPicker = false
            } onCancel: {
                showingContactPicker = false
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
        contactImportMessage = draft.birthDate == nil
            ? "No full birthdate was available. Enter one for a child; it is optional for adults."
            : "Contact details imported. Review them and choose the member’s role before saving."
        focusedField = .role
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
        picker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
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

        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.birthDate = sender.date
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
                CNContactNonGregorianBirthdayKey
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
            if pickerContact.isKeyAvailable(CNContactBirthdayKey) ||
                pickerContact.isKeyAvailable(CNContactNonGregorianBirthdayKey) {
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
                CNContactNonGregorianBirthdayKey as CNKeyDescriptor
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
            .modelContainer(for: [
                AllowanceFamily.self,
                FamilyInvitation.self,
                FamilyMembership.self,
                FamilyMember.self
            ])
    }
}
