import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @State private var selectedTab = "family"
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }
                .tag("dashboard")
            LogActivityView()
                .tabItem { Label("Record", systemImage: "plus.circle.fill") }
                .tag("record")
            ApprovalsView()
                .tabItem { Label("Approvals", systemImage: "checkmark.circle") }
                .tag("approvals")
            SettlementView()
                .tabItem { Label("Settlement", systemImage: "dollarsign.circle") }
                .tag("settlement")
            RuleCatalogView()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
                .tag("rules")
            NavigationStack {
                ManageFamilyView()
            }
            .tabItem { Label("Family", systemImage: "person.3.fill") }
            .tag("family")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Signed in as") {
                        Text(appleIDManager.currentFamilyMember?.name ?? "Unknown")
                            .disabled(true)
                    }
                    
                    Divider()
                    
                    NavigationLink("Manage My Family", destination: ManageFamilyView())
                    
                    Divider()
                    
                    Button("Sign Out", action: signOut)
                } label: {
                    Image(systemName: "person.circle.fill")
                }
            }
        }
    }
    
    private func signOut() {
        appleIDManager.signOut()
    }
}

private struct DashboardView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @Query private var settlements: [WeeklySettlement]

    private var weekEnding: Date {
        PointsEngine.weekEnding(containing: .now)
    }

    private var familyMembers: [FamilyMember] {
        members.filter { $0.familyID == appleIDManager.currentFamily?.id }
    }

    private var familyEntries: [LedgerEntry] {
        let ids = Set(familyMembers.map(\.id))
        return entries.filter { ids.contains($0.memberID) }
    }

    private var familySettlements: [WeeklySettlement] {
        let ids = Set(familyMembers.map(\.id))
        return settlements.filter { ids.contains($0.childID) }
    }

    private var drafts: [SettlementDraft] {
        return PointsEngine.settlementDrafts(
            weekEnding: weekEnding,
            members: familyMembers,
            entries: familyEntries,
            settlements: familySettlements
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Week ending \(weekEnding.formatted(date: .abbreviated, time: .omitted))") {
                    ForEach(drafts) { draft in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(draft.child.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(draft.finalPoints) pts")
                                    .font(.title3.bold())
                            }
                            Text("Base \(draft.startingPoints)  •  Debt \(draft.debtCarriedIn)  •  Entries \(draft.approvedEntryPoints)  •  Parent pot +\(draft.parentPotShare)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Pending approval") {
                    let pending = familyEntries.filter { $0.status == .pending }
                    if pending.isEmpty {
                        Text("No pending submissions")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(pending.count) item\(pending.count == 1 ? "" : "s") waiting")
                    }
                }
            }
            .navigationTitle("Family Points")
        }
    }
}

private struct LogActivityView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \RuleTemplate.title) private var allRules: [RuleTemplate]

    @State private var selectedMemberID: UUID?
    @State private var selectedRuleID: UUID?
    @State private var points = 0
    @State private var notes = ""
    @State private var submittedByChild = false
    @State private var errorMessage: String?

    private var rules: [RuleTemplate] {
        allRules.filter(\.isEnabled)
    }

    private var familyMembers: [FamilyMember] {
        members.filter { $0.familyID == appleIDManager.currentFamily?.id }
    }

    private var selectedRule: RuleTemplate? {
        rules.first { $0.id == selectedRuleID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Family member", selection: $selectedMemberID) {
                    Text("Select").tag(nil as UUID?)
                    ForEach(familyMembers.filter(\.isActive)) { member in
                        Text(member.name).tag(member.id as UUID?)
                    }
                }

                Picker("Rule or reward", selection: $selectedRuleID) {
                    Text("Select").tag(nil as UUID?)
                    ForEach(rules) { rule in
                        Text(rule.title).tag(rule.id as UUID?)
                    }
                }
                .onChange(of: selectedRuleID) {
                    points = selectedRule?.defaultPoints ?? 0
                }

                if let rule = selectedRule, !rule.guidance.isEmpty {
                    Text(rule.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper("Points: \(points)", value: $points, in: -10_000...10_000)
                TextField("Notes", text: $notes, axis: .vertical)
                Toggle("Submitted by a child", isOn: $submittedByChild)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Button("Save entry", action: save)
                    .disabled(selectedMemberID == nil || selectedRuleID == nil)
            }
            .navigationTitle("Record Activity")
        }
    }

    private func save() {
        guard
            let memberID = selectedMemberID,
            let rule = selectedRule
        else {
            errorMessage = "Select a family member and rule."
            return
        }

        let entry = LedgerEntry(
            memberID: memberID,
            ruleID: rule.id,
            weekEnding: PointsEngine.weekEnding(containing: .now),
            title: rule.title,
            notes: notes,
            points: points,
            kind: rule.kind,
            status: submittedByChild ? .pending : .approved,
            submittedBy: submittedByChild ? "Child" : "Parent",
            reviewedBy: submittedByChild ? nil : "Parent",
            reviewedAt: submittedByChild ? nil : .now
        )
        modelContext.insert(entry)

        do {
            try modelContext.save()
            selectedRuleID = nil
            points = 0
            notes = ""
            errorMessage = nil
        } catch {
            errorMessage = "The entry could not be saved: \(error.localizedDescription)"
        }
    }
}

