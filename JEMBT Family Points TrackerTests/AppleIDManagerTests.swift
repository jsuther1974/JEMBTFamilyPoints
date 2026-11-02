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

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AllowanceFamily.self,
            FamilyMember.self,
            FamilyInvitation.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
