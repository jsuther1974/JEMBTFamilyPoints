import SwiftData
import SwiftUI

struct RuleCatalogView: View {
    @Environment(AppleIDManager.self) private var appleIDManager

    private var canEdit: Bool {
        appleIDManager.currentMembership?.role.canManageRules == true
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(RuleCatalog.allCases) { catalog in
                    NavigationLink {
                        RuleCatalogListView(catalog: catalog)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(catalog.title)
                                    .font(.headline)
                                Text(catalog.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: catalog.iconName)
                                .font(.title2)
                                .foregroundStyle(catalog.tint)
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !canEdit {
                    Section {
                        Label("Parents can customize these items. Other family members can view them.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Rules")
        }
    }
}

private struct RuleCatalogListView: View {
    let catalog: RuleCatalog
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RuleTemplate.title) private var allRules: [RuleTemplate]
    @Query private var allRiders: [RuleRider]
    @State private var showingAdd = false
    @State private var editingRule: RuleTemplate?
    @State private var errorMessage: String?

    private var canEdit: Bool {
        appleIDManager.currentMembership?.role.canManageRules == true
    }

    private var rules: [RuleTemplate] {
        guard let familyID = appleIDManager.currentFamily?.id else { return [] }
        return allRules.filter {
            $0.familyID == familyID && $0.catalog == catalog && (canEdit || $0.isEnabled)
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if rules.isEmpty {
                ContentUnavailableView(
                    "No \(catalog.title)",
                    systemImage: catalog.iconName,
                    description: Text(canEdit ? "Add the first item." : "A family administrator can add items.")
                )
            } else {
                ForEach(rules) { rule in
                    NavigationLink {
                        RuleDetailView(
                            rule: rule,
                            riders: riders(for: rule),
                            canEdit: canEdit,
                            onEdit: { editingRule = rule }
                        )
                    } label: {
                        RuleRow(rule: rule)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canEdit {
                            Button("Delete", role: .destructive) { delete(rule) }
                            Button("Edit") { editingRule = rule }
                                .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle(catalog.title)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add \(catalog.singularTitle)", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            RuleEditorView(catalog: catalog) { draft in
                try save(draft, replacing: nil)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(catalog: catalog, rule: rule, riders: riders(for: rule)) { draft in
                try save(draft, replacing: rule)
            }
        }
    }

    private func riders(for rule: RuleTemplate) -> [RuleRider] {
        allRiders.filter { $0.ruleID == rule.id }.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func save(_ draft: RuleDraft, replacing rule: RuleTemplate?) throws {
        guard canEdit, let familyID = appleIDManager.currentFamily?.id else {
            throw RuleEditingError.notAuthorized
        }
        let target = rule ?? RuleTemplate(
            familyID: familyID,
            title: draft.title,
            category: draft.category,
            kind: catalog.entryKind,
            defaultPoints: draft.signedPoints(for: catalog)
        )
        if rule == nil { modelContext.insert(target) }

        target.familyID = familyID
        target.title = draft.title
        target.category = draft.category
        target.kind = catalog.entryKind
        target.defaultPoints = draft.signedPoints(for: catalog)
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
        target.warningUnits = 0
        target.acceleratorEnabled = false
        target.requiresApproval = true
        target.isEnabled = true
        try modelContext.save()
        errorMessage = nil
    }

    private func delete(_ rule: RuleTemplate) {
        guard canEdit else { return }
        riders(for: rule).forEach(modelContext.delete)
        modelContext.delete(rule)
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "The item could not be deleted: \(error.localizedDescription)"
        }
    }
}

private struct RuleRow: View {
    let rule: RuleTemplate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.iconName)
                .font(.title2)
                .frame(width: 30)
                .foregroundStyle(rule.catalog.tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.title)
                        .font(.headline)
                    if !rule.isEnabled {
                        Text("Disabled")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text(rule.pointSummary)
                    .font(.subheadline)
                    .foregroundStyle(rule.defaultPoints < 0 ? .red : .secondary)
                if !rule.guidance.isEmpty {
                    Text(rule.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RuleDetailView: View {
    let rule: RuleTemplate
    let riders: [RuleRider]
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: rule.iconName)
                        .font(.system(size: 42))
                        .frame(width: 58, height: 58)
                        .foregroundStyle(rule.catalog.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.title).font(.title3.bold())
                        Text(rule.pointSummary).foregroundStyle(.secondary)
                    }
                }
            }

            if !rule.guidance.isEmpty {
                Section("Description") { Text(rule.guidance) }
            }

            Section("How points are awarded") {
                Text(rule.frequencyDescription)
                Text("Point awards start on the \(ordinal(rule.firstAwardNumber)) award.")
                if let lastAward = rule.lastAwardNumber {
                    Text("Point awards end after award \(lastAward).")
                }
            }

            if rule.growthEnabled {
                Section("How the value changes") {
                    Text(rule.growthDescription)
                }
            }
        }
        .navigationTitle(rule.catalog.singularTitle)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", action: onEdit)
                }
            }
        }
    }
}

