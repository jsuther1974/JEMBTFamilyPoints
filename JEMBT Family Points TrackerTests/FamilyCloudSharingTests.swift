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
        XCTAssertEqual(transport.acknowledgedPayloads.map(\.familyID), [fixture.family.id])
        XCTAssertEqual(transport.acknowledgedPayloads.map(\.changeTag), ["mock-tag"])
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

        FamilySharePublicationState.markDirty(familyID: family.id)
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

    func testFailedConflictAndMalformedFetchDoNotAcknowledgeChangeTag() async throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let destination = try makeContainer()
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [try FamilyShareStore.export(family: fixture.family, from: source.mainContext)]
        transport.nextChangeTag = "accepted-tag"
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        _ = try await coordinator.fetchSharedFamilies(invitationCode: "CODEA")
        XCTAssertEqual(transport.acknowledgedPayloads.map(\.changeTag), ["accepted-tag"])

        let localFamily = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).first)
        localFamily.name = "Local edit"
        try destination.mainContext.save()
        fixture.family.name = "Remote edit"
        try source.mainContext.save()
        transport.fetchedPayloads = [try FamilyShareStore.export(family: fixture.family, from: source.mainContext)]
        transport.nextChangeTag = "conflicting-tag"

        do {
            _ = try await coordinator.fetchSharedFamilies(invitationCode: "CODEA")
            XCTFail("Expected local and remote conflict")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .localAndRemoteChangesConflict)
        }
        XCTAssertEqual(transport.acknowledgedPayloads.map(\.changeTag), ["accepted-tag"])

        transport.fetchedPayloads = [Data("malformed".utf8)]
        transport.fetchedFamilyIDOverride = fixture.family.id
        transport.nextChangeTag = "malformed-tag"
        do {
            _ = try await coordinator.fetchSharedFamilies(invitationCode: "CODEA")
            XCTFail("Expected malformed payload rejection")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .invalidPayload)
        }
        XCTAssertEqual(transport.acknowledgedPayloads.map(\.changeTag), ["accepted-tag"])
    }

    func testIneligiblePayloadDoesNotAcknowledgeFetchedChangeTag() async throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "A")
        let destination = try makeContainer()
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [try FamilyShareStore.export(family: fixture.family, from: source.mainContext)]
        transport.nextChangeTag = "ineligible-tag"
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        let imported = try await coordinator.fetchSharedFamilies(invitationCode: "WRONG")
        XCTAssertEqual(imported, [])
        XCTAssertTrue(transport.acknowledgedPayloads.isEmpty)
    }

    func testFetchedRecordFamilyMismatchIsRejectedAndNotAcknowledged() async throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "Mismatch")
        let destination = try makeContainer()
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [try FamilyShareStore.export(
            family: fixture.family,
            from: source.mainContext
        )]
        transport.fetchedFamilyIDOverride = UUID()
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)

        do {
            _ = try await coordinator.fetchSharedFamilies(invitationCode: "CODEMismatch")
            XCTFail("Expected fetched-record identity mismatch")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .fetchedRecordMismatch)
        }
        XCTAssertTrue(transport.acknowledgedPayloads.isEmpty)
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).isEmpty)
    }

    func testPayloadRejectsUnlinkedMembershipAndSettlementForParentBeforeMutation() throws {
        let source = try makeContainer()
        let fixture = try makeFamilyFixture(in: source.mainContext, suffix: "Graph")
        let validData = try FamilyShareStore.export(family: fixture.family, from: source.mainContext)
        let destination = try makeContainer()

        let unlinkedMembership = try mutateJSON(validData) { object in
            var membership = try XCTUnwrap((object["memberships"] as? [[String: Any]])?.first)
            membership["familyMemberID"] = NSNull()
            object["memberships"] = [membership]
        }
        XCTAssertThrowsError(try FamilyShareStore.importPayload(unlinkedMembership, into: destination.mainContext)) {
            XCTAssertEqual($0 as? FamilySharingError, .invalidRoleProfile)
        }

        let settlementForParent = try mutateJSON(validData) { object in
            let payload = try FamilyShareStore.decodeAndValidate(validData)
            var settlement = try XCTUnwrap((object["settlements"] as? [[String: Any]])?.first)
            settlement["childID"] = payload.members.first(where: { $0.roleRawValue == MemberRole.parent.rawValue })?.id.uuidString
            object["settlements"] = [settlement]
        }
        XCTAssertThrowsError(try FamilyShareStore.importPayload(settlementForParent, into: destination.mainContext)) {
            XCTAssertEqual($0 as? FamilySharingError, .invalidFamilyBoundary)
        }
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).isEmpty)
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

    func testLegacyBooleanDirtyMarkersMigrateToMonotonicGeneralPublicationIntents() throws {
        let defaults = UserDefaults.standard
        let freshFamilyID = UUID()
        let existingGenerationFamilyID = UUID()
        let prefixes = [
            "FamilySharePublicationDirty.",
            "FamilySharePublicationIntent.",
            "FamilySharePublicationGeneration."
        ]
        defer {
            for familyID in [freshFamilyID, existingGenerationFamilyID] {
                prefixes.forEach { defaults.removeObject(forKey: $0 + familyID.uuidString) }
            }
        }

        defaults.set(true, forKey: prefixes[0] + freshFamilyID.uuidString)
        let freshIntent = try XCTUnwrap(FamilySharePublicationState.dirtyIntent(familyID: freshFamilyID))
        XCTAssertEqual(freshIntent.generation, 1)
        XCTAssertEqual(freshIntent.authorization, .general)
        XCTAssertEqual(defaults.integer(forKey: prefixes[2] + freshFamilyID.uuidString), 1)
        XCTAssertNotNil(defaults.data(forKey: prefixes[1] + freshFamilyID.uuidString))
        XCTAssertEqual(FamilySharePublicationState.markDirty(familyID: freshFamilyID), 2)

        defaults.set(true, forKey: prefixes[0] + existingGenerationFamilyID.uuidString)
        defaults.set(7, forKey: prefixes[2] + existingGenerationFamilyID.uuidString)
        let existingIntent = try XCTUnwrap(
            FamilySharePublicationState.dirtyIntent(familyID: existingGenerationFamilyID)
        )
        XCTAssertEqual(existingIntent.generation, 7)
        XCTAssertEqual(existingIntent.authorization, .general)
        XCTAssertEqual(FamilySharePublicationState.markDirty(familyID: existingGenerationFamilyID), 8)
    }

    func testDirtyPublicationStateIsRetainedOnFailureAndClearedOnlyAfterSuccess() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "Dirty")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let session = MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        )
        let transport = MockFamilyShareTransport()
        transport.publishError = FamilySharingError.conflictingChange
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        do {
            try await coordinator.publishAfterLocalMutation(session: session)
            XCTFail("Expected publication failure")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .conflictingChange)
        }
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))

        transport.publishError = nil
        try await coordinator.retryPendingPublication(session: session)
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
        XCTAssertEqual(transport.publishCount, 2)
    }

    func testDirtyPublicationStateIsRetainedOnCancellation() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "Cancel")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let transport = MockFamilyShareTransport()
        transport.publishError = CancellationError()
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        do {
            try await coordinator.publishAfterLocalMutation(session: MutationSession(
                appleID: membership.appleID,
                family: fixture.family,
                membership: membership,
                member: fixture.member
            ))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
    }

    func testReconstructedCoordinatorRetriesDurablePendingPublicationAfterSessionEstablishment() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "Restart")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let session = MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        )
        FamilySharePublicationState.markDirty(familyID: fixture.family.id)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        let reconstructedTransport = MockFamilyShareTransport()
        let reconstructedCoordinator = FamilySharingCoordinator(transport: reconstructedTransport)
        reconstructedCoordinator.configure(modelContainer: container)
        try await reconstructedCoordinator.retryPendingPublication(session: session)

        XCTAssertEqual(reconstructedTransport.publishCount, 1)
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
    }

    func testPublicationIntentIsDurableBeforeSaveAndRollsBackAfterSaveFailure() throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "Rollback")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let session = MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        )
        let coordinator = FamilySharingCoordinator(transport: MockFamilyShareTransport())
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        enum ExpectedFailure: Error { case save }
        XCTAssertThrowsError(try coordinator.performProtectedMutation(session: session) {
            XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
            throw ExpectedFailure.save
        })
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: fixture.family.id))

        FamilySharePublicationState.markDirty(familyID: fixture.family.id)
        XCTAssertThrowsError(try coordinator.performProtectedMutation(session: session) {
            throw ExpectedFailure.save
        })
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
    }

    func testCommittedPublicationIntentRetriesSuccessfulSavedMutation() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "IntentRetry")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let session = MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        )
        let transport = MockFamilyShareTransport()
        transport.publishError = FamilySharingError.familyNotPublished
        let coordinator = FamilySharingCoordinator(transport: transport, publicationDelay: .milliseconds(1))
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        try coordinator.performProtectedMutation(session: session) {
            fixture.family.name = "Durably saved"
            try container.mainContext.save()
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))

        transport.publishError = nil
        try await coordinator.retryPendingPublication(session: session)
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
        let payload = try FamilyShareStore.decodeAndValidate(try XCTUnwrap(transport.lastPublishedPayload))
        XCTAssertEqual(payload.family.name, "Durably saved")
    }

    func testRevokedInvitationIsIncludedInCommittedPublication() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "RevokePublish")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let invitation = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyInvitation>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let session = MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        )
        let transport = MockFamilyShareTransport()
        let coordinator = FamilySharingCoordinator(transport: transport, publicationDelay: .milliseconds(1))
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        try coordinator.performProtectedMutation(session: session) {
            invitation.status = .revoked
            try container.mainContext.save()
        }
        try await Task.sleep(for: .milliseconds(50))

        let payload = try FamilyShareStore.decodeAndValidate(try XCTUnwrap(transport.lastPublishedPayload))
        XCTAssertEqual(payload.invitations.first { $0.id == invitation.id }?.statusRawValue, InvitationStatus.revoked.rawValue)
    }

    func testViewerInvitationRedemptionPublishesConsumedInvitationAndMembership() async throws {
        let setup = try makeViewerRedemptionSetup(suffix: "ViewerSuccess")
        defer { FamilySharePublicationState.clearDirty(familyID: setup.fixture.family.id) }

        let intent = try setup.coordinator.prepareInvitationRedemptionPublication(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        let accepted = try setup.manager.acceptInvitation(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        let session = MutationSession(
            appleID: setup.appleID,
            family: accepted.family,
            membership: accepted.membership,
            member: accepted.member
        )
        setup.coordinator.commitProtectedMutationPublication(intent, session: session)
        try await waitUntil { setup.transport.publishCount == 1 }

        let payload = try FamilyShareStore.decodeAndValidate(try XCTUnwrap(setup.transport.lastPublishedPayload))
        XCTAssertEqual(payload.invitations.first { $0.id == setup.invitation.id }?.statusRawValue, InvitationStatus.accepted.rawValue)
        XCTAssertTrue(payload.memberships.contains {
            $0.id == accepted.membership.id && $0.appleID == setup.appleID &&
                $0.roleRawValue == FamilyMembershipRole.viewer.rawValue
        })
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: setup.fixture.family.id))
    }

    func testFailedViewerInvitationRedemptionRemainsDurablyRetryable() async throws {
        let setup = try makeViewerRedemptionSetup(suffix: "ViewerRetry")
        defer { FamilySharePublicationState.clearDirty(familyID: setup.fixture.family.id) }
        setup.transport.publishError = FamilySharingError.conflictingChange
        let intent = try setup.coordinator.prepareInvitationRedemptionPublication(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        let accepted = try setup.manager.acceptInvitation(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        let session = MutationSession(
            appleID: setup.appleID, family: accepted.family,
            membership: accepted.membership, member: accepted.member
        )
        setup.coordinator.commitProtectedMutationPublication(intent, session: session)
        try await waitUntil { setup.transport.publishCount == 1 }
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: setup.fixture.family.id))

        setup.transport.publishError = nil
        let reconstructed = FamilySharingCoordinator(transport: setup.transport, publicationDelay: .milliseconds(1))
        reconstructed.configure(modelContainer: setup.container)
        try await reconstructed.retryPendingPublication(session: session)

        XCTAssertEqual(setup.transport.publishCount, 2)
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: setup.fixture.family.id))
    }

    func testViewerInvitationCodeCannotBeReusedAfterRedemption() throws {
        let setup = try makeViewerRedemptionSetup(suffix: "ViewerReuse")
        defer { FamilySharePublicationState.clearDirty(familyID: setup.fixture.family.id) }
        _ = try setup.coordinator.prepareInvitationRedemptionPublication(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        _ = try setup.manager.acceptInvitation(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )

        XCTAssertThrowsError(try setup.coordinator.prepareInvitationRedemptionPublication(
            code: setup.invitation.code,
            appleID: "second-viewer",
            modelContext: setup.container.mainContext
        )) { XCTAssertEqual($0 as? InvitationError, .invalidOrExpired) }
        XCTAssertThrowsError(try setup.manager.acceptInvitation(
            code: setup.invitation.code,
            appleID: "second-viewer",
            modelContext: setup.container.mainContext
        )) { XCTAssertEqual($0 as? InvitationError, .invalidOrExpired) }
    }

    func testViewerRedemptionPublicationRejectsMismatchedSessionButValidRetrySucceeds() async throws {
        let setup = try makeViewerRedemptionSetup(suffix: "ViewerMismatch")
        defer { FamilySharePublicationState.clearDirty(familyID: setup.fixture.family.id) }
        let intent = try setup.coordinator.prepareInvitationRedemptionPublication(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        let accepted = try setup.manager.acceptInvitation(
            code: setup.invitation.code,
            appleID: setup.appleID,
            modelContext: setup.container.mainContext
        )
        let validSession = MutationSession(
            appleID: setup.appleID, family: accepted.family,
            membership: accepted.membership, member: accepted.member
        )
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign")
        setup.coordinator.commitProtectedMutationPublication(intent, session: MutationSession(
            appleID: setup.appleID, family: foreignFamily,
            membership: accepted.membership, member: accepted.member
        ))

        XCTAssertEqual(setup.transport.publishCount, 0)
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: accepted.family.id))
        do {
            try await setup.coordinator.retryPendingPublication(session: MutationSession(
                appleID: "wrong", family: accepted.family,
                membership: accepted.membership, member: accepted.member
            ))
            XCTFail("Expected mismatched redemption session rejection")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .notAuthorized)
        }
        try await setup.coordinator.retryPendingPublication(session: validSession)
        XCTAssertEqual(setup.transport.publishCount, 1)
    }

    func testOlderInFlightPublishCannotClearNewerGenerationWhenCancellationIsIgnored() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "GenerationRace")
        let membership = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
            $0.familyID == fixture.family.id
        })
        let session = MutationSession(
            appleID: membership.appleID, family: fixture.family,
            membership: membership, member: fixture.member
        )
        let transport = BlockingFamilyShareTransport()
        let coordinator = FamilySharingCoordinator(transport: transport, publicationDelay: .milliseconds(1))
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        try coordinator.performProtectedMutation(session: session) {
            fixture.family.name = "Snapshot A"
            try container.mainContext.save()
        }
        try await waitUntil { transport.publishCount == 1 }

        try coordinator.performProtectedMutation(session: session) {
            fixture.family.name = "Snapshot B"
            try container.mainContext.save()
        }
        transport.releasePublish(at: 0)
        try await waitUntil { transport.publishCount == 2 }
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))

        transport.releasePublish(at: 1)
        try await waitUntil { !FamilySharePublicationState.isDirty(familyID: fixture.family.id) }
        let payloads = try transport.publishedPayloads.map(FamilyShareStore.decodeAndValidate)
        XCTAssertEqual(payloads.map(\.family.name), ["Snapshot A", "Snapshot B"])
    }

    func testProtectedMutationPublicationCoalescesAndPublishesLatestSavedSnapshot() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "Scheduled")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let session = MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        )
        let transport = MockFamilyShareTransport()
        let coordinator = FamilySharingCoordinator(
            transport: transport,
            publicationDelay: .milliseconds(1)
        )
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        fixture.family.name = "First saved name"
        try container.mainContext.save()
        coordinator.publishAfterProtectedMutation(session: session)
        fixture.family.name = "Latest saved name"
        try container.mainContext.save()
        coordinator.publishAfterProtectedMutation(session: session)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(transport.publishCount, 1)
        let data = try XCTUnwrap(transport.lastPublishedPayload)
        let payload = try FamilyShareStore.decodeAndValidate(data)
        XCTAssertEqual(payload.family.name, "Latest saved name")
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
    }

    func testProtectedMutationKeepsLocalOnlyFamilyDirtyWithoutSurfacingError() async throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "LocalOnly")
        let membership = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
                $0.familyID == fixture.family.id
            }
        )
        let transport = MockFamilyShareTransport()
        transport.publishError = FamilySharingError.familyNotPublished
        let coordinator = FamilySharingCoordinator(
            transport: transport,
            publicationDelay: .milliseconds(1)
        )
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        fixture.family.name = "Saved locally"
        try container.mainContext.save()
        coordinator.publishAfterProtectedMutation(session: MutationSession(
            appleID: membership.appleID,
            family: fixture.family,
            membership: membership,
            member: fixture.member
        ))
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(fixture.family.name, "Saved locally")
        XCTAssertEqual(transport.publishCount, 1)
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
        XCTAssertNil(coordinator.lastError)
    }

    func testProtectedMutationSchedulingIsAuthorizedBeforeDirtyMarker() throws {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: "Unauthorized")
        let coordinator = FamilySharingCoordinator(
            transport: MockFamilyShareTransport(),
            publicationDelay: .milliseconds(1)
        )
        coordinator.configure(modelContainer: container)
        defer { FamilySharePublicationState.clearDirty(familyID: fixture.family.id) }

        let unauthorized = FamilyMembership(
            familyID: fixture.family.id,
            familyMemberID: fixture.member.id,
            appleID: "viewer",
            role: .viewer
        )
        coordinator.publishAfterProtectedMutation(session: MutationSession(
            appleID: "viewer",
            family: fixture.family,
            membership: unauthorized,
            member: fixture.member
        ))

        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: fixture.family.id))
        XCTAssertEqual(coordinator.lastError, FamilySharingError.notAuthorized.localizedDescription)
    }

    func testAutomaticPublicationQueuesTwoFamiliesIndependently() async throws {
        let container = try makeContainer()
        let first = try makeFamilyFixture(in: container.mainContext, suffix: "QueueA")
        let second = try makeFamilyFixture(in: container.mainContext, suffix: "QueueB")
        let memberships = try container.mainContext.fetch(FetchDescriptor<FamilyMembership>())
        let transport = MockFamilyShareTransport()
        let coordinator = FamilySharingCoordinator(
            transport: transport,
            publicationDelay: .milliseconds(1)
        )
        coordinator.configure(modelContainer: container)
        defer {
            FamilySharePublicationState.clearDirty(familyID: first.family.id)
            FamilySharePublicationState.clearDirty(familyID: second.family.id)
        }

        for fixture in [first, second] {
            let membership = try XCTUnwrap(memberships.first { $0.familyID == fixture.family.id })
            coordinator.publishAfterProtectedMutation(session: MutationSession(
                appleID: membership.appleID,
                family: fixture.family,
                membership: membership,
                member: fixture.member
            ))
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(Set(transport.publishedFamilyIDs), [first.family.id, second.family.id])
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: first.family.id))
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: second.family.id))
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

    func testConflictKeepLocalPublishesLocalSnapshotAndClearsDirtyOnlyAfterSuccess() async throws {
        let setup = try await makeConflictSetup(suffix: "Keep")
        defer {
            FamilySharePublicationState.clearDirty(familyID: setup.family.id)
            FamilyShareBaseline.clear(familyID: setup.family.id)
        }
        FamilySharePublicationState.markDirty(familyID: setup.family.id)
        setup.transport.resolveConflictError = FamilySharingError.conflictingChange

        do {
            try await setup.coordinator.resolveConflictKeepingLocal(session: setup.session)
            XCTFail("Expected first conflict resolution attempt to fail")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .conflictingChange)
        }
        XCTAssertTrue(setup.coordinator.hasConflict(for: setup.family.id))
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: setup.family.id))

        setup.transport.resolveConflictError = nil
        try await setup.coordinator.resolveConflictKeepingLocal(session: setup.session)

        let published = try FamilyShareStore.decodeAndValidate(try XCTUnwrap(setup.transport.lastResolvedLocalPayload))
        XCTAssertEqual(published.family.name, "Local Keep")
        XCTAssertFalse(setup.coordinator.hasConflict(for: setup.family.id))
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: setup.family.id))
        XCTAssertEqual(setup.transport.resolveConflictCount, 2)
    }

    func testConflictUseCloudCopyReplacesOnlyEligibleFamilyAndClearsDirty() async throws {
        let setup = try await makeConflictSetup(suffix: "Cloud")
        let foreign = try makeFamilyFixture(in: setup.destination.mainContext, suffix: "ForeignCloud")
        defer {
            FamilySharePublicationState.clearDirty(familyID: setup.family.id)
            FamilyShareBaseline.clear(familyID: setup.family.id)
        }
        FamilySharePublicationState.markDirty(familyID: setup.family.id)

        try await setup.coordinator.resolveConflictUsingCloudCopy(session: setup.session)

        let families = try setup.destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>())
        XCTAssertEqual(families.first { $0.id == setup.family.id }?.name, "Remote Cloud")
        XCTAssertEqual(families.first { $0.id == foreign.family.id }?.name, foreign.family.name)
        XCTAssertTrue(try setup.destination.mainContext.fetch(FetchDescriptor<LedgerEntry>()).contains {
            $0.id == foreign.entry.id
        })
        XCTAssertFalse(try setup.destination.mainContext.fetch(FetchDescriptor<LedgerEntry>()).contains {
            $0.title == "Local-only Cloud"
        })
        XCTAssertFalse(setup.coordinator.hasConflict(for: setup.family.id))
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: setup.family.id))
        XCTAssertEqual(setup.transport.acknowledgedPayloads.last?.changeTag, "conflict-Cloud")
    }

    func testCloudCopyAcknowledgementFailureRetainsConflictAndDirtyStateForRetry() async throws {
        let setup = try await makeConflictSetup(suffix: "RetryCloud")
        defer {
            FamilySharePublicationState.clearDirty(familyID: setup.family.id)
            FamilyShareBaseline.clear(familyID: setup.family.id)
        }
        setup.transport.acknowledgeError = FamilySharingError.conflictingChange

        do {
            try await setup.coordinator.resolveConflictUsingCloudCopy(session: setup.session)
            XCTFail("Expected acknowledgement failure")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .conflictingChange)
        }
        XCTAssertTrue(setup.coordinator.hasConflict(for: setup.family.id))
        XCTAssertTrue(FamilySharePublicationState.isDirty(familyID: setup.family.id))

        setup.transport.acknowledgeError = nil
        try await setup.coordinator.resolveConflictUsingCloudCopy(session: setup.session)
        XCTAssertFalse(setup.coordinator.hasConflict(for: setup.family.id))
        XCTAssertFalse(FamilySharePublicationState.isDirty(familyID: setup.family.id))
    }

    func testConflictResolutionRejectsForeignSessionWithoutUsingPendingPayload() async throws {
        let setup = try await makeConflictSetup(suffix: "Unauthorized")
        defer { FamilyShareBaseline.clear(familyID: setup.family.id) }
        let foreignFamily = AllowanceFamily(name: "Foreign", createdByAppleID: "foreign")
        let foreignMember = FamilyMember(familyID: foreignFamily.id, name: "Foreign", role: .parent)
        let foreignMembership = FamilyMembership(
            familyID: foreignFamily.id, familyMemberID: foreignMember.id,
            appleID: "foreign", role: .familyAdmin
        )
        let foreignSession = MutationSession(
            appleID: "foreign", family: foreignFamily,
            membership: foreignMembership, member: foreignMember
        )

        for useCloudCopy in [false, true] {
            do {
                if useCloudCopy {
                    try await setup.coordinator.resolveConflictUsingCloudCopy(session: foreignSession)
                } else {
                    try await setup.coordinator.resolveConflictKeepingLocal(session: foreignSession)
                }
                XCTFail("Expected foreign-family conflict resolution rejection")
            } catch {
                XCTAssertTrue(
                    error as? FamilySharingError == .notAuthorized ||
                    error as? FamilySharingError == .missingPayload
                )
            }
        }
        XCTAssertTrue(setup.coordinator.hasConflict(for: setup.family.id))
        XCTAssertEqual(setup.transport.resolveConflictCount, 0)
    }

    private func makeConflictSetup(suffix: String) async throws -> (
        destination: ModelContainer,
        family: AllowanceFamily,
        session: MutationSession,
        coordinator: FamilySharingCoordinator,
        transport: MockFamilyShareTransport
    ) {
        let source = try makeContainer()
        let remote = try makeFamilyFixture(in: source.mainContext, suffix: suffix)
        let destination = try makeContainer()
        let transport = MockFamilyShareTransport()
        transport.fetchedPayloads = [try FamilyShareStore.export(family: remote.family, from: source.mainContext)]
        transport.nextChangeTag = "baseline-\(suffix)"
        let coordinator = FamilySharingCoordinator(transport: transport)
        coordinator.configure(modelContainer: destination)
        _ = try await coordinator.fetchSharedFamilies(invitationCode: "CODE\(suffix)")

        let family = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<AllowanceFamily>()).first)
        let member = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<FamilyMember>()).first {
            $0.familyID == family.id && $0.role == .parent
        })
        let membership = try XCTUnwrap(try destination.mainContext.fetch(FetchDescriptor<FamilyMembership>()).first {
            $0.familyID == family.id
        })
        family.name = "Local \(suffix.replacingOccurrences(of: "Retry", with: ""))"
        destination.mainContext.insert(LedgerEntry(
            memberID: member.id, weekEnding: .now, title: "Local-only \(suffix)", points: 1,
            kind: .reward, status: .approved, submittedBy: member.name
        ))
        try destination.mainContext.save()
        remote.family.name = "Remote \(suffix.replacingOccurrences(of: "Retry", with: ""))"
        try source.mainContext.save()
        transport.fetchedPayloads = [try FamilyShareStore.export(family: remote.family, from: source.mainContext)]
        transport.nextChangeTag = "conflict-\(suffix)"
        let session = MutationSession(
            appleID: membership.appleID, family: family, membership: membership, member: member
        )
        do {
            _ = try await coordinator.fetchSharedFamilies(session: session)
            XCTFail("Expected local and remote conflict")
        } catch {
            XCTAssertEqual(error as? FamilySharingError, .localAndRemoteChangesConflict)
        }
        return (destination, family, session, coordinator, transport)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: AllowanceFamily.self, FamilyInvitation.self, FamilyMembership.self, FamilyMember.self, RuleTemplate.self, RuleRider.self, LedgerEntry.self, WeeklySettlement.self, AppleIDMapping.self, configurations: configuration)
    }

    private func makeViewerRedemptionSetup(suffix: String) throws -> (
        container: ModelContainer,
        fixture: (family: AllowanceFamily, member: FamilyMember, entry: LedgerEntry),
        invitation: FamilyInvitation,
        appleID: String,
        manager: AppleIDManager,
        transport: MockFamilyShareTransport,
        coordinator: FamilySharingCoordinator
    ) {
        let container = try makeContainer()
        let fixture = try makeFamilyFixture(in: container.mainContext, suffix: suffix)
        let invitation = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<FamilyInvitation>()).first {
            $0.familyID == fixture.family.id
        })
        invitation.role = .viewer
        try container.mainContext.save()
        let transport = MockFamilyShareTransport()
        let coordinator = FamilySharingCoordinator(transport: transport, publicationDelay: .milliseconds(1))
        coordinator.configure(modelContainer: container)
        return (container, fixture, invitation, "viewer-\(suffix)", AppleIDManager(), transport, coordinator)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw FamilySharingTestError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
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

    private func mutateJSON(
        _ data: Data,
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try mutation(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private enum FamilySharingTestError: Error { case timedOut }

@MainActor
private final class BlockingFamilyShareTransport: FamilyShareTransport {
    private(set) var publishedPayloads: [Data] = []
    private var publishContinuations: [CheckedContinuation<Void, Never>] = []
    var publishCount: Int { publishedPayloads.count }

    func createShare(familyID: UUID, familyName: String, payload: Data) async throws -> FamilyShareHandle {
        let zone = CKRecordZone.ID(zoneName: "blocking-mock")
        let share = CKShare(rootRecord: CKRecord(
            recordType: "Mock",
            recordID: .init(recordName: familyID.uuidString, zoneID: zone)
        ))
        return FamilyShareHandle(
            share: share,
            container: CKContainer(identifier: CloudKitFamilyShareTransport.containerIdentifier)
        )
    }

    func publish(familyID: UUID, payload: Data) async throws {
        publishedPayloads.append(payload)
        await withCheckedContinuation { publishContinuations.append($0) }
    }

    func releasePublish(at index: Int) {
        publishContinuations[index].resume()
    }

    func resolveConflictKeepingLocal(_ fetched: FetchedFamilySharePayload, payload: Data) async throws {}
    func accept(_ metadata: CKShare.Metadata) async throws {}
    func fetchSharedPayloads() async throws -> [FetchedFamilySharePayload] { [] }
    func acknowledgeFetchedPayload(_ payload: FetchedFamilySharePayload) async throws {}
}

@MainActor
private final class MockFamilyShareTransport: FamilyShareTransport {
    var createdFamilyID: UUID?
    var fetchedPayloads: [Data] = []
    var fetchedFamilyIDOverride: UUID?
    var nextChangeTag: String? = "mock-tag"
    var acknowledgedPayloads: [FetchedFamilySharePayload] = []
    var fetchCount = 0
    var publishCount = 0
    var publishedFamilyIDs: [UUID] = []
    var lastPublishedPayload: Data?
    var publishError: Error?
    var resolveConflictError: Error?
    var acknowledgeError: Error?
    var resolveConflictCount = 0
    var lastResolvedLocalPayload: Data?

    func createShare(familyID: UUID, familyName: String, payload: Data) async throws -> FamilyShareHandle {
        createdFamilyID = familyID
        let zone = CKRecordZone.ID(zoneName: "mock")
        let share = CKShare(rootRecord: CKRecord(recordType: "Mock", recordID: .init(recordName: familyID.uuidString, zoneID: zone)))
        return FamilyShareHandle(share: share, container: CKContainer(identifier: CloudKitFamilyShareTransport.containerIdentifier))
    }
    func publish(familyID: UUID, payload: Data) async throws {
        publishCount += 1
        publishedFamilyIDs.append(familyID)
        lastPublishedPayload = payload
        if let publishError { throw publishError }
    }
    func resolveConflictKeepingLocal(_ fetched: FetchedFamilySharePayload, payload: Data) async throws {
        resolveConflictCount += 1
        lastResolvedLocalPayload = payload
        if let resolveConflictError { throw resolveConflictError }
    }
    func accept(_ metadata: CKShare.Metadata) async throws {}
    func fetchSharedPayloads() async throws -> [FetchedFamilySharePayload] {
        fetchCount += 1
        return try fetchedPayloads.map { data in
            let familyID = try fetchedFamilyIDOverride ?? FamilyShareStore.decodeAndValidate(data).familyID
            return FetchedFamilySharePayload(
                familyID: familyID,
                data: data,
                changeTag: nextChangeTag
            )
        }
    }
    func acknowledgeFetchedPayload(_ payload: FetchedFamilySharePayload) async throws {
        if let acknowledgeError { throw acknowledgeError }
        acknowledgedPayloads.append(payload)
    }
}

private extension JSONEncoder { static var familyShareTest: JSONEncoder { let e=JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e } }
private extension JSONDecoder { static var familyShareTest: JSONDecoder { let d=JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d } }