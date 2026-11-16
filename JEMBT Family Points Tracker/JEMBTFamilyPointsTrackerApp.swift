import SwiftData
import SwiftUI

@main
struct JEMBTFamilyPointsTrackerApp: App {
    @UIApplicationDelegateAdaptor(FamilySharingAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var appleIDManager = AppleIDManager()
    @State private var soundscape = SoundscapeDirector()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let isIsolatedUITest = ProcessInfo.processInfo.environment["UITEST_ISOLATED_STORE"] == "1"
            let schema = Schema([
                AllowanceFamily.self,
                FamilyInvitation.self,
                FamilyMembership.self,
                FamilyMember.self,
                RuleTemplate.self,
                RuleRider.self,
                LedgerEntry.self,
                WeeklySettlement.self,
                AppleIDMapping.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: isIsolatedUITest,
                cloudKitDatabase: isIsolatedUITest ? .none : .automatic
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            FamilySharingCoordinator.shared.configure(modelContainer: modelContainer)
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
                    .environment(soundscape)
            } else {
                SignInWithAppleView()
                    .environment(appleIDManager)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, appleIDManager.isSignedIn else { return }
            Task { @MainActor in
                try? await FamilySharingCoordinator.shared.synchronize(
                    session: MutationSession(appleIDManager: appleIDManager)
                )
            }
        }
        .modelContainer(modelContainer)
    }
}