import SwiftData
import SwiftUI

struct UITestLaunchConfiguration: Equatable {
    enum Scenario: String {
        case signedInDemoParent = "signed-in-demo-parent"
        case signedInEmptyAdministrator = "signed-in-empty-administrator"
    }

    let usesIsolatedStore: Bool
    let scenario: Scenario?
    let disablesAudio: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        usesIsolatedStore = environment["UITEST_ISOLATED_STORE"] == "1"
        scenario = usesIsolatedStore ? environment["UITEST_SCENARIO"].flatMap(Scenario.init(rawValue:)) : nil
        disablesAudio = usesIsolatedStore && environment["UITEST_DISABLE_AUDIO"] == "1"
    }
}

enum UITestScenarioFixtures {
    static let demoParentAppleID = "ui-fixture-demo-parent@example.invalid"
    static let administratorAppleID = "ui-fixture-administrator@example.invalid"

    @MainActor
    static func establish(
        _ scenario: UITestLaunchConfiguration.Scenario,
        manager: AppleIDManager,
        context: ModelContext
    ) throws {
        switch scenario {
        case .signedInDemoParent:
            let familyID = SeedData.demoFamilyID
            guard let family = try context.fetch(
                FetchDescriptor<AllowanceFamily>(predicate: #Predicate { $0.id == familyID })
            ).first,
            let member = try context.fetch(
                FetchDescriptor<FamilyMember>(predicate: #Predicate {
                    $0.familyID == familyID && $0.name == "Parent Example One"
                })
            ).first else {
                throw FixtureError.missingDemoFamily
            }
            let membership = FamilyMembership(
                familyID: family.id,
                familyMemberID: member.id,
                appleID: demoParentAppleID,
                role: .familyAdmin
            )
            context.insert(membership)
            try context.save()
            manager.establishSession(
                appleID: demoParentAppleID,
                family: family,
                membership: membership,
                member: member
            )
        case .signedInEmptyAdministrator:
            _ = try manager.createFamily(
                named: "UI Test Family",
                administratorName: "UI Test Admin",
                for: administratorAppleID,
                modelContext: context
            )
        }
    }

    enum FixtureError: Error {
        case missingDemoFamily
    }
}

@main
struct JEMBTFamilyPointsTrackerApp: App {
    @UIApplicationDelegateAdaptor(FamilySharingAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var appleIDManager: AppleIDManager
    @State private var soundscape: SoundscapeDirector
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        do {
            let launchConfiguration = UITestLaunchConfiguration()
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
                isStoredInMemoryOnly: launchConfiguration.usesIsolatedStore,
                cloudKitDatabase: launchConfiguration.usesIsolatedStore ? .none : .automatic
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let manager = AppleIDManager()
            _appleIDManager = State(initialValue: manager)
            _soundscape = State(initialValue: SoundscapeDirector(disableAudio: launchConfiguration.disablesAudio))
            AppRuntimeDependencies.appleIDManager = manager
            AppRuntimeDependencies.modelContainer = modelContainer
            FamilySharingCoordinator.shared.configure(modelContainer: modelContainer)
            try SeedData.seedIfNeeded(in: modelContainer.mainContext)
            if let scenario = launchConfiguration.scenario {
                try UITestScenarioFixtures.establish(
                    scenario,
                    manager: manager,
                    context: modelContainer.mainContext
                )
            }
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