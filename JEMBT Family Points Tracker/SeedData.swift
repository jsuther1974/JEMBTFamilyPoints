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

        let ruleCount = try context.fetchCount(FetchDescriptor<RuleTemplate>())
        if ruleCount == 0 {
            rules.forEach(context.insert)
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

    static var rules: [RuleTemplate] {
        [
            rule("Homework", .household, .adjustment, 0,
                 "Weekly calculation: missed days and days beyond five."),
            rule("Make bed", .household, .adjustment, 0,
                 "Weekly calculation depends on total days completed."),
            rule("Feed dog AM/PM", .household, .adjustment, 0,
                 "Weekly calculation depends on total days completed."),
            rule("Set or clear dinner table", .household, .adjustment, -25,
                 "-25 for a missed assigned day; +25 for covering another person's day."),
            rule("Monthly bedroom cleaning", .household, .adjustment, -100,
                 "-100 when overdue; penalty doubles each overdue week; +50 for extra cleanings."),
            rule("Pick up shared-space belongings", .household, .adjustment, -100,
                 "-100 when weekly task is missed; overdue penalty doubles; +100 per day above three."),
            rule("Walk dog", .household, .reward, 50, "+50 per five minutes."),
            rule("Pick up dog poop", .household, .reward, 150, "+150 per half yard."),
            rule("Help wash dishes", .household, .reward, 50,
                 "+50 each for emptying sink, loading, unloading, or stacking."),
            rule("Help with laundry", .household, .reward, 50,
                 "+50 per basket; +10 when only handling own clothes."),
            rule("Clean bathroom except toilet", .household, .reward, 100),
            rule("Clean bathroom toilet", .household, .reward, 200),
            rule("Help clean common rooms", .household, .reward, 150,
                 "+150 per half hour, prorated; reduce by one-third per skipped area."),
            rule("Yard work", .household, .reward, 250,
                 "+250 per half hour, prorated."),
            rule("Spring window cleaning", .household, .reward, 150,
                 "+150 per hour, prorated."),
            rule("Wash car exterior", .household, .reward, 300),
            rule("Wash car interior", .household, .reward, 100),
            rule("Plan and cook dinner", .household, .reward, 150,
                 "Up to +50 tip; half points when the meal is not balanced."),
            rule("Read to or with family", .household, .reward, 1,
                 "Per-minute value varies from +1 to +5 for each participating child."),
            rule("Peacemaker Award", .behavior, .reward, 250),
            rule("Protector Award", .behavior, .reward, 200),
            rule("Advocate Award", .behavior, .reward, 100),
            rule("Spotlight Award", .behavior, .reward, 50),
            rule("Device use without permission", .behavior, .penalty, -25,
                 "First event is -25; value doubles for subsequent events."),
            rule("Minor swearing", .behavior, .penalty, -50),
            rule("Major swearing", .behavior, .penalty, -100),
            rule("Name-calling", .behavior, .penalty, -50),
            rule("Inappropriate potty humor", .behavior, .penalty, -50),
            rule("Shouting after warning", .behavior, .penalty, -25,
                 "One warning per event, then -25 for each correction."),
            rule("School misbehavior", .behavior, .penalty, -200),
            rule("Bullying behavior", .behavior, .penalty, -50,
                 "Starts at -50 and doubles up to -1600; private-parts offenses add -50 with the same multiplier."),
            rule("15 minutes extra screen time", .rewardStore, .purchase, -100,
                 "Prices double for successive daily extensions: 100, 200, 400, 800."),
            rule("Download a new free game", .rewardStore, .purchase, -500,
                 "Maximum once per week."),
            rule("Extra sweet", .rewardStore, .purchase, -300,
                 "Maximum once per week."),
            rule("Extra TV night", .rewardStore, .purchase, 0,
                 "Price was missing from the source document.", enabled: false),
            rule("Choose weekly movie-night selection", .rewardStore, .purchase, 0,
                 "Price was mentioned but not provided.", enabled: false)
        ]
    }

    private static func rule(
        _ title: String,
        _ category: RuleCategory,
        _ kind: EntryKind,
        _ points: Int,
        _ guidance: String = "",
        enabled: Bool = true
    ) -> RuleTemplate {
        RuleTemplate(
            title: title,
            category: category,
            kind: kind,
            defaultPoints: points,
            guidance: guidance,
            requiresApproval: true,
            isEnabled: enabled
        )
    }
}

