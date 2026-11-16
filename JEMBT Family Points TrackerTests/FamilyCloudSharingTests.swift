import CloudKit
import SwiftData
import XCTest
@testable import JEMBT_Family_Points_Tracker

@MainActor
final class FamilyCloudSharingTests: XCTestCase {
    func testRoundTripPreservesFamilyIsolationAndLedgerSettlementAudit() throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let foreign = try makeFamilyFixture(in: source.mainContext, suffix: "B")

        let data = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        let payload = try JSONDecoder.familyShareTest.decode(FamilySharePayload.self, from: data)
        XCTAssertEqual(payload.familyID, fixture.family.id)
        XCTAssertFalse(payload.members.contains { $0.familyID == foreign.family.id })
        XCTAssertEqual(payload.entries.map(\.id), [fixture.entry.id])
        XCTAssertEqual(payload.settlements.map(\.transactionFingerprint), ["immutable-fingerprint-A"])
        XCTAssertEqual(payload.entries.first?.submittedBy, "recorder-A")
        XCTAssertEqual(payload.entries.first?.reviewedBy, "reviewer-A")

        let destination = try makeContainer()
        XCTAssertEqual(try FamilyShareStore.importPayload(data, into: destination.mainContext), fixture.family.id)
        let importedEntries = try destination.mainContext.fetch(FetchDescriptor<LedgerEntry>())
        let importedSettlements = try destination.mainContext.fetch(FetchDescriptor<WeeklySettlement>())
        XCTAssertEqual(importedEntries.first?.reviewedAt, fixture.entry.reviewedAt)
        XCTAssertEqual(importedEntries.first?.quantity, 2)
        XCTAssertEqual(importedSettlements.first?.transactionFingerprint, "immutable-fingerprint-A")
        XCTAssertEqual(importedSettlements.first?.minimumMissReviewDetails, "Laundry: Absolved")
    }

    func testImportRejectsCrossFamilyRecordBeforeMutation() throws {
        let container = try makeContainer()
        let first = try makeFamilyFixture(in: container.mainContext, suffix: "A")
        let second = try makeFamilyFixture(in: container.mainContext, suffix: "B")
        let original = try JSONDecoder.familyShareTest.decode(
            FamilySharePayload.self,
            from: FamilyShareStore.export(family: first.family, from: container.mainContext)
        )
        let payload = FamilySharePayload(
            schemaVersion: original.schemaVersion,
            family: original.family,
            invitations: original.invitations,
            memberships: original.memberships,
            members: original.members + [MemberDTO(second.member)],
            rules: original.rules,
            riders: original.riders,
            entries: original.entries,
            settlements: original.settlements
        )
        let invalidData = try JSONEncoder.familyShareTest.encode(payload)
        let destination = try makeContainer()

        XCTAssertThrowsError(try FamilyShareStore.importPayload(invalidData, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? FamilySharingError, .invalidFamilyBoundary)
        }
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).isEmpty)
    }

    func testOnlyAdministratorCanCreateShareAndForeignSessionIsRejected() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "A")
        let transport = MockFamilyShareTransport()
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: container)

        for role in [FamilyMembershipRole.parent, .caregiver, .child, .viewer] {
            let membership = FamilyMembership(
                familyID: fixture.family.id,
                familyMemberID: fixture.member.id,
                appleID: role.rawValue,
                role: role
            )
            do {
                _ = try await coordinator.prepareShare(
                    session: MutationSession(appleID: role.rawValue, family: fixture.family, membership: membership, member: fixture.member)
                )
                XCTFail("Expected \(role.rawValue) share-creation authorization failure")
            } catch {
                XCTAssertEqual(error as? FamilySharingError, .notAuthorized)
            }
        }

        for role in [FamilyMembershipRole.familyAdmin, .owner] {
            let membership = FamilyMembership(
                familyID: fixture.family.id,
                familyMemberID: fixture.member.id,
                appleID: role.rawValue,
                role: role
            )
            _ = try await coordinator.prepareShare(
                session: MutationSession(appleID: role.rawValue, family: fixture.family, membership: membership, member: fixture.member)
            )
        }
        XCTAssertEqual(transport.createdFamilyID, fixture.family.id)

        let viewer = FamilyMembership(familyID: fixture.family.id, familyMemberID: fixture.member.id, appleID: "viewer", role: .viewer)
        do {
            try await coordinator.publish(session: MutationSession(appleID: "viewer", family: fixture.family, membership: viewer, member: fixture.member))
            XCTFail("Expected viewer publication authorization failure")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .notAuthorized)
        }

        let admin = FamilyMembership(familyID: fixture.family.id, familyMemberID: fixture.member.id, appleID: "admin", role: .familyAdmin)
        _ = try await coordinator.prepareShare(session: MutationSession(appleID: "admin", family: fixture.family, membership: admin, member: fixture.member))
        XCTAssertEqual(transport.createdFamilyID, fixture.family.id)

        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "other")
        do {
            try await coordinator.publish(session: MutationSession(appleID: "admin", family: foreignFamily, membership: admin, member: fixture.member))
            XCTFail("Expected family isolation failure")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .notAuthorized)
        }
    }

    func testParticipantFetchImportsPayloadAndTransportConflictIsSurfaced() async throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let data = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        let destination = try makeContainer()
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [data]
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        let fetchedFamilyIDs = try await coordinator.fetchSharedFamilies(invitationCode: "CODEA")
        XCTAssertEqual(fetchedFamilyIDs, [fixture.family.id])
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<LedgerEntry>()).count, 1)

        let importedFamily = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).first)
        let importedMember = try XCTUnwrap(
            try destination.mainContext.fetch(FetchDescriptor<FamilyMember>()).first { $0.role == .parent }
        )
        let membership = FamilyMembership(familyID: importedFamily.id, familyMemberID: importedMember.id, appleID: "parent", role: .parent)
        transport.publishError = FamilySharingError.conflictingChange
        do {
            try await coordinator.publish(session: MutationSession(appleID: "parent", family: importedFamily, membership: membership, member: importedMember))
            XCTFail("Expected conflict")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .conflictingChange)
            XCTAssertEqual(coordinator.lastError, FamilySharingError.conflictingChange.localizedDescription)
        }
    }

    func testFetchRequiresExplicitEligibilityAndImportsOnlyMatchingInvitation() async throws {
        let source = try makeContainer()
        let first = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let second = try makeFamilyFixture(in: source.mainContext, suffix: "B")
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [
            try FamilyShareStore.export(family: first.family, from: source.mainContext),
            try FamilyShareStore.export(family: second.family, from: source.mainContext)
        ]
        let destination = try makeContainer()
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        do {
            _ = try await coordinator.fetchSharedFamilies()
            XCTFail("Expected an eligibility requirement")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .notAuthorized)
        }
        XCTAssertEqual(transport.fetchCount, 0)

        let imported = try await coordinator.fetchSharedFamilies(invitationCode: " codeb ")
        XCTAssertEqual(imported, [second.family.id])
        XCTAssertEqual(transport.fetchCount, 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).map(\.id), [second.family.id])
    }

    func testExpiredInvitationDoesNotAuthorizeImport() async throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let invitation = try XCTUnwrap(try source.mainContext.fetch(FetchDescriptor<FamilyInvitation>()).first)
        invitation.createdAt = Date(timeIntervalSince1970: 1)
        invitation.expiresAt = Date(timeIntervalSince1970: 2)
        try source.mainContext.save()

        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [try FamilyShareStore.export(family: fixture.family, from: source.mainContext)]
        let destination = try makeContainer()
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        let imported = try await coordinator.fetchSharedFamilies(invitationCode: "CODEA")
        XCTAssertEqual(imported, [])
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).isEmpty)
    }

    func testSynchronizePreservesLocalChangesThenPublishesLatestSnapshot() async throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let remotePayload = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        let destination = try makeContainer()
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [remotePayload]
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        _ = try await coordinator.fetchSharedFamilies(invitationCode: "CODEA")
        let family = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).first)
        let member = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<FamilyMember>()).first { $0.role == .parent })
        let membership = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first { $0.appleID == "owner-A" })
        destination.mainContext.insert(LedgerEntry(
            memberID: member.id,
            weekEnding: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Local change",
            points: 1,
            kind: .reward,
            status: .approved,
            submittedBy: member.name
        ))
        try destination.mainContext.save()

        try await coordinator.synchronize(session: MutationSession(
            appleID: "owner-A",
            family: family,
            membership: membership,
            member: member
        ))

        XCTAssertEqual(transport.publishCount, 1)
        let publishedData = try XCTUnwrap(transport.lastPublishedPayload)
        let published = try JSONDecoder.familyShareTest.decode(FamilySharePayload.self, from: publishedData)
        XCTAssertTrue(published.entries.contains { $0.title == "Local change" })
    }

    func testReconciliationRemovesOnlyMissingRecordsFromImportedFamily() throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let destination = try makeContainer()
        let foreign = try makeFamilyFixture(in: destination.mainContext, suffix: "B")
        let firstPayload = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        _ = try FamilyShareStore.importPayload(firstPayload, into: destination.mainContext)

        source.mainContext.delete(fixture.entry)
        try source.mainContext.save()
        let updatedPayload = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        _ = try FamilyShareStore.importPayload(updatedPayload, into: destination.mainContext)

        let entries = try destination.mainContext.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertFalse(entries.contains { $0.id == fixture.entry.id })
        XCTAssertTrue(entries.contains { $0.id == foreign.entry.id })
    }

    func testForeignIdentifierCollisionRejectsBeforeAnyMutation() throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let payload = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        let destination = try makeContainer()
        let foreign = try makeFamilyFixture(in: destination.mainContext, suffix: "B")
        let collidingEntry = LedgerEntry(
            id: fixture.entry.id,
            memberID: foreign.member.id,
            weekEnding: .now,
            title: "Foreign",
            points: 1,
            kind: .reward,
            status: .approved,
            submittedBy: "foreign"
        )
        destination.mainContext.insert(collidingEntry)
        try destination.mainContext.save()

        XCTAssertThrowsError(try FamilyShareStore.importPayload(payload, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? FamilySharingError, .foreignIdentifierCollision)
        }
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).count, 1)
        XCTAssertEqual(collidingEntry.title, "Foreign")
    }

    func testDuplicateInvitationCodesAndMemberIdentitiesAreRejectedOnExport() throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "A")
        let child = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<FamilyMember>()).first { $0.familyID == fixture.family.id && $0.role == .child })
        container.mainContext.insert(FamilyInvitation(
            familyID: fixture.family.id,
            familyMemberID: child.id,
            code: "codea",
            role: .child
        ))
        try container.mainContext.save()

        XCTAssertThrowsError(try FamilyShareStore.export(family: fixture.family, from: container.mainContext)) { error in
            XCTAssertEqual(error as? FamilySharingError, .duplicateInvitationCode)
        }

        let invitations = try container.mainContext.fetch(FetchDescriptor<FamilyInvitation>())
        container.mainContext.delete(try XCTUnwrap(invitations.first { $0.code == "codea" }))
        container.mainContext.insert(FamilyMember(
            familyID: fixture.family.id,
            name: fixture.member.name.lowercased(),
            role: .parent
        ))
        try container.mainContext.save()
        XCTAssertThrowsError(try FamilyShareStore.export(family: fixture.family, from: container.mainContext)) { error in
            XCTAssertEqual(error as? FamilySharingError, .duplicateMemberIdentity)
        }
    }

    func testMalformedAndOversizedSnapshotsAreRejectedBeforeDecode() {
        XCTAssertThrowsError(try FamilyShareStore.decodeAndValidate(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? FamilySharingError, .invalidPayload)
        }
        let oversized = Data(count: FamilySharePayload.maximumEncodedBytes + 1)
        XCTAssertThrowsError(try FamilyShareStore.decodeAndValidate(oversized)) { error in
            XCTAssertEqual(error as? FamilySharingError, .payloadTooLarge)
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: AllowanceFamily.self, FamilyInvitation.self, FamilyMembership.self, FamilyMember.self, RuleTemplate.self, RuleRider.self, LedgerEntry.self, WeeklySettlement.self, AppleIDMapping.self, configurations: configuration)
    }

    private func makeFamilyFixture(in context: ModelContext, suffix: String) throws -> (family: AllowanceFamily, member: FamilyMember, entry: LedgerEntry) {
        let family = AllowanceFamily(name: "Family \(suffix)", createdByAppleID: "owner-\(suffix)")
        let member = FamilyMember(familyID: family.id, name: "Parent \(suffix)", role: .parent)
        let child = FamilyMember(familyID: family.id, name: "Child \(suffix)", birthDate: Date(timeIntervalSince1970: 100), role: .child)
        let rule = RuleTemplate(familyID: family.id, title: "Laundry \(suffix)", category: .household, kind: .reward, defaultPoints: 10)
        let reviewedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = LedgerEntry(memberID: child.id, ruleID: rule.id, occurredAt: reviewedAt, weekEnding: reviewedAt, title: rule.title, points: 20, kind: .reward, status: .approved, submittedBy: "recorder-\(suffix)", reviewedBy: "reviewer-\(suffix)", reviewedAt: reviewedAt, quantity: 2, measurementUnit: .basket)
        let settlement = WeeklySettlement(childID: child.id, weekEnding: reviewedAt, startingPoints: 1000, debtCarriedIn: -10, approvedEntryPoints: 20, parentPotShare: 3, minimumMissDeductionPoints: 0, minimumMissDeductionDetails: "", minimumMissReviewDetails: "Laundry: Absolved", finalPoints: 1013, cashAmount: 10.13, debtCarriedOut: 0, transactionFingerprint: "immutable-fingerprint-\(suffix)", confirmedAt: reviewedAt, confirmedBy: "reviewer-\(suffix)")
        context.insert(family)
        context.insert(member)
        context.insert(child)
        context.insert(rule)
        context.insert(entry)
        context.insert(settlement)
        context.insert(FamilyMembership(familyID: family.id, familyMemberID: member.id, appleID: "owner-\(suffix)", role: .familyAdmin))
        context.insert(FamilyInvitation(familyID: family.id, familyMemberID: child.id, code: "CODE\(suffix)", role: .child))
        context.insert(RuleRider(ruleID: rule.id, title: "Double", multiplier: 2))
        try context.save()
        return (family, member, entry)
    }
}

