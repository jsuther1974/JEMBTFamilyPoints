import SwiftData
import SwiftUI
#if canImport(AudioToolbox)
import AudioToolbox
#endif

private struct PointChangeNotice: Identifiable {
    let id = UUID()
    let points: Int

    var title: String { points > 0 ? "Points gained!" : "Points changed" }
    var message: String {
        points > 0
            ? "+\(points.formatted()) points were added to your account."
            : "\(abs(points).formatted()) points were deducted from your account."
    }
    var symbolName: String { points > 0 ? "sparkles" : "arrow.down.circle.fill" }
    var color: Color { points > 0 ? .green : .orange }
}

struct ContentView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(SoundscapeDirector.self) private var soundscape
    @Query private var entries: [LedgerEntry]
    @State private var selectedTab = "family"
    @State private var reportingPeriod = ReportingPeriod()
    @State private var observedPointTotal: Int?
    @State private var pointChangeNotice: PointChangeNotice?
    @State private var soundscapeOwner = UUID()
    
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
                FamilyStatisticsView()
            }
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag("statistics")
            NavigationStack {
                ManageFamilyView()
            }
            .tabItem { Label("Family", systemImage: "person.3.fill") }
            .tag("family")
        }
        .environment(reportingPeriod)
        .background { WatchSnapshotSyncView() }
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

                    Button {
                        soundscape.isEnabled.toggle()
                    } label: {
                        Label(
                            soundscape.isEnabled ? "Turn Sounds Off" : "Turn Sounds On",
                            systemImage: soundscape.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                        )
                    }

                    Divider()
                    
                    Button("Sign Out", action: signOut)
                } label: {
                    Image(systemName: "person.circle.fill")
                }
            }
        }
        .overlay(alignment: .top) {
            if let pointChangeNotice {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pointChangeNotice.title).font(.headline)
                        Text(pointChangeNotice.message).font(.caption)
                    }
                } icon: {
                    Image(systemName: pointChangeNotice.symbolName)
                        .font(.title2)
                }
                .foregroundStyle(pointChangeNotice.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("pointChangeNotice")
            }
        }
        .onAppear {
            observedPointTotal = currentUserPointTotal
            soundscape.enter(soundscapeScene, owner: soundscapeOwner)
        }
        .onDisappear { soundscape.leave(owner: soundscapeOwner) }
        .onChange(of: selectedTab) {
            soundscape.enter(soundscapeScene, owner: soundscapeOwner)
        }
        .onChange(of: currentUserPointTotal) { _, newTotal in
            showPointChange(from: observedPointTotal, to: newTotal)
        }
    }

    private var currentUserPointTotal: Int {
        guard let memberID = appleIDManager.currentFamilyMember?.id else { return 0 }
        return entries
            .filter {
                $0.memberID == memberID &&
                $0.status == .approved &&
                $0.kind != .purchase
            }
            .reduce(0) { $0 + $1.points }
    }

    private var soundscapeScene: SoundscapeDirector.Scene {
        switch selectedTab {
        case "storefront": .storefront
        case "rules": .rules
        case "ledger": .ledger
        case "statistics": .statistics
        default: .family
        }
    }

    private func showPointChange(from oldTotal: Int?, to newTotal: Int) {
        defer { observedPointTotal = newTotal }
        guard let oldTotal, oldTotal != newTotal else { return }
        let notice = PointChangeNotice(points: newTotal - oldTotal)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            pointChangeNotice = notice
        }
        soundscape.play(notice.points > 0 ? .pointsGained : .pointsLost)
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard pointChangeNotice?.id == notice.id else { return }
            withAnimation { pointChangeNotice = nil }
        }
    }
    
    private func signOut() {
        soundscape.stop()
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
    @Environment(\.dismiss) private var dismiss
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
    @State private var selectedWeekEnding: Date?
    @State private var completionMessage: String?
    @State private var showingFinalCelebration = false

    private var familyMembers: [FamilyMember] {
        members.filter { $0.familyID == appleIDManager.currentFamily?.id }
    }

    private var familyEntries: [LedgerEntry] {
        let memberIDs = Set(familyMembers.map(\.id))
        return entries.filter { memberIDs.contains($0.memberID) }
    }

    private var familySettlements: [WeeklySettlement] {
        let memberIDs = Set(familyMembers.map(\.id))
        return settlements.filter { memberIDs.contains($0.childID) }
    }

    private var familyRules: [RuleTemplate] {
        rules.filter { $0.familyID == appleIDManager.currentFamily?.id }
    }

    private var activeWeekEndings: [Date] {
        PointsEngine.activePastWeekEndings(
            members: familyMembers,
            entries: familyEntries,
            settlements: familySettlements,
            rules: familyRules,
            cashValuePerPoint: appleIDManager.currentFamily?.effectiveCashValuePerPoint ?? Decimal(string: "0.01")!
        )
    }

    private var effectiveWeekEnding: Date {
        selectedWeekEnding ?? activeWeekEndings.first ?? PointsEngine.previousWeekEnding(before: PointsEngine.weekEnding(containing: .now))
    }

    private var canConfirm: Bool {
        appleIDManager.currentMembership?.role.canManageRules == true
    }

    private var drafts: [SettlementDraft] {
        guard !activeWeekEndings.isEmpty else { return [] }
        let familyMembers = members.filter { $0.familyID == appleIDManager.currentFamily?.id }
        let ids = Set(familyMembers.map(\.id))
        return PointsEngine.settlementDrafts(
            weekEnding: effectiveWeekEnding,
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
            weekEnding: effectiveWeekEnding,
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
                if activeWeekEndings.isEmpty {
                    ContentUnavailableView(
                        "All Prior Weeks Are Closed",
                        systemImage: "checkmark.seal.fill",
                        description: Text("There are no past weeks with active transactions to review.")
                    )
                } else {
                    Picker("Week ending", selection: Binding(
                        get: { effectiveWeekEnding },
                        set: { selectedWeekEnding = $0 }
                    )) {
                        ForEach(activeWeekEndings, id: \.self) { weekEnding in
                            Text(weekEnding.formatted(date: .abbreviated, time: .omitted))
                                .tag(weekEnding)
                        }
                    }
                    .accessibilityIdentifier("settlementWeekPicker")
                }

                if let completionMessage {
                    Label(completionMessage, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("settlementCompletionMessage")
                }

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
                            Button("Close This Week", action: requestGlobalConfirmation)
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
            .navigationTitle("Review and Close")
            .overlay {
                if showingFinalCelebration {
                    ClosingCelebrationView()
                        .transition(.opacity)
                        .accessibilityIdentifier("closingCelebration")
                }
            }
            .alert(
                "Reject waiting items and close this week?",
                isPresented: $showingPendingWarning
            ) {
                Button("Not Yet", role: .cancel) {}
                Button("Reject Waiting & Close", role: .destructive) {
                    confirmAll(rejectingPending: true)
                }
            } message: {
                Text("\(pendingEntriesForWeek.count) item\(pendingEntriesForWeek.count == 1 ? " is" : "s are") still waiting for parent review. Continuing will reject all waiting items in this week before settlement.")
            }
            .onAppear {
                if selectedWeekEnding == nil {
                    selectedWeekEnding = activeWeekEndings.first
                }
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
        let fingerprint = PointsEngine.transactionFingerprint(
            weekEnding: draft.weekEnding,
            memberIDs: Set(familyMembers.map(\.id)),
            entries: familyEntries
        )
        return settlements.first {
            $0.childID == draft.child.id &&
            $0.transactionFingerprint == fingerprint &&
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
        let closedWeek = effectiveWeekEnding
        let reviewer = appleIDManager.currentFamilyMember?.name ?? "Parent"
        let memberIDs = Set(familyMembers.map(\.id))
        if rejectingPending {
            PointsEngine.rejectPendingEntriesBeforeSettlement(
                weekEnding: closedWeek,
                memberIDs: memberIDs,
                entries: entries,
                reviewedBy: reviewer,
                reviewedAt: .now
            )
        }

        let fingerprint = PointsEngine.transactionFingerprint(
            weekEnding: closedWeek,
            memberIDs: memberIDs,
            entries: entries
        )
        let distributedPoints = unconfirmedDrafts.reduce(0) { total, draft in
            let selectedRuleIDs = draft.selectedRuleIDs(from: decisions(for: draft))
            return total + max(0, draft.finalPoints(applying: selectedRuleIDs))
        }
        for settlement in familySettlements where Calendar.current.isDate(settlement.weekEnding, inSameDayAs: closedWeek) {
            modelContext.delete(settlement)
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
                transactionFingerprint: fingerprint,
                confirmedBy: reviewer
            ))
        }

        do {
            try modelContext.save()
            errorMessage = nil
            showingPendingWarning = false
            completionMessage = "Congratulations! You closed the week ending \(closedWeek.formatted(date: .numeric, time: .omitted)) and distributed \(distributedPoints.formatted()) points!"
            minimumMissDecisions.removeAll()
            expandedChildren.removeAll()

            let remainingWeeks = activeWeekEndings.filter {
                !Calendar.current.isDate($0, inSameDayAs: closedWeek)
            }
            if let nextWeek = remainingWeeks.first {
                selectedWeekEnding = nextWeek
            } else {
                celebrateAndReturn()
            }
        } catch {
            modelContext.rollback()
            errorMessage = "The week could not be closed: \(error.localizedDescription)"
        }
    }

    private func celebrateAndReturn() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showingFinalCelebration = true
        }
        #if canImport(AudioToolbox)
        AudioServicesPlaySystemSound(1025)
        #endif
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            dismiss()
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
                    quickActivity = QuickActivityRequest(member: child, kind: kind, weekEnding: effectiveWeekEnding)
                }
            }
        } label: {
            Image(systemName: kind.quickActionSymbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(kind == .reward ? Color.green : Color.red)
                .frame(width: 48, height: 44)
                .background(
                    (kind == .reward ? Color.green : Color.red).opacity(0.14),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .reward ? "Assign award" : "Assign penalty")
    }
}

private struct ClosingCelebrationView: View {
    @State private var falling = false
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()
                ForEach(0..<36, id: \.self) { index in
                    let x = CGFloat((index * 47) % 101) / 100 * proxy.size.width
                    let size = CGFloat(8 + (index % 4) * 4)
                    Group {
                        if index.isMultiple(of: 7) {
                            Image(systemName: "balloon.2.fill")
                                .font(.system(size: size + 10))
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .frame(width: size, height: size * 0.55)
                                .rotationEffect(.degrees(Double(index * 31)))
                        }
                    }
                    .foregroundStyle(colors[index % colors.count])
                    .position(x: x, y: falling ? proxy.size.height + 40 : -40)
                    .animation(
                        .easeIn(duration: 1.6 + Double(index % 5) * 0.12)
                            .delay(Double(index % 9) * 0.04),
                        value: falling
                    )
                }

                VStack(spacing: 12) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Congratulations!")
                        .font(.title.bold())
                    Text("You closed the books for all prior weeks!")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding()
            }
            .onAppear { falling = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Congratulations! You closed the books for all prior weeks!")
    }
}

private func ordinal(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: value)) ?? "#\(value)"
}