private struct ApprovalsView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LedgerEntry.occurredAt, order: .reverse) private var entries: [LedgerEntry]
    @Query private var members: [FamilyMember]
    @State private var errorMessage: String?

    private var pending: [LedgerEntry] {
        let ids = Set(members.filter { $0.familyID == appleIDManager.currentFamily?.id }.map(\.id))
        return entries.filter { ids.contains($0.memberID) && $0.status == .pending }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if pending.isEmpty {
                    ContentUnavailableView(
                        "No Pending Items",
                        systemImage: "checkmark.circle",
                        description: Text("Child submissions will appear here.")
                    )
                } else {
                    ForEach(pending) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title)
                                .font(.headline)
                            Text("\(memberName(entry.memberID)) • \(entry.points) points")
                                .foregroundStyle(.secondary)
                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                            }
                            HStack {
                                Button("Reject", role: .destructive) {
                                    review(entry, status: .rejected)
                                }
                                Spacer()
                                Button("Approve") {
                                    review(entry, status: .approved)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Approvals")
        }
    }

    private func memberName(_ id: UUID) -> String {
        members.first { $0.id == id }?.name ?? "Unknown"
    }

    private func review(_ entry: LedgerEntry, status: ApprovalStatus) {
        entry.status = status
        entry.reviewedBy = "Parent"
        entry.reviewedAt = .now
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "The review could not be saved: \(error.localizedDescription)"
        }
    }
}

private struct SettlementView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @Query private var settlements: [WeeklySettlement]
    @State private var selectedWeekEnding = PointsEngine.weekEnding(containing: .now)
    @State private var errorMessage: String?

    private var drafts: [SettlementDraft] {
        let familyMembers = members.filter { $0.familyID == appleIDManager.currentFamily?.id }
        let ids = Set(familyMembers.map(\.id))
        return PointsEngine.settlementDrafts(
            weekEnding: selectedWeekEnding,
            members: familyMembers,
            entries: entries.filter { ids.contains($0.memberID) },
            settlements: settlements.filter { ids.contains($0.childID) }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                DatePicker(
                    "Week ending",
                    selection: $selectedWeekEnding,
                    displayedComponents: .date
                )

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                ForEach(drafts) { draft in
                    Section(draft.child.name) {
                        LabeledContent("Starting points", value: "\(draft.startingPoints)")
                        LabeledContent("Debt carried in", value: "\(draft.debtCarriedIn)")
                        LabeledContent("Approved entries", value: "\(draft.approvedEntryPoints)")
                        LabeledContent("Parent-pot share", value: "+\(draft.parentPotShare)")
                        LabeledContent("Final points", value: "\(draft.finalPoints)")
                        LabeledContent(
                            "Cash transfer",
                            value: draft.cashAmount.formatted(.currency(code: "USD"))
                        )
                        LabeledContent("Debt carried out", value: "\(draft.debtCarriedOut)")

                        if isConfirmed(draft) {
                            Label("Settlement confirmed", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Confirm settlement") {
                                confirm(draft)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Weekly Settlement")
        }
    }

    private func isConfirmed(_ draft: SettlementDraft) -> Bool {
        settlements.contains {
            $0.childID == draft.child.id &&
            Calendar.current.isDate($0.weekEnding, inSameDayAs: draft.weekEnding)
        }
    }

    private func confirm(_ draft: SettlementDraft) {
        guard !isConfirmed(draft) else { return }

        modelContext.insert(
            WeeklySettlement(
                childID: draft.child.id,
                weekEnding: draft.weekEnding,
                startingPoints: draft.startingPoints,
                debtCarriedIn: draft.debtCarriedIn,
                approvedEntryPoints: draft.approvedEntryPoints,
                parentPotShare: draft.parentPotShare,
                finalPoints: draft.finalPoints,
                cashAmount: draft.cashAmount,
                debtCarriedOut: draft.debtCarriedOut,
                confirmedBy: "Parent"
            )
        )

        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "The settlement could not be saved: \(error.localizedDescription)"
        }
    }
}

private struct RuleCatalogView: View {
    @Query(sort: \RuleTemplate.title) private var rules: [RuleTemplate]

    var body: some View {
        NavigationStack {
            List {
                ForEach(RuleCategory.allCases, id: \.self) { category in
                    Section(category.title) {
                        ForEach(rules.filter { $0.category == category }) { rule in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(rule.title)
                                    Spacer()
                                    Text("\(rule.defaultPoints)")
                                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                                }
                                if !rule.guidance.isEmpty {
                                    Text(rule.guidance)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !rule.isEnabled {
                                    Text("Disabled until configured")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rule Catalog")
        }
    }
}

private extension RuleCategory {
    var title: String {
        switch self {
        case .household: "Household"
        case .behavior: "Behavior"
        case .rewardStore: "Reward Store"
        }
    }
}

