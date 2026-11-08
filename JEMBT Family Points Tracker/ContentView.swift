import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @State private var selectedTab = "family"
    
    var body: some View {
        TabView(selection: $selectedTab) {
            LogActivityView()
                .tabItem { Label("Record", systemImage: "plus.circle.fill") }
                .tag("record")
            RuleCatalogView()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
                .tag("rules")
            NavigationStack {
                WeeklyLedgerView(weekEnding: PointsEngine.weekEnding(containing: .now))
            }
                .tabItem { Label("Ledger", systemImage: "tablecells") }
                .tag("ledger")
            SettlementView()
                .tabItem { Label("Settlement", systemImage: "dollarsign.circle") }
                .tag("settlement")
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

private struct LogActivityView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \RuleTemplate.title) private var allRules: [RuleTemplate]

    @State private var selectedMemberID: UUID?
    @State private var selectedRuleID: UUID?
    @State private var quantity = 1.0
    @State private var points = 0
    @State private var notes = ""
    @State private var errorMessage: String?

    private var rules: [RuleTemplate] {
        allRules.filter {
            $0.familyID == appleIDManager.currentFamily?.id &&
            $0.isEnabled &&
            (submissionKind != .caregiverRecommendation || $0.catalog != .tradingPost)
        }
    }

    private var familyMembers: [FamilyMember] {
        members.filter {
            $0.familyID == appleIDManager.currentFamily?.id && $0.role.participatesInPoints
        }
    }

    private var selectedRule: RuleTemplate? {
        rules.first { $0.id == selectedRuleID }
    }

    private var submissionKind: ActivitySubmissionKind {
        ActivitySubmissionPolicy.submissionKind(
            member: appleIDManager.currentFamilyMember,
            membershipRole: appleIDManager.currentMembership?.role
        )
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

                Picker("Point item or reward", selection: $selectedRuleID) {
                    Text("Select").tag(nil as UUID?)
                    ForEach(rules) { rule in
                        Text(rule.title).tag(rule.id as UUID?)
                    }
                }
                .onChange(of: selectedRuleID) {
                    quantity = 1
                    updateCalculatedPoints()
                }

                if let rule = selectedRule {
                    Section(rule.frequencyKind == .count ? "How many times?" : "How much time?") {
                        Stepper(
                            rule.quantityDescription(quantity),
                            value: $quantity,
                            in: 1...rule.maximumInputQuantity,
                            step: 1
                        )
                        .onChange(of: quantity) { updateCalculatedPoints() }

                        if rule.awardCount(for: quantity) < rule.firstAwardNumber {
                            Text("Point changes begin with the \(ordinal(rule.firstAwardNumber)) award.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if !rule.guidance.isEmpty {
                        Text(rule.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper("Points: \(points)", value: $points, in: -10_000...10_000)
                TextField("Notes", text: $notes, axis: .vertical)
                LabeledContent("Submitted by") {
                    Text(submissionKind.accountDescription)
                        .accessibilityIdentifier("submissionAccountType")
                }
                if submissionKind.requiresParentApproval {
                    Text(submissionKind == .caregiverRecommendation
                         ? "This recommendation will be sent to a parent for approval."
                         : "This entry will be sent to a parent for approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
            status: submissionKind.requiresParentApproval ? .pending : .approved,
            submittedBy: submissionKind.submittedBy,
            reviewedBy: submissionKind.requiresParentApproval ? nil : "Parent",
            reviewedAt: submissionKind.requiresParentApproval ? nil : .now,
            quantity: quantity,
            measurementUnit: rule.measurementUnit,
            riderTitle: nil
        )
        modelContext.insert(entry)

        do {
            try modelContext.save()
            selectedRuleID = nil
            quantity = 1
            points = 0
            notes = ""
            errorMessage = nil
        } catch {
            errorMessage = "The entry could not be saved: \(error.localizedDescription)"
        }
    }

    private func updateCalculatedPoints() {
        guard let rule = selectedRule else {
            points = 0
            return
        }
        points = rule.calculatedPoints(quantity: quantity)
    }
}

private struct SettlementView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @Query private var settlements: [WeeklySettlement]
    @Query private var rules: [RuleTemplate]
    @State private var selectedWeekEnding = PointsEngine.weekEnding(containing: .now)
    @State private var errorMessage: String?
    @State private var appliedMinimumDeductions: [UUID: Set<UUID>] = [:]
    @State private var reviewedMinimumDeductions: Set<UUID> = []

    private var canConfirm: Bool {
        appleIDManager.currentMembership?.role.canManageRules == true
    }

    private var drafts: [SettlementDraft] {
        let familyMembers = members.filter { $0.familyID == appleIDManager.currentFamily?.id }
        let ids = Set(familyMembers.map(\.id))
        return PointsEngine.settlementDrafts(
            weekEnding: selectedWeekEnding,
            members: familyMembers,
            entries: entries.filter { ids.contains($0.memberID) },
            settlements: settlements.filter { ids.contains($0.childID) },
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id }






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
                    let confirmedSettlement = confirmedSettlement(for: draft)
                    Section(draft.child.name) {
                        LabeledContent("Starting points", value: "\(confirmedSettlement?.startingPoints ?? draft.startingPoints)")
                        LabeledContent("Debt carried in", value: "\(confirmedSettlement?.debtCarriedIn ?? draft.debtCarriedIn)")
                        LabeledContent("Approved entries", value: "\(confirmedSettlement?.approvedEntryPoints ?? draft.approvedEntryPoints)")
                        LabeledContent("Parent-pot share", value: "+\(confirmedSettlement?.parentPotShare ?? draft.parentPotShare)")
                        if !draft.minimumMissDeductions.isEmpty, confirmedSettlement == nil {
                            Text("Missed minimums")
                                .font(.headline)
                            ForEach(draft.minimumMissDeductions) { deduction in
                                Toggle(isOn: deductionBinding(for: deduction, childID: draft.child.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Deduct \(deduction.points) points — \(deduction.title)")
                                        Text("\(deduction.period.title): \(deduction.completedQuantity.formatted()) of \(deduction.requiredQuantity.formatted()) completed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Toggle(
                                "I reviewed the missed minimums and selected the deductions to apply",
                                isOn: reviewBinding(for: draft.child.id)
                            )
                            .font(.subheadline)
                        }
                        LabeledContent(
                            "Minimum deductions",
                            value: "-\(confirmedSettlement?.minimumMissDeductionPoints ?? draft.deductionPoints(applying: selectedRuleIDs(for: draft)))"
                        )
                        LabeledContent(
                            "Final points",
                            value: "\(confirmedSettlement?.finalPoints ?? draft.finalPoints(applying: selectedRuleIDs(for: draft)))"
                        )
                        LabeledContent(
                            "Cash transfer",
                            value: (confirmedSettlement?.cashAmount ?? draft.cashAmount(applying: selectedRuleIDs(for: draft)))
                                .formatted(.currency(code: "USD"))
                        )
                        LabeledContent(
                            "Debt carried out",
                            value: "\(confirmedSettlement?.debtCarriedOut ?? draft.debtCarriedOut(applying: selectedRuleIDs(for: draft)))"
                        )

                        if confirmedSettlement != nil {
                            Label("Settlement confirmed", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Confirm settlement") {
                                confirm(draft)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                !canConfirm ||
                                (!draft.minimumMissDeductions.isEmpty && !reviewedMinimumDeductions.contains(draft.child.id))
                            )
                        }
                    }
                }
            }
            .navigationTitle("Weekly Settlement")
            .onChange(of: selectedWeekEnding) {
                appliedMinimumDeductions.removeAll()
                reviewedMinimumDeductions.removeAll()
            }
        }
    }

    private func selectedRuleIDs(for draft: SettlementDraft) -> Set<UUID> {
        appliedMinimumDeductions[draft.child.id] ?? []
    }

    private func deductionBinding(for deduction: MinimumMissDeduction, childID: UUID) -> Binding<Bool> {
        Binding(
            get: { appliedMinimumDeductions[childID, default: []].contains(deduction.ruleID) },
            set: { isApplied in
                var selected = appliedMinimumDeductions[childID, default: []]
                if isApplied {
                    selected.insert(deduction.ruleID)
                } else {
                    selected.remove(deduction.ruleID)
                }
                appliedMinimumDeductions[childID] = selected
                reviewedMinimumDeductions.remove(childID)
            }
        )
    }

    private func reviewBinding(for childID: UUID) -> Binding<Bool> {
        Binding(
            get: { reviewedMinimumDeductions.contains(childID) },
            set: { isReviewed in
                if isReviewed {
                    reviewedMinimumDeductions.insert(childID)
                } else {
                    reviewedMinimumDeductions.remove(childID)
                }
            }
        )
    }

    private func isConfirmed(_ draft: SettlementDraft) -> Bool {
        confirmedSettlement(for: draft) != nil
    }

    private func confirmedSettlement(for draft: SettlementDraft) -> WeeklySettlement? {
        settlements.first {
            $0.childID == draft.child.id &&
            Calendar.current.isDate($0.weekEnding, inSameDayAs: draft.weekEnding)
        }
    }

    private func confirm(_ draft: SettlementDraft) {
        guard canConfirm,
              !isConfirmed(draft),
              draft.minimumMissDeductions.isEmpty || reviewedMinimumDeductions.contains(draft.child.id) else {
            return
        }

        let selectedRuleIDs = selectedRuleIDs(for: draft)
        let selectedDeductions = draft.minimumMissDeductions.filter { selectedRuleIDs.contains($0.ruleID) }
        let deductionPoints = draft.deductionPoints(applying: selectedRuleIDs)

        modelContext.insert(
            WeeklySettlement(
                childID: draft.child.id,
                weekEnding: draft.weekEnding,
                startingPoints: draft.startingPoints,
                debtCarriedIn: draft.debtCarriedIn,
                approvedEntryPoints: draft.approvedEntryPoints,
                parentPotShare: draft.parentPotShare,
                minimumMissDeductionPoints: deductionPoints,
                minimumMissDeductionDetails: selectedDeductions
                    .map {
                        "\($0.title) (\($0.period.title.lowercased()), \($0.completedQuantity.formatted()) of \($0.requiredQuantity.formatted()) completed): -\($0.points)"
                    }
                    .joined(separator: "; "),
                finalPoints: draft.finalPoints(applying: selectedRuleIDs),
                cashAmount: draft.cashAmount(applying: selectedRuleIDs),
                debtCarriedOut: draft.debtCarriedOut(applying: selectedRuleIDs),
                confirmedBy: appleIDManager.currentFamilyMember?.name ?? "Parent"
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


private func ordinal(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: value)) ?? "#\(value)"
}
