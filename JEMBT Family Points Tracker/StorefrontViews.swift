import SwiftData
import SwiftUI

enum StorefrontEngine {
    static func storeName(for familyName: String?) -> String {
        let trimmedName = familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Family Reward Mart" : trimmedName
    }

    static func canUseChildStorefront(
        memberRole: MemberRole?,
        membershipRole: FamilyMembershipRole?
    ) -> Bool {
        memberRole == .child && membershipRole == .child
    }

    static func purchaseCount(
        for rule: RuleTemplate,
        entries: [LedgerEntry],
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        entries.count { entry in
            guard entry.ruleID == rule.id,
                  entry.kind == .purchase,
                  entry.status == .approved else { return false }

            switch rule.storeInventoryPeriod {
            case .daily:
                return calendar.isDate(entry.occurredAt, inSameDayAs: date)
            case .weekly:
                return calendar.isDate(
                    entry.weekEnding,
                    inSameDayAs: PointsEngine.weekEnding(containing: date, calendar: calendar)
                )
            case .total:
                return true
            }
        }
    }

    static func remainingQuantity(
        for rule: RuleTemplate,
        entries: [LedgerEntry],
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard let limit = rule.storeInventoryLimit else { return nil }
        return max(0, limit - purchaseCount(for: rule, entries: entries, at: date, calendar: calendar))
    }

    static func canAfford(_ rule: RuleTemplate, balance: Int) -> Bool {
        balance >= abs(rule.defaultPoints)
    }
}

