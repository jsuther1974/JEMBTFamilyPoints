import SwiftUI

struct ContentView: View {
    @Environment(WatchDashboardModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.snapshot {
                    dashboard(snapshot)
                } else {
                    ContentUnavailableView {
                        Label("Ready to Pair", systemImage: "iphone.and.arrow.forward")
                    } description: {
                        Text(model.connectionMessage)
                    } actions: {
                        Button("Try Again") { model.requestRefresh() }
                            .accessibilityIdentifier("watchRefresh")
                    }
                    .accessibilityIdentifier("watchEmptyState")
                }
            }
            .navigationTitle("Family Points")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.requestRefresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh from iPhone")
                }
            }
        }
    }

    private func dashboard(_ snapshot: WatchFamilySnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.familyName)
                        .font(.headline)
                    Text("Hi, \(snapshot.viewerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("watchFamilyHeader")

                if snapshot.members.isEmpty {
                    Text("No active children yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.members) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .font(.headline)
                                Text("Current balance")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(member.points.formatted())
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(member.points < 0 ? .orange : .green)
                        }
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(member.name), \(member.points) points")
                        .accessibilityIdentifier("watchMember-\(member.id)")
                    }
                }

                if snapshot.viewerRole != "child", snapshot.pendingCount > 0 {
                    Label(
                        "\(snapshot.pendingCount) waiting for review",
                        systemImage: "checkmark.circle.badge.questionmark"
                    )
                    .font(.callout.bold())
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("watchPendingCount")
                }

                if !snapshot.recent.isEmpty {
                    Text("Recent activity")
                        .font(.headline)
                        .padding(.top, 2)

                    ForEach(snapshot.recent) { activity in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: activity.points < 0 ? "arrow.down.circle.fill" : "sparkles")
                                .foregroundStyle(activity.points < 0 ? .orange : .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.title)
                                    .font(.caption.bold())
                                    .lineLimit(2)
                                Text(activity.memberName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 2)
                            Text(activity.points, format: .number.sign(strategy: .always()))
                                .font(.caption.bold().monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Text("Updated \(snapshot.generatedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .accessibilityIdentifier("watchLastUpdated")
            }
        }
        .accessibilityIdentifier("watchDashboard")
    }
}

#Preview("Synced") {
    ContentView()
        .environment(WatchDashboardModel.preview(.sample))
}

#Preview("Needs iPhone") {
    ContentView()
        .environment(WatchDashboardModel.preview(nil))
}

extension WatchDashboardModel {
    static func preview(_ snapshot: WatchFamilySnapshot?) -> WatchDashboardModel {
        let model = WatchDashboardModel()
        model.snapshot = snapshot
        return model
    }
}
