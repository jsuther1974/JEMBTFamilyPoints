import SwiftData
import SwiftUI

@main
struct JEMBTFamilyPointsTrackerApp: App {
    private let modelContainer: ModelContainer
    @State private var appleIDManager = AppleIDManager()

    init() {
        do {
            let schema = Schema([
                AllowanceFamily.self,
                FamilyInvitation.self,
                FamilyMembership.self,
                FamilyMember.self,
                RuleTemplate.self,
                LedgerEntry.self,
                WeeklySettlement.self,
                AppleIDMapping.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            try SeedData.seedIfNeeded(in: modelContainer.mainContext)
        } catch {
            fatalError("Unable to initialize the point ledger: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if appleIDManager.isSignedIn, appleIDManager.currentFamily != nil {
                ContentView()
                    .environment(appleIDManager)
            } else {
                SignInWithAppleView()
                    .environment(appleIDManager)
            }
        }
        .modelContainer(modelContainer)
    }
}

