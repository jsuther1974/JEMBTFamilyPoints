import Foundation
import Observation
import SwiftData
import SwiftUI
import WatchConnectivity

@MainActor
@Observable
final class WatchSyncBridge: NSObject, WCSessionDelegate {
    private var latestContext: [String: Any]?
    private var pendingContext: [String: Any]?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(
        familyName: String,
        viewerName: String,
        viewerRole: MemberRole,
        members: [FamilyMember],
        entries: [LedgerEntry]
    ) {
        let activeChildren = members
            .filter { $0.isActive && $0.role == .child }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let memberNames = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })
        let approved = entries.filter { $0.status == .approved }

        let memberPayload: [[String: Any]] = activeChildren.map { member in
            let balance = approved
                .filter { $0.memberID == member.id }
                .reduce(0) { $0 + $1.points }
            return ["id": member.id.uuidString, "name": member.name, "points": balance]
        }
        let recentPayload: [[String: Any]] = approved
            .filter { memberNames[$0.memberID] != nil }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(5)
            .map { entry in
                [
                    "id": entry.id.uuidString,
                    "memberName": memberNames[entry.memberID] ?? "Family member",
                    "title": entry.title,
                    "points": entry.points,
                    "occurredAt": entry.occurredAt
                ]
            }
        let context: [String: Any] = [
            "schemaVersion": 1,
            "familyName": familyName,
            "viewerName": viewerName,
            "viewerRole": viewerRole.rawValue,
            "pendingCount": entries.filter { $0.status == .pending }.count,
            "generatedAt": Date(),
            "members": memberPayload,
            "recent": recentPayload
        ]

        latestContext = context
        pendingContext = context
        sendIfReady()
    }

    private func sendIfReady() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let pendingContext else { return }
        do {
            try WCSession.default.updateApplicationContext(pendingContext)
            self.pendingContext = nil
        } catch {
            // Keep the latest snapshot queued for the next activation.
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.sendIfReady() }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            guard message["request"] as? String == "snapshot",
                  let latestContext = self.latestContext else {
                replyHandler([:])
                return
            }
            replyHandler(latestContext)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

struct WatchSnapshotSyncView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Query private var members: [FamilyMember]
    @Query private var entries: [LedgerEntry]
    @State private var bridge = WatchSyncBridge()

    private var familyMembers: [FamilyMember] {
        guard let familyID = appleIDManager.currentFamily?.id else { return [] }
        return members.filter { $0.familyID == familyID }
    }

    private var familyEntries: [LedgerEntry] {
        let memberIDs = Set(familyMembers.map(\.id))
        return entries.filter { memberIDs.contains($0.memberID) }
    }

    private var syncToken: String {
        let memberToken = familyMembers
            .map { "\($0.id.uuidString):\($0.name):\($0.roleRawValue):\($0.isActive)" }
            .sorted()
            .joined(separator: "|")
        let entryToken = familyEntries
            .map { "\($0.id.uuidString):\($0.points):\($0.statusRawValue):\($0.occurredAt.timeIntervalSinceReferenceDate)" }
            .sorted()
            .joined(separator: "|")
        return "\(appleIDManager.currentFamily?.name ?? "")#\(memberToken)#\(entryToken)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: syncToken) {
                guard let family = appleIDManager.currentFamily,
                      let viewer = appleIDManager.currentFamilyMember else { return }
                bridge.publish(
                    familyName: family.name,
                    viewerName: viewer.name,
                    viewerRole: viewer.role,
                    members: familyMembers,
                    entries: familyEntries
                )
            }
    }
}