struct FamilyStorefrontView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query private var allMembers: [FamilyMember]
    @Query private var allRules: [RuleTemplate]
    @Query private var allEntries: [LedgerEntry]
    @Query private var allSettlements: [WeeklySettlement]
    @State private var pendingPurchase: RuleTemplate?
    @State private var editingRule: RuleTemplate?
    @State private var showingAddItem = false
    @State private var errorMessage: String?
    @State private var purchaseMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    private var familyID: UUID? { appleIDManager.currentFamily?.id }
    private var storeName: String { StorefrontEngine.storeName(for: appleIDManager.currentFamily?.name) }

    private var familyMembers: [FamilyMember] {
        guard let familyID else { return [] }
        return allMembers.filter { $0.familyID == familyID && $0.isActive }
    }

    private var currentChild: FamilyMember? {
        guard StorefrontEngine.canUseChildStorefront(
            memberRole: appleIDManager.currentFamilyMember?.role,
            membershipRole: appleIDManager.currentMembership?.role
        ) else { return nil }
        return appleIDManager.currentFamilyMember
    }

    private var canManage: Bool {
        appleIDManager.currentMembership?.role.canManageRules == true
    }

    private var canPurchase: Bool {
        currentChild != nil
    }

    private var storeItems: [RuleTemplate] {
        allRules.filter {
            $0.familyID == familyID &&
            $0.catalog == .tradingPost &&
            (canManage || $0.isEnabled)
        }.sorted {
            if $0.storeShelfPosition != $1.storeShelfPosition {
                return $0.storeShelfPosition < $1.storeShelfPosition
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var familyEntries: [LedgerEntry] {
        let memberIDs = Set(familyMembers.map(\.id))
        return allEntries.filter { memberIDs.contains($0.memberID) }
    }

    private var currentWeekEnding: Date { PointsEngine.weekEnding(containing: .now) }

    private var balance: Int {
        guard let currentChild else { return 0 }
        return PointsEngine.settlementDrafts(
            weekEnding: currentWeekEnding,
            members: familyMembers,
            entries: familyEntries,
            settlements: allSettlements.filter { $0.childID == currentChild.id },
            rules: allRules.filter { $0.familyID == familyID }
        ).first(where: { $0.child.id == currentChild.id })?.finalPoints ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StoreAwningView()

                VStack(spacing: 14) {
                    storeSign
                    balanceHeader

                    if storeItems.isEmpty && !canManage {
                        ContentUnavailableView(
                            "The Store Is Empty",
                            systemImage: "shippingbox",
                            description: Text("A parent can add rewards soon.")
                        )
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(storeItems) { item in
                                StoreShelfItemView(
                                    item: item,
                                    remaining: StorefrontEngine.remainingQuantity(for: item, entries: familyEntries),
                                    balance: currentChild == nil ? nil : balance,
                                    canPurchase: canPurchase,
                                    canEdit: canManage
                                ) {
                                    if canManage {
                                        editingRule = item
                                    } else {
                                        pendingPurchase = item
                                    }
                                }
                            }

                            if canManage {
                                AddStoreItemView {
                                    showingAddItem = true
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(StoreInteriorBackground())
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.brown.opacity(0.35), lineWidth: 2)
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.12), Color.brown.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle(storeName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddItem) {
            RuleEditorView(catalog: .tradingPost) { draft in
                try save(draft, replacing: nil)
            }
            .presentationDetents([.large])
            .presentationCornerRadius(28)
            .presentationBackground(.regularMaterial)
        }
        .sheet(item: $editingRule) { item in
            RuleEditorView(catalog: .tradingPost, rule: item) { draft in
                try save(draft, replacing: item)
            }
            .presentationDetents([.large])
            .presentationCornerRadius(28)
            .presentationBackground(.regularMaterial)
        }
        .confirmationDialog(
            "Buy \(pendingPurchase?.title ?? "this reward")?",
            isPresented: Binding(
                get: { pendingPurchase != nil },
                set: { if !$0 { pendingPurchase = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingPurchase {
                Button("Buy for \(abs(item.defaultPoints).formatted()) points") {
                    purchase(item)
                }
            }
            Button("Cancel", role: .cancel) { pendingPurchase = nil }
        } message: {
            Text("The points will be deducted immediately.")
        }
        .alert("Storefront", isPresented: Binding(
            get: { errorMessage != nil || purchaseMessage != nil },
            set: { if !$0 { errorMessage = nil; purchaseMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil; purchaseMessage = nil }
        } message: {
            Text(errorMessage ?? purchaseMessage ?? "")
        }
    }

    private var storeSign: some View {
        VStack(spacing: 5) {
            Text(storeName)
                .font(.system(.title, design: .rounded, weight: .black))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
            Text("FAMILY REWARDS • OPEN TODAY")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.yellow.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [.purple.opacity(0.95), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.yellow.opacity(0.7), lineWidth: 2)
                .padding(4)
        }
        .shadow(color: .black.opacity(0.28), radius: 5, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storefrontSign")
    }

    @ViewBuilder
    private var balanceHeader: some View {
        VStack(spacing: 8) {
            if let currentChild {
                Text(currentChild.name)
                    .font(.headline)
                Text("\(balance.formatted()) points to spend")
                    .font(.title2.bold())
                    .foregroundStyle(.purple)
                    .contentTransition(.numericText())
            } else if canManage {
                Text("Manage the family store")
                    .font(.headline)
                Text("Review inventory or use Manage Items to update the shelves.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Store inventory")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.7))
        }
    }

    private func purchase(_ item: RuleTemplate) {
        defer { pendingPurchase = nil }
        guard canPurchase, let child = currentChild else {
            errorMessage = "Only a child can purchase rewards from their own account."
            return
        }
        guard item.isEnabled, item.familyID == familyID, item.catalog == .tradingPost else {
            errorMessage = "This item is no longer available."
            return
        }
        guard StorefrontEngine.remainingQuantity(for: item, entries: familyEntries).map({ $0 > 0 }) ?? true else {
            errorMessage = "Sorry, this item just sold out."
            return
        }
        guard StorefrontEngine.canAfford(item, balance: balance) else {
            errorMessage = "You no longer have enough points for this item."
            return
        }

        let now = Date.now
        let recorder = child.name
        modelContext.insert(
            LedgerEntry(
                memberID: child.id,
                ruleID: item.id,
                occurredAt: now,
                weekEnding: PointsEngine.weekEnding(containing: now),
                title: item.title,
                notes: "Purchased in the Family Storefront",
                points: -abs(item.defaultPoints),
                kind: .purchase,
                status: .approved,
                submittedBy: recorder,
                reviewedBy: "Family Storefront",
                reviewedAt: now,
                quantity: 1,
                measurementUnit: .item
            )
        )

        do {
            try modelContext.save()
            purchaseMessage = "You bought \(item.title)!"
        } catch {
            modelContext.rollback()
            errorMessage = "The purchase could not be completed: \(error.localizedDescription)"
        }
    }

    private func save(_ draft: RuleDraft, replacing rule: RuleTemplate?) throws {
        guard canManage, let familyID else {
            throw RuleEditingError.notAuthorized
        }

        let target = rule ?? RuleTemplate(
            familyID: familyID,
            title: draft.title,
            category: draft.category,
            kind: RuleCatalog.tradingPost.entryKind,
            defaultPoints: draft.signedPoints(for: .tradingPost)
        )
        if rule == nil {
            target.storeShelfPosition = (storeItems.map(\.storeShelfPosition).max() ?? -1) + 1
            modelContext.insert(target)
        }

        target.familyID = familyID
        target.title = draft.title
        target.category = draft.category
        target.kind = RuleCatalog.tradingPost.entryKind
        target.defaultPoints = draft.signedPoints(for: .tradingPost)
        target.guidance = draft.details
        target.iconName = draft.iconName
        target.frequencyKind = draft.frequencyKind
        target.countSchedule = draft.countSchedule
        target.frequencyValue = Double(draft.frequencyCount)
        target.timeUnit = draft.timeUnit
        target.minimumTarget = Double(draft.firstAward)
        target.maximumTarget = draft.hasLastAward ? Double(draft.lastAward) : nil
        target.growthEnabled = draft.growthEnabled
        target.growthKind = draft.growthKind
        target.growthAmount = draft.growthAmount
        target.deductStartingPointsWhenMinimumMissed = draft.deductStartingPointsWhenMinimumMissed
        target.minimumPeriod = draft.minimumPeriod
        target.storeInventoryLimit = draft.hasInventoryLimit ? draft.inventoryLimit : nil
        target.storeInventoryPeriod = draft.inventoryPeriod
        target.warningUnits = 0
        target.acceleratorEnabled = false
        target.requiresApproval = true
        target.isEnabled = draft.isEnabled
        try modelContext.save()
    }
}

private struct StoreAwningView: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? Color.purple.gradient : Color.white.gradient)
            }
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 2) ? Color.purple : Color.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
            .offset(y: 9)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 4)
        .accessibilityHidden(true)
    }
}

private struct StoreInteriorBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.99, green: 0.95, blue: 0.83), Color(red: 0.91, green: 0.83, blue: 0.68)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 44) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.brown.opacity(0.08))
                        .frame(height: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StoreShelfItemView: View {
    let item: RuleTemplate
    let remaining: Int?
    let balance: Int?
    let canPurchase: Bool
    let canEdit: Bool
    let onSelect: () -> Void

    private var soldOut: Bool { remaining == 0 }
    private var affordable: Bool {
        balance.map { StorefrontEngine.canAfford(item, balance: $0) } ?? true
    }
    private var purchasable: Bool { canPurchase && item.isEnabled && affordable && !soldOut }
    private var dimmedForChild: Bool { canPurchase && !affordable && !soldOut }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                VStack(spacing: 5) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.9), .cyan.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(alignment: .topLeading) {
                                Capsule()
                                    .fill(.white.opacity(0.7))
                                    .frame(width: 24, height: 3)
                                    .rotationEffect(.degrees(-35))
                                    .padding(6)
                            }

                        Ellipse()
                            .fill(.black.opacity(0.12))
                            .frame(width: 42, height: 8)
                            .blur(radius: 2)
                            .padding(.bottom, 6)

                        Image(systemName: item.iconName)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                purchasable || !canPurchase ? Color.purple : Color.secondary,
                                purchasable || !canPurchase ? Color.orange : Color.gray
                            )
                            .font(.system(size: 31, weight: .semibold))
                            .shadow(color: .black.opacity(0.24), radius: 3, y: 4)
                            .padding(.bottom, 10)
                    }
                    .frame(height: 66)

                    ZStack {
                        VStack(spacing: 2) {
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text("\(abs(item.defaultPoints).formatted()) points")
                                .font(.caption2.bold())
                                .foregroundStyle(.purple)
                            if let remaining {
                                Text("\(remaining) \(item.storeInventoryPeriod.remainingLabel)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Available")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                            if let balance, !affordable && !soldOut {
                                Text("Need \((abs(item.defaultPoints) - balance).formatted()) more")
                                    .font(.system(size: 8, weight: .bold))
                            } else if canEdit, !item.isEnabled {
                                Text("Hidden")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(5)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color(red: 1, green: 0.98, blue: 0.84), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.brown.opacity(0.35))
                        }

                        if soldOut {
                            Text("SOLD OUT")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.red, in: RoundedRectangle(cornerRadius: 5))
                                .rotationEffect(.degrees(-9))
                                .shadow(radius: 2)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(
                    purchasable
                        ? AnyShapeStyle(LinearGradient(colors: [.yellow.opacity(0.48), .orange.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.brown.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.8), lineWidth: 2)
                }

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.brown, Color(red: 0.28, green: 0.12, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 8)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 4)
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(height: 2)
                }
                .padding(.horizontal, -6)
            }
            .grayscale(dimmedForChild || (!item.isEnabled && canEdit) ? 1 : 0)
            .opacity(dimmedForChild || (!item.isEnabled && canEdit) ? 0.48 : 1)
            .shadow(color: purchasable ? .yellow.opacity(0.9) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!canEdit && !purchasable)
        .accessibilityLabel("\(item.title), \(abs(item.defaultPoints)) points")
        .accessibilityValue(!item.isEnabled ? "Hidden from children" : soldOut ? "Sold out" : affordable ? "Available to buy" : "Cannot afford")
        .accessibilityHint(canEdit ? "Double tap to edit" : purchasable ? "Double tap to purchase" : "")
        .accessibilityIdentifier("storeItem-\(item.id.uuidString)")
    }
}

private struct AddStoreItemView: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Add item")
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 138)
            .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.purple.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            }
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.brown, Color(red: 0.28, green: 0.12, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addStoreItem")
    }
}
