import XCTest

final class JEMBT_Family_Points_TrackerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCurrentMemberRowDoesNotShowInviteActions() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()
        app.openFamilyTab()
        app.assertCurrentMemberCannotInvite()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

private extension XCUIApplication {
    @MainActor
    func signInAndJoinDemoFamilyIfNeeded() {
        let simulatorButton = buttons["Use Simulator Test Account"]
        if simulatorButton.waitForExistence(timeout: 5) {
            simulatorButton.tap()
        }

        let joinButton = buttons["Join a family with an invitation code"]
        if joinButton.waitForExistence(timeout: 2) {
            joinButton.tap()

            let invitationField = textFields["Invitation code"]
            XCTAssertTrue(invitationField.waitForExistence(timeout: 5))
            invitationField.tap()
            invitationField.typeText("DEMO-FAMILY")

            navigationBars.buttons["Join"].tap()
        }
    }

    @MainActor
    func openFamilyTab() {
        let familyTab = tabBars.buttons["Family"]
        if familyTab.waitForExistence(timeout: 5) {
            familyTab.tap()
        }
    }

    @MainActor
    func assertCurrentMemberCannotInvite() {
        let meLabelPredicate = NSPredicate(format: "label CONTAINS '(me)'")
        let meLabelElement = staticTexts.matching(meLabelPredicate).firstMatch
        XCTAssertTrue(meLabelElement.waitForExistence(timeout: 8), "Expected a member row marked as '(me)'.")

        let meLabel = meLabelElement.label
        let meRow = cells.containing(.staticText, identifier: meLabel).firstMatch
        XCTAssertTrue(meRow.waitForExistence(timeout: 3), "Expected to find the row for the current member.")

        XCTAssertFalse(meRow.buttons["Generate invitation code"].exists)
        XCTAssertFalse(meRow.buttons["Share invitation"].exists)

        let name = meLabel.components(separatedBy: " (me)").first ?? ""
        if !name.isEmpty {
            XCTAssertFalse(buttons["Share invitation for \(name)"].exists)
        }
    }
}
