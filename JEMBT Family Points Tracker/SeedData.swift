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
        let existingRules = try context.fetch(FetchDescriptor<RuleTemplate>(predicate: #Predicate {
            $0.familyID == familyID
        }))
        if shouldReplaceLegacyCatalog(existingRules) {
            let legacyRuleIDs = Set(existingRules.filter { legacyDefaultTitles.contains($0.title) }.map(\.id))
            let riders = try context.fetch(FetchDescriptor<RuleRider>())
            riders.filter { legacyRuleIDs.contains($0.ruleID) }.forEach(context.delete)
            existingRules.filter { legacyRuleIDs.contains($0.id) }.forEach(context.delete)
        } else if !existingRules.isEmpty {
            return
        }
        let rules = defaultRules(for: familyID)
        rules.forEach(context.insert)
    }

    private static func shouldReplaceLegacyCatalog(_ rules: [RuleTemplate]) -> Bool {
        rules.count >= 20 && rules.filter { legacyDefaultTitles.contains($0.title) }.count >= 15
    }

    private static let legacyDefaultTitles: Set<String> = [
        "Homework", "Make bed", "Feed dog AM/PM", "Set or clear dinner table",
        "Monthly bedroom cleaning", "Pick up shared-space belongings", "Walk dog",
        "Pick up dog poop", "Help wash dishes", "Help with laundry",
        "Clean bathroom except toilet", "Clean bathroom toilet", "Help clean common rooms",
        "Yard work", "Spring window cleaning", "Wash car exterior", "Wash car interior",
        "Plan and cook dinner", "Read to or with family", "Peacemaker Award",
        "Protector Award", "Advocate Award", "Spotlight Award", "Device use without permission",
        "Minor swearing", "Major swearing", "Name-calling", "Inappropriate potty humor",
        "Shouting after warning", "School misbehavior", "Bullying behavior",
        "15 minutes extra screen time", "Download a new free game", "Extra sweet",
        "Extra TV night", "Choose weekly movie-night selection"
    ]

    static func defaultRules(for familyID: UUID) -> [RuleTemplate] {
        [
            rule("Wash the dishes", .household, .reward, 75,
                 "Wash dishes, load or unload the dishwasher, or clear and stack dishes.", familyID: familyID, icon: "sink.fill", unit: .task),
            rule("Make your bed", .household, .reward, 40,
                 "Make the bed without being reminded. Points begin after completing four days in the week.", familyID: familyID, icon: "bed.double.fill", unit: .day, minimum: 4, maximum: 7),
            rule("Clean your room", .household, .reward, 250,
                 "Complete a thorough bedroom cleaning once during the week.", familyID: familyID, icon: "sparkles", unit: .task, maximum: 1, countSchedule: .once),
            rule("Help with laundry", .household, .reward, 75,
                 "Wash, dry, fold, or put away a basket of laundry.", familyID: familyID, icon: "washer.fill", unit: .basket),
            rule("Rake the leaves", .household, .reward, 200,
                 "Rake and bag leaves for each 30-minute work interval.", familyID: familyID, icon: "leaf.fill", unit: .thirtyMinutes),
            rule("Wash the car", .household, .reward, 300,
                 "Wash and dry the outside of the family car.", familyID: familyID, icon: "car.fill", unit: .task),

            rule("Swearing", .behavior, .penalty, -50,
                 "Points lost for each occurrence.", familyID: familyID, icon: "exclamationmark.bubble.fill"),
            rule("Name calling", .behavior, .penalty, -75,
                 "Points lost for calling another person an unkind name.", familyID: familyID, icon: "person.crop.circle.badge.exclamationmark"),
            rule("Unapproved device use", .behavior, .penalty, -100,
                 "The point loss doubles with each additional occurrence during the week.", familyID: familyID, icon: "ipad.and.iphone", accelerator: true),
            rule("School misbehavior", .behavior, .penalty, -200,
                 "Points lost for a verified school behavior incident.", familyID: familyID, icon: "building.columns.fill"),

            rule("Extra 15 minutes of screen time", .rewardStore, .purchase, -100,
                 "Up to four extra 15-minute extensions are available each week.", familyID: familyID, icon: "display", unit: .fifteenMinutes, inventory: 4, inventoryPeriod: .weekly, shelfPosition: 0),
            rule("Extra sweet", .rewardStore, .purchase, -150,
                 "One extra sweet is available each day.", familyID: familyID, icon: "birthday.cake.fill", maximum: 1, inventory: 1, inventoryPeriod: .daily, shelfPosition: 1),
            rule("Stay up late", .rewardStore, .purchase, -400,
                 "Stay up later than the usual bedtime once this week, with parent approval.", familyID: familyID, icon: "moon.stars.fill", maximum: 1, inventory: 1, inventoryPeriod: .weekly, shelfPosition: 2),
            rule("Pick game for Family Game Night", .rewardStore, .purchase, -250,
                 "Choose the game the family plays at the next Family Game Night.", familyID: familyID, icon: "gamecontroller.fill", maximum: 1, inventory: 1, inventoryPeriod: .weekly, shelfPosition: 3)
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
        countSchedule: RuleCountSchedule = .every,
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
            countSchedule: countSchedule,
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
        case .occurrence, .item, .basket, .task: .count
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
        case .occurrence, .item, .basket, .task: .day
        }
    }
}

