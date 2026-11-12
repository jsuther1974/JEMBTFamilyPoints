import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @State private var selectedTab = "family"
    @State private var reportingPeriod = ReportingPeriod()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FamilyStorefrontView()
            }
                .tabItem { Label("Store", systemImage: "storefront.fill") }
                .tag("storefront")
            RuleCatalogView()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
                .tag("rules")
            NavigationStack {
                WeeklyLedgerView()
            }
                .tabItem { Label("Ledger", systemImage: "tablecells") }
                .tag("ledger")
            NavigationStack {
                ManageFamilyView()
            }
            .tabItem { Label("Family", systemImage: "person.3.fill") }
            .tag("family")
        }
        .environment(reportingPeriod)
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
    @Environment(ReportingPeriod.self) private var reportingPeriod
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \RuleTemplate.title) private var allRules: [RuleTemplate]

    @State private var selectedMemberID: UUID?
    @State private var selectedRuleID: UUID?
    @State private var quantity = 1.0
    @State private var points = 0
    @State private var notes = ""
    @State private var selectedWeekdays: Set<Int> = [Calendar.current.component(.weekday, from: Date.now)]
    @State private var errorMessage: String?

    private var rules: [RuleTemplate] {
        allRules.filter {
            $0.familyID == appleIDManager.currentFamily?.id &&
            $0.isEnabled &&
            (submissionKind != .caregiverRecommendation || $0.catalog != .tradingPost) &&
            (selectedMember == nil || $0.isEligible(for: selectedMember!, at: reportingPeriod.weekEnding))
        }
    }

    private var selectedMember: FamilyMember? {
        familyMembers.first { $0.id == selectedMemberID }
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
                .onChange(of: selectedMemberID) {
                    if let selectedRule, let selectedMember,
                       !selectedRule.isEligible(for: selectedMember, at: reportingPeriod.weekEnding) {
                        selectedRuleID = nil
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
                    Section("Days occurred") {
                        WeekdaySelector(
                            weekEnding: reportingPeriod.weekEnding,
                            selection: $selectedWeekdays
                        )
                    }

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
                    .disabled(selectedMemberID == nil || selectedRuleID == nil || selectedWeekdays.isEmpty)
            }
            .navigationTitle("Record Activity")
        }
    }

    private func save() {
        guard
            let member = selectedMember,
            let rule = selectedRule
        else {
            errorMessage = "Select a family member and rule."
            return
        }

        let weekEnding = reportingPeriod.weekEnding
        guard rule.isEligible(for: member, at: weekEnding) else {
            errorMessage = "This item is not available for the selected child’s age."
            return
        }
        let recorder = appleIDManager.currentFamilyMember?.name ?? submissionKind.submittedBy
        for occurredAt in PointsEngine.dates(inWeekEnding: weekEnding, matchingWeekdays: selectedWeekdays) {
            modelContext.insert(
                LedgerEntry(
                    memberID: member.id,
                    ruleID: rule.id,
                    occurredAt: occurredAt,
                    weekEnding: weekEnding,
                    title: rule.title,
                    notes: notes,
                    points: points,
                    kind: rule.kind,
                    status: submissionKind.requiresParentApproval ? .pending : .approved,
                    submittedBy: recorder,
                    reviewedBy: submissionKind.requiresParentApproval ? nil : recorder,
                    reviewedAt: submissionKind.requiresParentApproval ? nil : .now,
                    quantity: quantity,
                    measurementUnit: rule.measurementUnit,
                    riderTitle: nil
                )
            )
        }

        do {
            try modelContext.save()
            selectedRuleID = nil
            quantity = 1
            points = 0
            notes = ""
            selectedWeekdays = [Calendar.current.component(.weekday, from: Date.now)]
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

struct SettlementView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(ReportingPeriod.self) private var reportingPeriod
    @Environment(\.modelContext) private var modelContext
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @Query private var settlements: [WeeklySettlement]
    @Query private var rules: [RuleTemplate]
    @State private var errorMessage: String?
    @State private var minimumMissDecisions: [UUID: [UUID: MinimumMissDecision]] = [:]
    @State private var expandedChildren: Set<UUID> = []
    @State private var showingPendingWarning = false
    @State private var quickActivity: QuickActivityRequest?

    private var selectedWeekEnding: Date { reportingPeriod.weekEnding }

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
            rules: rules.filter { $0.familyID == appleIDManager.currentFamily?.id },
            cashValuePerPoint: appleIDManager.currentFamily?.effectiveCashValuePerPoint ?? Decimal(string: "0.01")!
        )
    }

    private var pendingEntriesForWeek: [LedgerEntry] {
        let ids = Set(members.filter { $0.familyID == appleIDManager.currentFamily?.id }.map(\.id))
        return PointsEngine.pendingEntriesForReview(
            weekEnding: selectedWeekEnding,
            memberIDs: ids,
            entries: entries
        )
    }

    private var unconfirmedDrafts: [SettlementDraft] {
        drafts.filter { confirmedSettlement(for: $0) == nil }
    }

    private var allDecisionsComplete: Bool {
        unconfirmedDrafts.allSatisfy {
            $0.decisionsAreComplete(minimumMissDecisions[$0.child.id] ?? [:])
        }
    }

    private var children: [FamilyMember] { drafts.map(\.child) }

    var body: some View {
        NavigationStack {
            List {
                ReportingWeekPicker()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Section("Family settlements") {
                    ForEach(drafts) { draft in
                        DisclosureGroup(
                            isExpanded: expansionBinding(for: draft.child.id)
                        ) {
                            settlementDetails(for: draft)
                        } label: {
                            settlementSummary(for: draft)
                        }
                        .accessibilityIdentifier("settlementRow-\(draft.child.name)")
                    }
                }

                if canConfirm {
                    Section {
                        HStack(spacing: 12) {
                            activityMenu(kind: .reward)
                            activityMenu(kind: .penalty)
                            Button("Confirm settlement", action: requestGlobalConfirmation)
                                .buttonStyle(.borderedProminent)
                                .disabled(unconfirmedDrafts.isEmpty || !allDecisionsComplete)
                                .accessibilityIdentifier("confirmGlobalSettlement")
                        }
                    } footer: {
                        if !allDecisionsComplete {
                            Text("Deduct or absolve every missed requirement before closing the books.")
                        }
                    }
                }
            }
            .navigationTitle("Weekly Settlement")
            .alert(
                "Reject waiting items and close the books?",
                isPresented: $showingPendingWarning
            ) {
                Button("Not Yet", role: .cancel) {}
                Button("Reject Waiting & Settle", role: .destructive) {
                    confirmAll(rejectingPending: true)
                }
            } message: {
                Text("\(pendingEntriesForWeek.count) item\(pendingEntriesForWeek.count == 1 ? " is" : "s are") still waiting for parent review. Continuing will reject all waiting items in this week before settlement.")
            }
            .onChange(of: selectedWeekEnding) {
                minimumMissDecisions.removeAll()
                expandedChildren.removeAll()
            }
            .sheet(item: $quickActivity) { request in
                QuickActivityView(member: request.member, kind: request.kind, weekEnding: request.weekEnding)
            }
        }
    }

    private func decisions(for draft: SettlementDraft) -> [UUID: MinimumMissDecision] {
        minimumMissDecisions[draft.child.id] ?? [:]
    }

    private func decisionBinding(for deduction: MinimumMissDeduction, childID: UUID) -> Binding<MinimumMissDecision?> {
        Binding(
            get: { minimumMissDecisions[childID]?[deduction.ruleID] },
            set: { decision in
                minimumMissDecisions[childID, default: [:]][deduction.ruleID] = decision
            }
        )
    }

    private func expansionBinding(for childID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedChildren.contains(childID) },
            set: { expanded in
                if expanded {
                    expandedChildren.insert(childID)
                } else {
                    expandedChildren.remove(childID)
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

    private func requestGlobalConfirmation() {
        guard allDecisionsComplete, !unconfirmedDrafts.isEmpty else { return }
        if pendingEntriesForWeek.isEmpty {
            confirmAll()
        } else {
            showingPendingWarning = true
        }
    }

    private func confirmAll(rejectingPending: Bool = false) {
        guard canConfirm, allDecisionsComplete, !unconfirmedDrafts.isEmpty else { return }
        let reviewer = appleIDManager.currentFamilyMember?.name ?? "Parent"
        if rejectingPending {
            let memberIDs = Set(members.filter { $0.familyID == appleIDManager.currentFamily?.id }.map(\.id))
            PointsEngine.rejectPendingEntriesBeforeSettlement(
                weekEnding: selectedWeekEnding,
                memberIDs: memberIDs,
                entries: entries,
                reviewedBy: reviewer,
                reviewedAt: .now
            )
        }

        for draft in unconfirmedDrafts {
            let decisions = decisions(for: draft)
            let selectedRuleIDs = draft.selectedRuleIDs(from: decisions)
            let selectedDeductions = draft.minimumMissDeductions.filter { selectedRuleIDs.contains($0.ruleID) }
            let deductionPoints = draft.deductionPoints(applying: selectedRuleIDs)
            modelContext.insert(WeeklySettlement(
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
                minimumMissReviewDetails: draft.minimumMissReviewDescription(decisions),
                finalPoints: draft.finalPoints(applying: selectedRuleIDs),
                cashAmount: draft.cashAmount(applying: selectedRuleIDs),
                debtCarriedOut: draft.debtCarriedOut(applying: selectedRuleIDs),
                confirmedBy: reviewer
            ))
        }

        do {
            try modelContext.save()
            errorMessage = nil
            showingPendingWarning = false
        } catch {
            modelContext.rollback()
            errorMessage = "The settlement could not be saved: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func settlementDetails(for draft: SettlementDraft) -> some View {
        let confirmed = confirmedSettlement(for: draft)
        let decisions = decisions(for: draft)
        let selectedIDs = draft.selectedRuleIDs(from: decisions)
        let breakdown = PointsEngine.settlementEntryBreakdown(
            for: draft.child.id,
            weekEnding: draft.weekEnding,
            entries: entries
        )
        let finalPoints = confirmed?.finalPoints ?? draft.finalPoints(applying: selectedIDs)
        let debtOut = confirmed?.debtCarriedOut ?? draft.debtCarriedOut(applying: selectedIDs)

        LabeledContent("Starting points", value: "\(confirmed?.startingPoints ?? draft.startingPoints)")
        if (confirmed?.debtCarriedIn ?? draft.debtCarriedIn) < 0 {
            LabeledContent("Debt carried in", value: "\(confirmed?.debtCarriedIn ?? draft.debtCarriedIn)")
        }
        LabeledContent("Additional awards", value: "+\(breakdown.additionalAwards)")
        if breakdown.penalties > 0 {
            LabeledContent("Penalties", value: "-\(breakdown.penalties)")
        }
        ForEach(breakdown.purchases) { purchase in
            LabeledContent(purchase.title, value: "-\(purchase.pointsSpent) pts")
            Text("\(purchase.quantity) purchased")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if confirmed == nil, !draft.minimumMissDeductions.isEmpty {
            HStack {
                Text("Missed required activities").font(.headline)
                Spacer()
                Button("Absolve All") {
                    minimumMissDecisions[draft.child.id] = Dictionary(
                        uniqueKeysWithValues: draft.minimumMissDeductions.map { ($0.ruleID, .absolve) }
                    )
                }
            }
            ForEach(draft.minimumMissDeductions) { deduction in
                VStack(alignment: .leading, spacing: 4) {
                    Text(deduction.title)
                    Text("\(deduction.period.title): \(deduction.completedQuantity.formatted()) of \(deduction.requiredQuantity.formatted()) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Decision", selection: decisionBinding(for: deduction, childID: draft.child.id)) {
                        Text("Choose").tag(nil as MinimumMissDecision?)
                        Text("Deduct \(deduction.points)").tag(MinimumMissDecision.deduct as MinimumMissDecision?)
                        Text("Absolve").tag(MinimumMissDecision.absolve as MinimumMissDecision?)
                    }
                    .pickerStyle(.segmented)
                }
            }
        } else if let reviewDetails = confirmed?.minimumMissReviewDetails, !reviewDetails.isEmpty {
            Text(reviewDetails).font(.caption).foregroundStyle(.secondary)
        }
        let deductionPoints = confirmed?.minimumMissDeductionPoints ?? draft.deductionPoints(applying: selectedIDs)
        if deductionPoints > 0 {
            LabeledContent("Missed required activities", value: "-\(deductionPoints)")
        }
        let cashValue = confirmed?.cashAmount ?? draft.cashAmount(applying: selectedIDs)
        let cashValueText = cashValue.formatted(.currency(code: "USD"))
        let rateText = draft.cashValuePerPoint.formatted(.currency(code: "USD"))
        Text("Cash value: \(cashValueText) at \(rateText) per point")
            .font(.caption)
            .foregroundStyle(.secondary)
        let parentShare = confirmed?.parentPotShare ?? draft.parentPotShare
        if parentShare > 0 {
            LabeledContent("Parent-penalty share", value: "+\(parentShare)")
        }
        if debtOut < 0 {
            LabeledContent("Debt carried out", value: "\(debtOut)").fontWeight(.semibold)
        } else {
            LabeledContent("Final points", value: "\(finalPoints)").fontWeight(.semibold)
        }
    }

    private func settlementSummary(for draft: SettlementDraft) -> some View {
        let confirmed = confirmedSettlement(for: draft)
        let selectedIDs = draft.selectedRuleIDs(from: decisions(for: draft))
        let points = confirmed?.finalPoints ?? draft.finalPoints(applying: selectedIDs)
        return HStack {
            Text(draft.child.name).font(.headline)
            Spacer()
            Text(points < 0 ? "\(abs(points)) debt" : "\(points) pts")
                .foregroundStyle(points < 0 ? .red : .secondary)
            if confirmed != nil {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
    }

    private func activityMenu(kind: EntryKind) -> some View {
        Menu {
            ForEach(children) { child in
                Button(child.name) {
                    quickActivity = QuickActivityRequest(member: child, kind: kind, weekEnding: selectedWeekEnding)
                }
            }
        } label: {
            Image(systemName: kind.quickActionSymbolName)
        }
        .accessibilityLabel(kind == .reward ? "Assign award" : "Assign penalty")
    }
}


private func ordinal(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: value)) ?? "#\(value)"
}
