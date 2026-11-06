import XCTest

final class JEMBT_Family_Points_TrackerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSimulatorRoleAccountsAreAvailable() throws {
        let app = XCUIApplication()
        app.launch()

        let roleAccountMenu = app.buttons["Choose Simulator Role Account"]
        XCTAssertTrue(roleAccountMenu.waitForExistence(timeout: 5))
        roleAccountMenu.tap()

        for account in ["Parent Test Account", "Caregiver Test Account", "Child Test Account"] {
            XCTAssertTrue(app.buttons[account].waitForExistence(timeout: 2), "Expected \(account) in the simulator account menu.")
        }
    }

    @MainActor
    func testRecordActivityDetectsFreshFamilyAdminAsAdult() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-record-adult-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()

        let recordTab = app.tabBars.buttons["Record"]
        XCTAssertTrue(recordTab.waitForExistence(timeout: 5))
        recordTab.tap()

        XCTAssertTrue(app.navigationBars["Record Activity"].waitForExistence(timeout: 5))
        let accountType = app.staticTexts["submissionAccountType"]
        XCTAssertTrue(accountType.waitForExistence(timeout: 5))
        XCTAssertEqual(accountType.label, "Submitted by, Adult account")
        XCTAssertFalse(app.switches["Submitted by a child"].exists)
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
        let birthdateField = app.textFields["Birthdate"]
        XCTAssertTrue(birthdateField.exists, "Expected a keyboard-accessible birthdate field.")
        XCTAssertEqual(birthdateField.value as? String, "Enter birthdate")
    }

    @MainActor
    func testAddMemberStartsWithNameFocused() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-member-focus-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.buttons["Add family member"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            nameField.value(forKey: "hasKeyboardFocus") as? Bool,
            true,
            "Expected the Name field to receive focus when Add Family Member opens."
        )
    }

    @MainActor
    func testAddMemberTabOrderIncludesRoleAndBirthdate() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-member-tabs-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.buttons["Add family member"].tap()

        let nameField = app.textFields["Name"]
        let emailField = app.textFields["Email address (optional)"]
        let roleControl = app.textFields["Role"]
        let birthdateField = app.textFields["Birthdate"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let nameFocused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: nameField
        )
        XCTAssertEqual(XCTWaiter.wait(for: [nameFocused], timeout: 2), .completed)

        app.typeKey(.tab, modifierFlags: [])
        let emailFocused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: emailField
        )
        XCTAssertEqual(XCTWaiter.wait(for: [emailFocused], timeout: 2), .completed)
        XCTAssertTrue(roleControl.exists)
        XCTAssertTrue(birthdateField.exists)
    }

    @MainActor
    func testFamilyPageIncludesWeeklyStandingsWithoutDashboardTab() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()
        app.openFamilyTab()

        let weekHeading = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Week ending '")
        ).firstMatch
        XCTAssertTrue(weekHeading.waitForExistence(timeout: 5), "Expected weekly standings on the Family page.")
        XCTAssertTrue(app.staticTexts["Pending approval"].exists)
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists)
    }

    @MainActor
    func testRuleCatalogsHaveSingleBackButton() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()

        let rulesTab = app.tabBars.buttons["Rules"]
        XCTAssertTrue(rulesTab.waitForExistence(timeout: 5), "Expected Rules to be a direct tab.")
        rulesTab.tap()

        for title in ["Earn Points", "Lose Points", "Rewards Shop"] {
            let catalog = app.staticTexts[title]
            XCTAssertTrue(catalog.waitForExistence(timeout: 5))
            catalog.tap()

            let navigationBar = app.navigationBars[title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            XCTAssertEqual(navigationBar.buttons.matching(identifier: "Rules").count, 1, "Expected exactly one back button on \(title).")
            XCTAssertFalse(navigationBar.buttons["More"].exists, "\(title) must not be nested under the system More screen.")
            navigationBar.buttons["Rules"].tap()
        }
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
        for _ in 0..<4 where !meLabelElement.exists {
            swipeUp()
        }
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

        let roleField = textFields["Role"]
        XCTAssertTrue(roleField.exists, "Expected a role field when adding a member.")
        if keyboards.firstMatch.exists {
            keyboards.firstMatch.swipeDown()
        }
        roleField.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        let rolePicker = pickerWheels.firstMatch
        XCTAssertTrue(rolePicker.waitForExistence(timeout: 5))
        rolePicker.adjust(toPickerWheelValue: "Parent")
        XCTAssertEqual(roleField.value as? String, "Parent")

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
