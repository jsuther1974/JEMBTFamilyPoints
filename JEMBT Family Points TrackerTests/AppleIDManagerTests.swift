import SwiftData
import XCTest
@testable import JEMBT_Family_Points_Tracker

final class AppleIDManagerTests: XCTestCase {
    func testAddingSameContactTwiceIsRejected() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()

        _ = try manager.addFamilyMember(
            family: family,
            name: "Daniel Higgins, Jr.",
            emailAddress: nil,
            birthDate: nil,
            sourceContactIdentifier: "contact-daniel",
            role: .parent,
            modelContext: context,
            shouldCreateInvitation: false
        )

        XCTAssertThrowsError(
            try manager.addFamilyMember(
                family: family,
                name: "Daniel Higgins Jr.",
                emailAddress: nil,
                birthDate: nil,
                sourceContactIdentifier: "contact-daniel",
                role: .parent,
                modelContext: context,
                shouldCreateInvitation: false
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Daniel Higgins, Jr. is already in this family.")
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 1)
    }

    func testDuplicateEmailIsCaseInsensitive() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()

        _ = try manager.addFamilyMember(
            family: family,
            name: "First Profile",
            emailAddress: "Daniel@example.com",
            birthDate: nil,
            role: .parent,
            modelContext: context,
            shouldCreateInvitation: false
        )

        XCTAssertThrowsError(
            try manager.addFamilyMember(
                family: family,
                name: "Second Profile",
                emailAddress: "daniel@EXAMPLE.COM",
                birthDate: nil,
                role: .parent,
                modelContext: context,
                shouldCreateInvitation: false
            )
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<FamilyMember>()).count, 1)
    }

    func testMemberAvatarCanBeAddedUpdatedAndRemoved() throws {
        let context = try makeContext()
        let family = AllowanceFamily(name: "Test Family", createdByAppleID: "test@local")
        context.insert(family)
        let manager = AppleIDManager()
        let originalAvatar = Data([0x01, 0x02, 0x03])

        let result = try manager.addFamilyMember(
            family: family,
            name: "Avatar Member",
            emailAddress: nil,
            birthDate: nil,
            avatarData: originalAvatar,
            role: .parent,
            modelContext: context,
            shouldCreateInvitation: false
        )
        XCTAssertEqual(result.member.avatarData, originalAvatar)

        let replacementAvatar = Data([0x04, 0x05])
        try manager.updateFamilyMember(
            result.member,
            name: result.member.name,
            emailAddress: nil,
            birthDate: nil,
            avatarData: replacementAvatar,
            role: .parent,
            modelContext: context
        )
        XCTAssertEqual(result.member.avatarData, replacementAvatar)

        try manager.updateFamilyMember(
            result.member,
            name: result.member.name,
            emailAddress: nil,
            birthDate: nil,
            avatarData: nil,
            role: .parent,
            modelContext: context
        )
        XCTAssertNil(result.member.avatarData)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: AllowanceFamily.self,
            FamilyMember.self,
            FamilyInvitation.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