@MainActor
private final class MockFamilyShareTransport: FamilyShareTransport {
    var createdFamilyID: UUID?
    var fetchedPayloads: [Data] = []
    var fetchCount = 0
    var publishCount = 0
    var lastPublishedPayload: Data?
    var publishError: Error?

    func createShare(familyID: UUID, familyName: String, payload: Data) async throws -> FamilyShareHandle {
        createdFamilyID = familyID
        let zone = CKRecordZone.ID(zoneName: "mock")
        let share = CKShare(rootRecord: CKRecord(recordType: "Mock", recordID: .init(recordName: familyID.uuidString, zoneID: zone)))
        return FamilyShareHandle(share: share, container: CKContainer(identifier: CloudKitFamilyShareTransport.containerIdentifier))
    }
    func publish(familyID: UUID, payload: Data) async throws {
        publishCount += 1
        lastPublishedPayload = payload
        if let publishError { throw publishError }
    }
    func accept(_ metadata: CKShare.Metadata) async throws {}
    func fetchSharedPayloads() async throws -> [Data] {
        fetchCount += 1
        return fetchedPayloads
    }
}

private extension JSONEncoder { static var familyShareTest: JSONEncoder { let e=JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e } }
private extension JSONDecoder { static var familyShareTest: JSONDecoder { let d=JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d } }