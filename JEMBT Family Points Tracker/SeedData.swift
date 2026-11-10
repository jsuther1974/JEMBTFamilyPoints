import Foundation
import SwiftData

enum SeedData {
    static func seedIfNeeded(in context: ModelContext) throws {
        let familyCount = try context.fetchCount(FetchDescriptor<AllowanceFamily>())
        if familyCount == 0 {
            let family = AllowanceFamily(
                id: demoFamilyID,
                name: "Demo Family",
                createdByAppleID: "seeded-demo"
            )
            context.insert(family)
            context.insert(
                FamilyInvitation(
                    familyID: demoFamilyID,
                    code: "DEMO-FAMILY",
                    role: .parent
                )
            )
        }

        let memberCount = try context.fetchCount(FetchDescriptor<FamilyMember>())
        if memberCount == 0 {
            familyMembers.forEach(context.insert)
        }

        let families = try context.fetch(FetchDescriptor<AllowanceFamily>())
        for family in families {
            try installDefaultRules(for: family, in: context)
        }

        try context.save()
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    static let demoFamilyID = UUID(uuidString: "E5D5D0A8-6D7C-4BD0-9C2B-4F7C8A5A0A11")!

    static var familyMembers: [FamilyMember] {
        [
            FamilyMember(
                familyID: demoFamilyID,
                name: "Mateo",
                birthDate: date(2016, 3, 19),
                role: .child
            ),
            FamilyMember(
                familyID: demoFamilyID,
                name: "Emilio",
                birthDate: date(2018, 12, 30),
                role: .child
            ),
            FamilyMember(
                familyID: demoFamilyID,
                name: "Daddy",
                birthDate: date(1974, 4, 1),
                role: .parent
            ),
            FamilyMember(
                familyID: demoFamilyID,
                name: "Papa",
                birthDate: date(1968, 2, 12),
                role: .parent
            )
        ]
    }

    static func installDefaultRules(for family: AllowanceFamily, in context: ModelContext) throws {
        let familyID = family.id
        let count = try context.fetchCount(FetchDescriptor<RuleTemplate>(predicate: #Predicate {
            $0.familyID == familyID
        }))
        guard count == 0 else { return }
        let rules = defaultRules(for: familyID)
        rules.forEach(context.insert)
        if let bullying = rules.first(where: { $0.title == "Bullying behavior" }) {
            context.insert(
                RuleRider(
                    ruleID: bullying.id,
                    title: "Unwelcome physical touching",
                    details: "Includes unwelcome or inappropriate touching or joking.",
                    multiplier: 4
                )
            )
        }
        if let reading = rules.first(where: { $0.title == "Read to or with family" }) {
            context.insert(
                RuleRider(
                    ruleID: reading.id,
                    title: "Attentive sibling reading",
                    details: "Siblings read to one another and listen attentively.",
                    multiplier: 2
                )
            )
        }
    }

