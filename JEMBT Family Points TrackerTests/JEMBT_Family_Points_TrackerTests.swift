//
//  JEMBT_Family_Points_TrackerTests.swift
//  JEMBT Family Points TrackerTests
//

import Foundation
import SwiftData
import Testing
@testable import JEMBT_Family_Points_Tracker

private final class AudioSessionActivationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activationCount = 0
    private var activatedOnMainThread = false

    func recordActivation() {
        lock.withLock {
            activationCount += 1
            activatedOnMainThread = Thread.isMainThread
        }
    }

    var snapshot: (count: Int, onMainThread: Bool) {
        lock.withLock { (activationCount, activatedOnMainThread) }
    }
}

struct JEMBT_Family_Points_TrackerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func shippedSeedProfilesAreClearlySynthetic() {
        let members = SeedData.familyMembers

        #expect(members.count == 4)
        #expect(members.allSatisfy { $0.name.contains("Example") })
        #expect(members.filter { $0.role == .child }.count == 2)
        #expect(members.filter { $0.role == .parent }.count == 2)
    }

    @Test func scenarioAndAudioOverridesRequireIsolatedStore() {
        let nonisolated = UITestLaunchConfiguration(environment: [
            "UITEST_SCENARIO": "signed-in-demo-parent",
            "UITEST_DISABLE_AUDIO": "1"
        ])
        #expect(!nonisolated.usesIsolatedStore)
        #expect(nonisolated.scenario == nil)
        #expect(!nonisolated.disablesAudio)

        let isolated = UITestLaunchConfiguration(environment: [
            "UITEST_ISOLATED_STORE": "1",
            "UITEST_SCENARIO": "signed-in-demo-parent",
            "UITEST_DISABLE_AUDIO": "1"
        ])
        #expect(isolated.usesIsolatedStore)
        #expect(isolated.scenario == .signedInDemoParent)
        #expect(isolated.disablesAudio)
    }

    @MainActor
    @Test func signedInScenarioFixturesEstablishScopedFamilySessions() throws {
        let demoContainer = try makeFixtureContainer()
        try SeedData.seedIfNeeded(in: demoContainer.mainContext)
        let demoManager = AppleIDManager()
        try UITestScenarioFixtures.establish(
            .signedInDemoParent,
            manager: demoManager,
            context: demoContainer.mainContext
        )
        #expect(demoManager.isSignedIn)
        #expect(demoManager.currentAppleID == UITestScenarioFixtures.demoParentAppleID)
        #expect(demoManager.currentFamily?.id == SeedData.demoFamilyID)
        #expect(demoManager.currentMembership?.familyID == SeedData.demoFamilyID)
        #expect(demoManager.currentFamilyMember?.name == "Parent Example One")

        let adminContainer = try makeFixtureContainer()
        try SeedData.seedIfNeeded(in: adminContainer.mainContext)
        let adminManager = AppleIDManager()
        try UITestScenarioFixtures.establish(
            .signedInEmptyAdministrator,
            manager: adminManager,
            context: adminContainer.mainContext
        )
        #expect(adminManager.isSignedIn)
        #expect(adminManager.currentAppleID == UITestScenarioFixtures.administratorAppleID)
        #expect(adminManager.currentFamily?.name == "UI Test Family")
        #expect(adminManager.currentFamilyMember?.name == "UI Test Admin")
        #expect(adminManager.currentMembership?.familyID == adminManager.currentFamily?.id)
        #expect(adminManager.currentFamily?.id != SeedData.demoFamilyID)
    }

    @MainActor
    private func makeFixtureContainer() throws -> ModelContainer {
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
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )]
        )
    }

    @MainActor
    @Test func soundscapeRestoresThePreviousRoomAfterAnOverlayCloses() {
        let preferenceKey = "soundscapeEnabled"
        let previousPreference = UserDefaults.standard.object(forKey: preferenceKey)
        defer {
            if let previousPreference {
                UserDefaults.standard.set(previousPreference, forKey: preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            }
        }

        let director = SoundscapeDirector()
        director.isEnabled = false
        let familyOwner = UUID()
        let editorOwner = UUID()

        director.enter(.family, owner: familyOwner)
        #expect(director.scene == .family)

        director.enter(.rewardEntry, owner: editorOwner)
        #expect(director.scene == .rewardEntry)

        director.leave(owner: editorOwner)
        #expect(director.scene == .family)

        director.leave(owner: familyOwner)
        #expect(director.scene == .none)
    }

    @MainActor
    @Test func oneViewOwnerCannotLeaveDuplicateSoundtrackClaims() {
        let preferenceKey = "soundscapeEnabled"
        let previousPreference = UserDefaults.standard.object(forKey: preferenceKey)
        defer {
            if let previousPreference {
                UserDefaults.standard.set(previousPreference, forKey: preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: preferenceKey)
            }
        }

        let director = SoundscapeDirector()
        director.isEnabled = false
        let owner = UUID()

        director.enter(.rules, owner: owner)
        director.enter(.ledger, owner: owner)
        #expect(director.scene == .ledger)

        director.leave(owner: owner)
        #expect(director.scene == .none)
    }

    @MainActor
    @Test func runtimeAudioDisableSkipsPlaybackWithoutChangingAudioControllerCoverage() {
        let probe = AudioSessionActivationProbe()
        let controller = AudioSessionController { completion in
            probe.recordActivation()
            completion(true)
        }
        let director = SoundscapeDirector(audioSession: controller, disableAudio: true)

        director.activate(.family)
        director.play(.pointsGained)

        #expect(!director.isEnabled)
        #expect(director.scene == .family)
        #expect(probe.snapshot.count == 0)
    }

    @Test func audioSessionActivationIsOffMainThreadSerializedAndIdempotent() async {
        let probe = AudioSessionActivationProbe()
        let controller = AudioSessionController { completion in
            probe.recordActivation()
            completion(true)
        }

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<8 {
                group.addTask { await controller.activateIfNeeded() }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let snapshot = probe.snapshot
        #expect(results.allSatisfy { $0 })
        #expect(snapshot.count == 1)
        #expect(!snapshot.onMainThread)
    }

    @MainActor
    @Test func everyMusicalRoomHasABundledPublicDomainPerformance() {
        let expectedResources: [SoundscapeDirector.Scene: String] = [
            .storefront: "storefront-theme",
            .rules: "rules-theme",
            .ledger: "ledger-theme",
            .statistics: "statistics-theme",
            .family: "family-theme",
            .rewardEntry: "rules-theme",
            .penaltyEntry: "rules-theme"
        ]
        let bundle = Bundle(for: SoundscapeDirector.self)

        for (scene, resourceName) in expectedResources {
            #expect(scene.soundtrackResourceName == resourceName)
            let url = bundle.url(forResource: resourceName, withExtension: "m4a", subdirectory: "Audio")
                ?? bundle.url(forResource: resourceName, withExtension: "m4a")
            #expect(url != nil, "Missing soundtrack resource: \(resourceName).m4a")
        }
        #expect(SoundscapeDirector.Scene.none.soundtrackResourceName == nil)
    }

}