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
    func testAddMemberShowsInviteReadySheetImmediately() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-admin-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.addMemberNamedForInviteSheetVerification()
        app.assertInviteReadySheetIsVisible()
    }

    @MainActor
    func testFamilyNameEditButtonOpensEditor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-family-name-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()

        let editFamilyNameButton = app.buttons["Edit family name"]
        XCTAssertTrue(editFamilyNameButton.waitForExistence(timeout: 5), "Expected the family-name edit button to exist.")
        editFamilyNameButton.tap()

        XCTAssertTrue(
            app.navigationBars["Edit Family Name"].waitForExistence(timeout: 5),
            "Expected tapping the family-name edit button to open the editor."
        )
    }

    @MainActor
    func testReturnSubmitsCreateFamilyForm() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-create-return-\(UUID().uuidString)@local"
        app.launch()

        let simulatorButton = app.buttons["Use Simulator Test Account"]
        XCTAssertTrue(simulatorButton.waitForExistence(timeout: 5))
        simulatorButton.tap()

        let createFamilyButton = app.buttons["Create a new family"]
        XCTAssertTrue(createFamilyButton.waitForExistence(timeout: 5))
        createFamilyButton.tap()

        let familyNameField = app.textFields["Family name"]
        XCTAssertTrue(familyNameField.waitForExistence(timeout: 5))
        familyNameField.tap()
        familyNameField.typeText("Return Test Family")

        let administratorNameField = app.textFields["Your name"]
        XCTAssertTrue(administratorNameField.waitForExistence(timeout: 5))
        administratorNameField.tap()
        administratorNameField.typeText("Return Test Admin")
        administratorNameField.typeText("\r")

        XCTAssertTrue(
            app.buttons["Edit family name"].waitForExistence(timeout: 5),
            "Expected Return in the final field to create the family."
        )
    }

    @MainActor
    func testNewChildDoesNotShowFabricatedBirthdate() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-empty-birthday-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.buttons["Add family member"].tap()

        XCTAssertTrue(app.navigationBars["Add Family Member"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Enter birthdate"].exists, "Expected an explicit action for a child without a birthdate.")
        XCTAssertFalse(app.datePickers["Birthdate"].exists, "A missing birthdate must not display a fabricated date.")
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
    func signInAndCreateFamilyForAddingMembers() {
        let simulatorButton = buttons["Use Simulator Test Account"]
        if simulatorButton.waitForExistence(timeout: 5) {
            simulatorButton.tap()
        }

        let createFamilyButton = buttons["Create a new family"]
        XCTAssertTrue(createFamilyButton.waitForExistence(timeout: 5), "Expected create-family option for a new simulator Apple ID.")
        createFamilyButton.tap()

        XCTAssertTrue(navigationBars["Create a Family"].waitForExistence(timeout: 5))

        let familyNameField = textFields["Family name"]
        XCTAssertTrue(familyNameField.waitForExistence(timeout: 5), "Expected family name field.")
        familyNameField.tap()
        familyNameField.typeText("UI Test Family")

        let administratorNameField = textFields["Your name"]
        XCTAssertTrue(administratorNameField.waitForExistence(timeout: 5), "Expected administrator name field.")
        administratorNameField.tap()
        administratorNameField.typeText("UI Test Admin")

        navigationBars["Create a Family"].buttons["Create"].tap()
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

    @MainActor
    func addMemberNamedForInviteSheetVerification() {
        let addButton = buttons["Add family member"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Expected add member button to exist.")
        addButton.tap()

        XCTAssertTrue(navigationBars["Add Family Member"].waitForExistence(timeout: 5))

        let nameField = textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Expected name field in add member sheet.")
        nameField.tap()
        nameField.typeText("UI Test Invite Recipient")

        let enterBirthdateButton = buttons["Enter birthdate"]
        XCTAssertTrue(enterBirthdateButton.exists, "Expected an explicit birthdate action for a child.")
        enterBirthdateButton.tap()
        XCTAssertFalse(enterBirthdateButton.exists, "Expected the entry action to be replaced after choosing a birthdate.")

        let saveButton = navigationBars["Add Family Member"].buttons["Save"]
        XCTAssertTrue(saveButton.exists, "Expected save button in add member sheet.")
        saveButton.tap()
    }

    @MainActor
    func assertInviteReadySheetIsVisible() {
        let inviteReadyTitle = staticTexts["Invite Ready"]
        XCTAssertTrue(inviteReadyTitle.waitForExistence(timeout: 8), "Expected the Invite Ready sheet to appear after saving a new member.")

        XCTAssertTrue(buttons["Share Invite"].exists)
        XCTAssertTrue(buttons["Copy Code"].exists)
        XCTAssertTrue(buttons["Done"].exists)

        let invitationCodeLabel = staticTexts["Invitation code"]
        XCTAssertTrue(invitationCodeLabel.exists)
    }
}
