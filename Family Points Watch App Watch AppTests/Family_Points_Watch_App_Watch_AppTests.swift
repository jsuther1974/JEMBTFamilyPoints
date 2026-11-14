import Foundation
import Testing
@testable import Family_Points_Watch_App_Watch_App

struct Family_Points_Watch_App_Watch_AppTests {
    @Test func snapshotRoundTripsThroughCacheEncoding() throws {
        let source = WatchFamilySnapshot.sample
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(WatchFamilySnapshot.self, from: data)

        #expect(decoded == source)
        #expect(decoded.members.count == 2)
        #expect(decoded.recent.count == 2)
    }

    @Test func sampleSnapshotHasUsefulGlanceInformation() {
        let sample = WatchFamilySnapshot.sample

        #expect(!sample.familyName.isEmpty)
        #expect(!sample.viewerName.isEmpty)
        #expect(sample.members.allSatisfy { !$0.name.isEmpty })
        #expect(sample.pendingCount >= 0)
    }
}