    static func defaultRules(for familyID: UUID) -> [RuleTemplate] {
        [
            rule("Homework", .household, .adjustment, 0,
                 "Complete assigned homework for the day.", familyID: familyID, icon: "book.closed.fill", unit: .day, minimum: 4, maximum: 7),
            rule("Make bed", .household, .adjustment, 0,
                 "Make the bed without being reminded.", familyID: familyID, icon: "bed.double.fill", unit: .day, minimum: 4, maximum: 7),
            rule("Feed dog AM/PM", .household, .adjustment, 0,
                 "Feed the dog as assigned each day.", familyID: familyID, icon: "dog.fill", unit: .day, minimum: 4, maximum: 7),
            rule("Set or clear dinner table", .household, .adjustment, -25,
                 "Points for each missed assigned day.", familyID: familyID, icon: "fork.knife", unit: .occurrence),
            rule("Monthly bedroom cleaning", .household, .adjustment, -100,
                 "Penalty when the monthly cleaning is overdue.", familyID: familyID, icon: "bed.double", unit: .occurrence, accelerator: true),
            rule("Pick up shared-space belongings", .household, .adjustment, -100,
                 "Penalty when belongings are left in shared spaces.", familyID: familyID, icon: "shippingbox.fill"),
            rule("Walk dog", .household, .reward, 50, "Earn points for each walking interval.", familyID: familyID, icon: "figure.walk", unit: .fifteenMinutes),
            rule("Pick up dog poop", .household, .reward, 150, "Earn points for each completed area.", familyID: familyID, icon: "dog.fill", unit: .task),
            rule("Help wash dishes", .household, .reward, 50,
                 "Empty the sink, load or unload the dishwasher, or stack dishes.", familyID: familyID, icon: "sink.fill", unit: .task),
            rule("Help with laundry", .household, .reward, 50,
                 "Wash, dry, fold, or put away a basket of laundry.", familyID: familyID, icon: "washer.fill", unit: .task),
            rule("Clean bathroom except toilet", .household, .reward, 100, familyID: familyID, icon: "sparkles", unit: .task),
            rule("Clean bathroom toilet", .household, .reward, 200, familyID: familyID, icon: "toilet.fill", unit: .task),
            rule("Help clean common rooms", .household, .reward, 150,
                 "Help clean shared family spaces.", familyID: familyID, icon: "house.fill", unit: .thirtyMinutes),
            rule("Yard work", .household, .reward, 250,
                 "Mow, rake, weed, or complete another yard task.", familyID: familyID, icon: "leaf.fill", unit: .thirtyMinutes),
            rule("Spring window cleaning", .household, .reward, 150,
                 "Clean windows and frames.", familyID: familyID, icon: "window.vertical.closed", unit: .hour),
            rule("Wash car exterior", .household, .reward, 300, familyID: familyID, icon: "car.fill", unit: .task),
            rule("Wash car interior", .household, .reward, 100, familyID: familyID, icon: "car.side.fill", unit: .task),
            rule("Plan and cook dinner", .household, .reward, 150,
                 "Plan and prepare a balanced family dinner.", familyID: familyID, icon: "frying.pan.fill", unit: .task),
            rule("Read to or with family", .household, .reward, 1,
                 "Read aloud to family members or listen attentively.", familyID: familyID, icon: "books.vertical.fill", unit: .minute),
            rule("Peacemaker Award", .behavior, .reward, 250, familyID: familyID, icon: "heart.circle.fill"),
            rule("Protector Award", .behavior, .reward, 200, familyID: familyID, icon: "shield.fill"),
            rule("Advocate Award", .behavior, .reward, 100, familyID: familyID, icon: "person.2.wave.2.fill"),
            rule("Spotlight Award", .behavior, .reward, 50, familyID: familyID, icon: "lightbulb.fill"),
            rule("Device use without permission", .behavior, .penalty, -25,
                 "The penalty doubles with each additional occurrence.", familyID: familyID, icon: "ipad.and.iphone", accelerator: true),
            rule("Minor swearing", .behavior, .penalty, -50, familyID: familyID, icon: "text.bubble.fill"),
            rule("Major swearing", .behavior, .penalty, -100, familyID: familyID, icon: "exclamationmark.bubble.fill"),
            rule("Name-calling", .behavior, .penalty, -50, familyID: familyID, icon: "person.crop.circle.badge.exclamationmark"),
            rule("Inappropriate potty humor", .behavior, .penalty, -50, familyID: familyID, icon: "face.smiling.inverse"),
            rule("Shouting after warning", .behavior, .penalty, -25,
                 "The first occurrence is a warning; points accrue afterward.", familyID: familyID, icon: "speaker.wave.3.fill", warnings: 1),
            rule("School misbehavior", .behavior, .penalty, -200, familyID: familyID, icon: "building.columns.fill"),
            rule("Bullying behavior", .behavior, .penalty, -50,
                 "Starts at -50 and doubles for repeated occurrences.", familyID: familyID, icon: "hand.raised.fill", accelerator: true),
            rule("15 minutes extra screen time", .rewardStore, .purchase, -100,
                 "Up to four extra 15-minute extensions are available each week.", familyID: familyID, icon: "display", unit: .fifteenMinutes, inventory: 4, inventoryPeriod: .weekly, shelfPosition: 0),
            rule("Download a new free game", .rewardStore, .purchase, -500,
                 "Maximum once per week.", familyID: familyID, icon: "gamecontroller.fill", maximum: 1, inventory: 1, inventoryPeriod: .weekly, shelfPosition: 1),
            rule("Extra sweet", .rewardStore, .purchase, -300,
                 "Maximum once per day.", familyID: familyID, icon: "birthday.cake.fill", maximum: 1, inventory: 1, inventoryPeriod: .daily, shelfPosition: 2),
            rule("Extra TV night", .rewardStore, .purchase, 0,
                 "Set a price before enabling this prize.", familyID: familyID, icon: "tv.fill", enabled: false, shelfPosition: 3),
            rule("Choose weekly movie-night selection", .rewardStore, .purchase, 0,
                 "Set a price before enabling this prize.", familyID: familyID, icon: "popcorn.fill", enabled: false, shelfPosition: 4)
        ]
    }

    private static func rule(
        _ title: String,
        _ category: RuleCategory,
        _ kind: EntryKind,
        _ points: Int,
        _ guidance: String = "",
        familyID: UUID,
        icon: String = "star.fill",
        unit: RuleMeasurementUnit = .occurrence,
        minimum: Double? = nil,
        maximum: Double? = nil,
        warnings: Int = 0,
        accelerator: Bool = false,
        enabled: Bool = true,
        inventory: Int? = nil,
        inventoryPeriod: StoreInventoryPeriod = .weekly,
        shelfPosition: Int = 0
    ) -> RuleTemplate {
        RuleTemplate(
            familyID: familyID,
            title: title,
            category: category,
            kind: kind,
            defaultPoints: points,
            guidance: guidance,
            requiresApproval: true,
            isEnabled: enabled,
            iconName: icon,
            measurementUnit: unit,
            minimumTarget: minimum,
            maximumTarget: maximum,
            warningUnits: warnings,
            acceleratorEnabled: false,
            frequencyKind: unit.frequencyKind,
            countSchedule: .every,
            frequencyValue: unit.frequencyValue,
            timeUnit: unit.timeUnit,
            growthEnabled: accelerator,
            growthKind: .percentage,
            growthAmount: 100,
            storeInventoryLimit: inventory,
            storeInventoryPeriod: inventoryPeriod,
            storeShelfPosition: shelfPosition
        )
    }
}

private extension RuleMeasurementUnit {
    var frequencyKind: RuleFrequencyKind {
        switch self {
        case .minute, .fifteenMinutes, .thirtyMinutes, .hour, .day: .time
        case .occurrence, .item, .task: .count
        }
    }

    var frequencyValue: Double {
        switch self {
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        default: 1
        }
    }

    var timeUnit: RuleTimeUnit {
        switch self {
        case .minute, .fifteenMinutes, .thirtyMinutes: .minute
        case .hour: .hour
        case .day: .day
        case .occurrence, .item, .task: .day
        }
    }
}

