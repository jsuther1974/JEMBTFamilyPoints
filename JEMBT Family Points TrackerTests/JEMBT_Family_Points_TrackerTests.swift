//
//  JEMBT_Family_Points_TrackerTests.swift
//  JEMBT Family Points TrackerTests
//
//  Created by Jeffrey Sutherland on 9/8/26.
//

import Foundation
import Testing
@testable import JEMBT_Family_Points_Tracker

struct JEMBT_Family_Points_TrackerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
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

}
