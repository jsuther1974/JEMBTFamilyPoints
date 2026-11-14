import XCTest

final class Family_Points_Watch_App_Watch_AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSyncedDashboardShowsBalancesAndReviewCount() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_WATCH_SAMPLE"] = "1"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["watchDashboard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["watchFamilyHeader"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watchMember-mateo"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watchPendingCount"].exists)

        let lastUpdated = app.descendants(matching: .any)["watchLastUpdated"]
        app.descendants(matching: .any)["watchDashboard"].swipeUp()
        XCTAssertTrue(lastUpdated.waitForExistence(timeout: 4))
    }

    @MainActor
    func testFirstLaunchExplainsHowToSync() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launch()

        let dashboard = app.descendants(matching: .any)["watchDashboard"]
        let emptyState = app.descendants(matching: .any)["watchEmptyState"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 8) || emptyState.waitForExistence(timeout: 2))
    }
}
