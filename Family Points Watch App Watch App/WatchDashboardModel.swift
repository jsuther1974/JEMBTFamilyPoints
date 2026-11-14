import Foundation
import Observation
import WatchConnectivity

struct WatchMemberSummary: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let points: Int
}

struct WatchActivitySummary: Codable, Identifiable, Equatable {
    let id: String
    let memberName: String
    let title: String
    let points: Int
    let occurredAt: Date
}

struct WatchFamilySnapshot: Codable, Equatable {
    let familyName: String
    let viewerName: String
    let viewerRole: String
    let pendingCount: Int
    let generatedAt: Date
    let members: [WatchMemberSummary]
    let recent: [WatchActivitySummary]

    static let sample = WatchFamilySnapshot(
        familyName: "Sutherland Family",
        viewerName: "Jeffrey",
        viewerRole: "parent",
        pendingCount: 2,
        generatedAt: .now,
        members: [
            WatchMemberSummary(id: "mateo", name: "Mateo", points: 1_240),
            WatchMemberSummary(id: "sophia", name: "Sophia", points: 875)
        ],
        recent: [
            WatchActivitySummary(id: "1", memberName: "Mateo", title: "Help with laundry", points: 25, occurredAt: .now),
            WatchActivitySummary(id: "2", memberName: "Sophia", title: "Wash the dishes", points: 15, occurredAt: .now.addingTimeInterval(-3_600))
        ]
    )
}

@MainActor
@Observable
final class WatchDashboardModel: NSObject, WCSessionDelegate {
    private static let cacheKey = "familyPoints.watchSnapshot.v1"

    var snapshot: WatchFamilySnapshot?
    var connectionMessage = "Open Family Points on your iPhone to sync."

    override init() {
        super.init()
        if ProcessInfo.processInfo.environment["UITEST_WATCH_SAMPLE"] == "1" {
            snapshot = .sample
        } else if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            snapshot = try? JSONDecoder().decode(WatchFamilySnapshot.self, from: data)
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestRefresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            connectionMessage = "Connecting to iPhone…"
            session.activate()
            return
        }
        guard session.isReachable else {
            connectionMessage = "Your last update is available offline. Open the iPhone app to refresh."
            return
        }
        session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] context in
            Task { @MainActor in self?.receive(context) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.connectionMessage = "Couldn’t refresh. Your last update is still available."
            }
        })
    }

    private func receive(_ context: [String: Any]) {
        guard let familyName = context["familyName"] as? String,
              let viewerName = context["viewerName"] as? String,
              let viewerRole = context["viewerRole"] as? String,
              let pendingCount = context["pendingCount"] as? Int,
              let generatedAt = context["generatedAt"] as? Date else { return }

        let members = (context["members"] as? [[String: Any]] ?? []).compactMap { item -> WatchMemberSummary? in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let points = item["points"] as? Int else { return nil }
            return WatchMemberSummary(id: id, name: name, points: points)
        }
        let recent = (context["recent"] as? [[String: Any]] ?? []).compactMap { item -> WatchActivitySummary? in
            guard let id = item["id"] as? String,
                  let memberName = item["memberName"] as? String,
                  let title = item["title"] as? String,
                  let points = item["points"] as? Int,
                  let occurredAt = item["occurredAt"] as? Date else { return nil }
            return WatchActivitySummary(
                id: id,
                memberName: memberName,
                title: title,
                points: points,
                occurredAt: occurredAt
            )
        }
        let newSnapshot = WatchFamilySnapshot(
            familyName: familyName,
            viewerName: viewerName,
            viewerRole: viewerRole,
            pendingCount: pendingCount,
            generatedAt: generatedAt,
            members: members,
            recent: recent
        )
        snapshot = newSnapshot
        connectionMessage = "Updated just now"
        if let data = try? JSONEncoder().encode(newSnapshot) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let context = message["snapshot"] as? [String: Any] {
            Task { @MainActor in self.receive(context) }
        }
    }
}