private struct RuleEditorView: View {
    let catalog: RuleCatalog
    let onSave: (RuleDraft) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RuleDraft
    @State private var validationMessage: String?
    @State private var showingIconPicker = false

    init(
        catalog: RuleCatalog,
        rule: RuleTemplate? = nil,
        riders: [RuleRider] = [],
        onSave: @escaping (RuleDraft) throws -> Void
    ) {
        self.catalog = catalog
        self.onSave = onSave
        _draft = State(initialValue: RuleDraft(catalog: catalog, rule: rule, riders: riders))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingIconPicker = true
                    } label: {
                        LabeledContent("Icon") {
                            Image(systemName: draft.iconName)
                                .font(.title2)
                        }
                    }
                    TextField("Name", text: $draft.title)
                    TextField("Description", text: $draft.details, axis: .vertical)
                        .lineLimit(3...7)
                } header: {
                    Text("Item")
                } footer: {
                    Text("Describe what someone must do—or what prize they receive—so the rule is easy for everyone to understand.")
                }

                Section {
                    LabeledContent(catalog.pointsQuestion) {
                        HStack(spacing: 8) {
                            TextField("Points", value: $draft.pointsMagnitude, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 85)
                            Stepper("", value: $draft.pointsMagnitude, in: 0...100_000, step: 25)
                                .labelsHidden()
                        }
                    }
                } header: {
                    Text("Point value")
                } footer: {
                    Text(catalog.pointsHelp)
                }

                Section {
                    Picker("Measure by", selection: $draft.frequencyKind) {
                        ForEach(RuleFrequencyKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.frequencyKind == .count {
                        Picker("How often", selection: $draft.countSchedule) {
                            ForEach(RuleCountSchedule.allCases) { schedule in
                                Text(schedule.title).tag(schedule)
                            }
                        }
                        .pickerStyle(.segmented)
                        if draft.countSchedule == .every {
                            HStack {
                                Text("Give points every")
                                Spacer()
                                TextField("Count", value: $draft.frequencyCount, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 55)
                                Text(draft.frequencyCount == 1 ? "time" : "times")
                            }
                        }
                    } else {
                        HStack {
                            Text("Give points every")
                            Spacer()
                            TextField("Time", value: $draft.frequencyCount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 55)
                            Picker("Time unit", selection: $draft.timeUnit) {
                                ForEach(RuleTimeUnit.allCases) { unit in
                                    Text(unit.label(for: Double(draft.frequencyCount))).tag(unit)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("How often are points awarded?")
                } footer: {
                    Text("Count works for occurrences such as each chore completed. Time works for activities measured in minutes, hours, days, weeks, or months.")
                }

                Section {
                    Stepper(
                        "Point awards start on the \(ordinal(draft.firstAward)) award",
                        value: $draft.firstAward,
                        in: 1...100
                    )
                    Toggle("Stop awarding points", isOn: $draft.hasLastAward)
                    if draft.hasLastAward {
                        LabeledContent("Awards end after") {
                            HStack {
                                TextField("Award", value: $draft.lastAward, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 55)
                                Stepper("", value: $draft.lastAward, in: draft.firstAward...10_000)
                                    .labelsHidden()
                            }
                        }
                    }
                } header: {
                    Text("When do point awards start and stop?")
                } footer: {
                    Text("Choose a later starting award when the first few times do not count. Add an ending award to cap the total for the week.")
                }

                Section {
                    Toggle("Value grows with each additional award", isOn: $draft.growthEnabled)
                    if draft.growthEnabled {
                        Picker("Value grows by", selection: $draft.growthKind) {
                            ForEach(RuleGrowthKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        LabeledContent(draft.growthKind == .fixedPoints ? "Points added each time" : "Percentage added each time") {
                            HStack {
                                TextField("Growth", value: $draft.growthAmount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                Text(draft.growthKind == .percentage ? "%" : "points")
                            }
                        }
                    }
                } header: {
                    Text("Should the point value grow?")
                } footer: {
                    Text("For example, a 100% increase makes 100 points become 200, then 400, then 800. A 25-point increase makes 100 become 125, then 150, then 175.")
                }

                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(draft.isExisting ? "Edit \(catalog.singularTitle)" : "New \(catalog.singularTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                RuleIconPicker(selectedIcon: $draft.iconName)
            }
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else {
            validationMessage = "Enter a name."
            return
        }
        guard draft.pointsMagnitude >= 0, draft.frequencyCount >= 1 else {
            validationMessage = "Enter valid point and frequency values."
            return
        }
        if draft.hasLastAward, draft.lastAward < draft.firstAward {
            validationMessage = "The ending award cannot come before the starting award."
            return
        }
        do {
            try onSave(draft)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct RuleIconPicker: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 58))]

    private var symbols: [RuleSymbol] {
        let all = RuleSymbol.library
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.keywords.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(symbols) { symbol in
                        Button {
                            selectedIcon = symbol.name
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: symbol.name)
                                    .font(.title2)
                                    .frame(height: 28)
                                if selectedIcon == symbol.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol.keywords)
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search icons")
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct RuleDraft {
    var isExisting: Bool
    var title: String
    var details: String
    var iconName: String
    var category: RuleCategory
    var pointsMagnitude: Int
    var frequencyKind: RuleFrequencyKind
    var countSchedule: RuleCountSchedule
    var frequencyCount: Int
    var timeUnit: RuleTimeUnit
    var firstAward: Int
    var hasLastAward: Bool
    var lastAward: Int
    var growthEnabled: Bool
    var growthKind: RuleGrowthKind
    var growthAmount: Double

    @MainActor
    init(catalog: RuleCatalog, rule: RuleTemplate?, riders: [RuleRider]) {
        isExisting = rule != nil
        title = rule?.title ?? ""
        details = rule?.guidance ?? ""
        iconName = rule?.iconName ?? catalog.iconName
        category = rule?.category ?? (catalog == .tradingPost ? .rewardStore : .household)
        pointsMagnitude = abs(rule?.defaultPoints ?? 0)
        frequencyKind = rule?.frequencyKind ?? .count
        countSchedule = rule?.countSchedule ?? .every
        frequencyCount = max(1, Int(rule?.frequencyValue ?? 1))
        timeUnit = rule?.timeUnit ?? .day
        firstAward = max(1, Int(rule?.minimumTarget ?? 1), (rule?.warningUnits ?? 0) + 1)
        hasLastAward = rule?.maximumTarget != nil
        lastAward = max(firstAward, Int(rule?.maximumTarget ?? Double(firstAward)))
        growthEnabled = rule?.growthEnabled == true || rule?.acceleratorEnabled == true
        growthKind = rule?.growthEnabled == true ? (rule?.growthKind ?? .percentage) : .percentage
        growthAmount = rule?.growthEnabled == true
            ? (rule?.growthAmount ?? 100)
            : max(0, ((rule?.acceleratorMultiplier ?? 2) - 1) * 100)
    }

    func signedPoints(for catalog: RuleCatalog) -> Int {
        catalog == .incentives ? abs(pointsMagnitude) : -abs(pointsMagnitude)
    }
}

private struct RuleSymbol: Identifiable {
    let name: String
    let keywords: String
    var id: String { name }

    static let library: [RuleSymbol] = [
        .init(name: "star.fill", keywords: "star award favorite"),
        .init(name: "heart.fill", keywords: "heart kind caring"),
        .init(name: "heart.circle.fill", keywords: "peacemaker kindness"),
        .init(name: "sparkles", keywords: "clean sparkle"),
        .init(name: "house.fill", keywords: "house home rooms chores"),
        .init(name: "bed.double.fill", keywords: "bed bedroom make bed"),
        .init(name: "sink.fill", keywords: "sink dishes kitchen bubbles"),
        .init(name: "washer.fill", keywords: "washer laundry clothes"),
        .init(name: "fork.knife", keywords: "food table dishes dinner"),
        .init(name: "frying.pan.fill", keywords: "cook dinner kitchen"),
        .init(name: "toilet.fill", keywords: "bathroom toilet clean"),
        .init(name: "window.vertical.closed", keywords: "window clean"),
        .init(name: "shippingbox.fill", keywords: "box organize pickup belongings"),
        .init(name: "leaf.fill", keywords: "yard garden outdoors"),
        .init(name: "car.fill", keywords: "car wash vehicle"),
        .init(name: "dog.fill", keywords: "dog pet feed walk"),
        .init(name: "pawprint.fill", keywords: "pet animal"),
        .init(name: "figure.walk", keywords: "walk exercise dog"),
        .init(name: "book.closed.fill", keywords: "book homework school read"),
        .init(name: "books.vertical.fill", keywords: "books reading family"),
        .init(name: "pencil", keywords: "homework writing school"),
        .init(name: "graduationcap.fill", keywords: "school learn achievement"),
        .init(name: "clock.fill", keywords: "time minute hour"),
        .init(name: "timer", keywords: "timer duration interval"),
        .init(name: "display", keywords: "screen computer time"),
        .init(name: "tv.fill", keywords: "television movie screen"),
        .init(name: "gamecontroller.fill", keywords: "game prize play"),
        .init(name: "popcorn.fill", keywords: "movie night prize"),
        .init(name: "birthday.cake.fill", keywords: "sweet cake dessert"),
        .init(name: "gift.fill", keywords: "gift prize reward"),
        .init(name: "storefront.fill", keywords: "store trading post prize"),
        .init(name: "shield.fill", keywords: "protect safety"),
        .init(name: "hand.raised.fill", keywords: "stop bullying touching"),
        .init(name: "person.2.fill", keywords: "family people siblings"),
        .init(name: "person.2.wave.2.fill", keywords: "advocate help people"),
        .init(name: "lightbulb.fill", keywords: "idea spotlight"),
        .init(name: "exclamationmark.bubble.fill", keywords: "warning words swearing"),
        .init(name: "speaker.wave.3.fill", keywords: "shouting noise loud"),
        .init(name: "ipad.and.iphone", keywords: "device phone tablet"),
        .init(name: "checkmark.circle.fill", keywords: "complete done success")
    ]
}

private enum RuleEditingError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        "Only a family administrator can change rule items."
    }
}

private extension RuleCatalog {
    var singularTitle: String {
        switch self {
        case .incentives: "Incentive"
        case .disincentives: "Disincentive"
        case .tradingPost: "Prize"
        }
    }

    var tint: Color {
        switch self {
        case .incentives: .green
        case .disincentives: .red
        case .tradingPost: .purple
        }
    }

    var pointsQuestion: String {
        switch self {
        case .incentives: "Points earned for each award"
        case .disincentives: "Points lost for each occurrence"
        case .tradingPost: "Points needed for this reward"
        }
    }

    var pointsHelp: String {
        switch self {
        case .incentives: "These points are added to the family member’s weekly total each time an award is earned."
        case .disincentives: "These points are subtracted from the family member’s weekly total. Enter a positive number; the app handles the subtraction."
        case .tradingPost: "These points are deducted when the family member chooses this reward. Enter a positive number; the app handles the deduction."
        }
    }
}

private extension RuleTemplate {
    var pointSummary: String {
        let sign = defaultPoints > 0 ? "+" : ""
        return "\(sign)\(defaultPoints.formatted()) points • \(frequencyDescription)"
    }

    var frequencyDescription: String {
        if frequencyKind == .count {
            return countSchedule == .once
                ? "Awarded once"
                : "Awarded every \(max(1, frequencyValue).formatted()) time\(frequencyValue == 1 ? "" : "s")"
        }
        return "Awarded every \(max(1, frequencyValue).formatted()) \(timeUnit.label(for: max(1, frequencyValue)))"
    }

    var growthDescription: String {
        switch growthKind {
        case .fixedPoints:
            "Each additional award changes the value by \(growthAmount.formatted()) points."
        case .percentage:
            "Each additional award increases the previous value by \(growthAmount.formatted())%."
        }
    }
}

private func ordinal(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: value)) ?? "#\(value)"
}
