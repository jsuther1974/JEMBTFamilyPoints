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
    func testStorefrontReplacesRecordTabAndUsesFamilyName() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-store-brand-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()

        let storeTab = app.tabBars.buttons["Store"]
        XCTAssertTrue(storeTab.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Record"].exists)
        storeTab.tap()

        XCTAssertTrue(app.navigationBars["UI Test Family"].waitForExistence(timeout: 5))
        let sign = app.descendants(matching: .any)["storefrontSign"]
        XCTAssertTrue(sign.waitForExistence(timeout: 5))
        XCTAssertTrue(sign.label.contains("UI Test Family"))

        let existingItem = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '15 minutes extra screen time'")
        ).firstMatch
        XCTAssertTrue(existingItem.waitForExistence(timeout: 5))
        existingItem.tap()
        XCTAssertTrue(app.navigationBars["Edit Prize"].waitForExistence(timeout: 5))
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(" - Edited")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Edited'")).firstMatch.waitForExistence(timeout: 5))

        let addItem = app.descendants(matching: .any)["addStoreItem"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()
        XCTAssertTrue(app.navigationBars["New Prize"].waitForExistence(timeout: 5))
        let newNameField = app.textFields["Name"]
        XCTAssertTrue(newNameField.waitForExistence(timeout: 5))
        newNameField.tap()
        newNameField.typeText("Family Game")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Family Game'")).firstMatch.waitForExistence(timeout: 5))
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
    func testFamilyStorefrontOpensWithParentManagement() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()
        let storeTab = app.tabBars.buttons["Store"]
        XCTAssertTrue(storeTab.waitForExistence(timeout: 5))
        storeTab.tap()

        XCTAssertFalse(app.buttons["Manage Items"].exists)
        XCTAssertTrue(app.staticTexts["Manage the family store"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'points to spend'")).count, 0)
        XCTAssertTrue(app.staticTexts["15 minutes extra screen time"].waitForExistence(timeout: 5))

        let addItem = app.descendants(matching: .any)["addStoreItem"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))

        let existingItem = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '15 minutes extra screen time'")
        ).firstMatch
        XCTAssertTrue(existingItem.waitForExistence(timeout: 5))
        existingItem.tap()
        XCTAssertTrue(app.navigationBars["Edit Prize"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        XCTAssertTrue(addItem.waitForExistence(timeout: 5))
        addItem.tap()
        XCTAssertTrue(app.navigationBars["New Prize"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        app.openFamilyTab()
        let familyStoreLink = app.descendants(matching: .any)["familyStorefrontLink"]
        XCTAssertTrue(familyStoreLink.waitForExistence(timeout: 5))
        let settlementLink = app.descendants(matching: .any)["familySettlementLink"]
        XCTAssertTrue(settlementLink.exists)
        settlementLink.tap()
        XCTAssertTrue(app.navigationBars["Weekly Settlement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reportingWeekPicker"].exists)
        app.navigationBars["Weekly Settlement"].buttons.firstMatch.tap()
        XCTAssertTrue(familyStoreLink.waitForExistence(timeout: 5))
        familyStoreLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["storefrontSign"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddMemberShowsInviteReadySheetImmediately() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-admin-\(UUID().uuidString)@local"
        app.launchEnvironment["UITEST_DEFAULT_MEMBER_ROLE"] = "parent"
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
    func testCaregiverCardDoesNotShowPoints() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-caregiver-card-\(UUID().uuidString)@local"
        app.launchEnvironment["UITEST_DEFAULT_MEMBER_ROLE"] = "caregiver"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        let addButton = app.buttons["Add family member"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UI Test Caregiver")
        XCTAssertEqual(app.textFields["Role"].value as? String, "Caregiver")
        app.navigationBars["Add Family Member"].buttons["Save"].tap()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 8))
        doneButton.tap()

        let caregiverName = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'UI Test Caregiver'")
        ).firstMatch
        for _ in 0..<5 where !caregiverName.exists {
            app.swipeUp()
        }
        XCTAssertTrue(caregiverName.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["pointsSummary-UI Test Caregiver"].exists)
        XCTAssertFalse(app.buttons["Reward UI Test Caregiver"].exists)
        XCTAssertFalse(app.buttons["Penalize UI Test Caregiver"].exists)
    }

    @MainActor
    func testFamilyPageShowsPointsInMemberCardsWithoutStandaloneWeekSection() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()
        app.openFamilyTab()

        let reportingWeek = app.descendants(matching: .any)["reportingWeekPicker"]
        XCTAssertTrue(reportingWeek.waitForExistence(timeout: 5), "Expected the selected week to be visible and changeable on Family.")

        let childPoints = app.staticTexts["pointsSummary-Mateo"]
        XCTAssertTrue(childPoints.waitForExistence(timeout: 5), "Expected points in Mateo's member card.")
        XCTAssertTrue(app.staticTexts["Pending approval"].exists)

        let parentPoints = app.staticTexts["pointsSummary-Daddy"]
        for _ in 0..<4 where !parentPoints.exists {
            app.swipeUp()
        }
        XCTAssertTrue(parentPoints.waitForExistence(timeout: 5), "Expected points in Daddy's member card.")

        for redundantRole in ["Child", "Parent", "Caregiver"] {
            XCTAssertFalse(app.staticTexts[redundantRole].exists, "Expected section headings, not a redundant \(redundantRole) label in each card.")
        }
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists)
    }

    @MainActor
    func testFamilyQuickAwardSavesAndAppearsInWeeklyLedger() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()
        app.openFamilyTab()

        let rewardMateo = app.buttons["Reward Mateo"]
        let penalizeMateo = app.buttons["Penalize Mateo"]
        XCTAssertTrue(rewardMateo.waitForExistence(timeout: 5))
        XCTAssertTrue(penalizeMateo.exists)
        rewardMateo.tap()

        let saveButton = app.navigationBars.buttons["Save"]
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.exists)
        XCTAssertFalse(saveButton.isEnabled)

        let advocateAward = app.buttons["quickRule-Advocate Award"]
        let readingAward = app.buttons["quickRule-Read to or with family"]
        XCTAssertTrue(advocateAward.waitForExistence(timeout: 5))
        advocateAward.tap()
        for _ in 0..<4 where !readingAward.exists {
            app.swipeUp()
        }
        XCTAssertTrue(readingAward.waitForExistence(timeout: 5))
        readingAward.tap()

        let currentWeekday = Calendar.current.component(.weekday, from: Date.now)
        let secondWeekday = currentWeekday == 7 ? 1 : currentWeekday + 1
        let advocateCurrentDay = app.buttons["activityDay-Advocate Award-\(currentWeekday)"]
        let advocateSecondDay = app.buttons["activityDay-Advocate Award-\(secondWeekday)"]
        let readingCurrentDay = app.buttons["activityDay-Read to or with family-\(currentWeekday)"]
        let readingSecondDay = app.buttons["activityDay-Read to or with family-\(secondWeekday)"]
        for _ in 0..<4 where !advocateCurrentDay.exists || !advocateSecondDay.exists {
            app.swipeUp()
        }
        XCTAssertTrue(advocateCurrentDay.waitForExistence(timeout: 5))
        XCTAssertEqual(advocateCurrentDay.value as? String, "Selected")
        XCTAssertEqual(advocateSecondDay.value as? String, "Not selected")
        advocateSecondDay.tap()
        XCTAssertEqual(advocateSecondDay.value as? String, "Selected")
        advocateCurrentDay.tap()
        advocateSecondDay.tap()
        XCTAssertFalse(saveButton.isEnabled)
        advocateCurrentDay.tap()
        advocateSecondDay.tap()
        XCTAssertTrue(saveButton.isEnabled)
        let advocatePoints = app.descendants(matching: .any)["quickActivityPoints-Advocate Award"]
        XCTAssertTrue(advocatePoints.waitForExistence(timeout: 5))
        for _ in 0..<4 where !readingCurrentDay.exists || !readingSecondDay.exists {
            app.swipeUp()
        }
        XCTAssertTrue(readingCurrentDay.waitForExistence(timeout: 5))
        XCTAssertEqual(readingCurrentDay.value as? String, "Selected")
        XCTAssertEqual(readingSecondDay.value as? String, "Not selected")

        let readingPoints = app.descendants(matching: .any)["quickActivityPoints-Read to or with family"]
        let readingQuantity = app.descendants(matching: .any)["quickActivityQuantity-Read to or with family"]
        for _ in 0..<4 where !readingPoints.exists || !readingQuantity.exists {
            app.swipeUp()
        }
        XCTAssertTrue(readingPoints.waitForExistence(timeout: 5))
        XCTAssertEqual(readingQuantity.value as? String, "1")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let ledgerLink = app.descendants(matching: .any)["weeklyLedgerLink"]
        for _ in 0..<4 where !ledgerLink.exists {
            app.swipeDown()
        }
        XCTAssertTrue(ledgerLink.waitForExistence(timeout: 5))
        ledgerLink.tap()

        XCTAssertTrue(app.navigationBars["Weekly Ledger"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reportingWeekPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["weeklyLedgerHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ledgerStartingValue-Mateo"].waitForExistence(timeout: 5))
        let advocateRows = app.descendants(matching: .any).matching(identifier: "ledgerSummary-Mateo-Advocate Award")
        XCTAssertGreaterThanOrEqual(advocateRows.count, 2)
        XCTAssertTrue(advocateRows.firstMatch.label.localizedCaseInsensitiveContains("recorded by"))
        XCTAssertTrue(app.descendants(matching: .any)["ledgerSummary-Mateo-Read to or with family"].waitForExistence(timeout: 5))
        let approvedStatus = app.descendants(matching: .any).matching(identifier: "ledgerStatus-Mateo-Advocate Award").firstMatch
        XCTAssertTrue(approvedStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(approvedStatus.label, "Approved")

        let itemSort = app.buttons["ledgerSort-item"]
        let typeSort = app.buttons["ledgerSort-type"]
        XCTAssertTrue(itemSort.waitForExistence(timeout: 5))
        itemSort.tap()
        typeSort.tap()
        let resetSort = app.buttons["resetLedgerSort"]
        XCTAssertTrue(resetSort.exists)
        XCTAssertTrue(resetSort.isEnabled)
        resetSort.tap()
        XCTAssertFalse(resetSort.isEnabled)

        advocateRows.firstMatch.doubleTap()
        XCTAssertTrue(app.navigationBars["Edit Ledger Item"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Advocate Award"].exists)
        XCTAssertTrue(app.staticTexts["Mateo"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Mommy' OR label CONTAINS[c] 'Parent'")).firstMatch.exists)
        app.navigationBars["Edit Ledger Item"].buttons["Cancel"].tap()

        let readingRow = app.descendants(matching: .any)
            .matching(identifier: "ledgerSummary-Mateo-Read to or with family")
            .firstMatch
        readingRow.doubleTap()
        XCTAssertTrue(app.navigationBars["Edit Ledger Item"].waitForExistence(timeout: 5))
        let typedQuantity = app.descendants(matching: .any)["ledgerQuantity"]
        XCTAssertTrue(typedQuantity.waitForExistence(timeout: 5))
        XCTAssertTrue(typedQuantity.label.localizedCaseInsensitiveContains("minute"))
        app.navigationBars["Edit Ledger Item"].buttons["Cancel"].tap()

        app.navigationBars["Weekly Ledger"].buttons.firstMatch.tap()
        let penalizeDaddy = app.buttons["Penalize Daddy"]
        for _ in 0..<5 where !penalizeDaddy.exists {
            app.swipeUp()
        }
        XCTAssertTrue(penalizeDaddy.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reward Daddy"].exists)
    }

    @MainActor
    func testFamilyStatisticsPageIsAvailableWithoutAddingASixthTab() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()

        XCTAssertEqual(app.tabBars.buttons.count, 5)
        let statsLink = app.descendants(matching: .any)["familyStatisticsLink"]
        XCTAssertTrue(statsLink.waitForExistence(timeout: 5))
        statsLink.tap()

        XCTAssertTrue(app.navigationBars["Stats & Trends"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["familyStatisticsPage"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["statsWeeklyTrendChart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["statsYearChart"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["statsProjectionChart"].exists)
    }

    @MainActor
    func testLedgerTabReplacesStandaloneApprovalsPage() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()

        XCTAssertFalse(app.tabBars.buttons["Approvals"].exists)
        let ledgerTab = app.tabBars.buttons["Ledger"]
        XCTAssertTrue(ledgerTab.waitForExistence(timeout: 5))
        ledgerTab.tap()

        XCTAssertTrue(app.navigationBars["Weekly Ledger"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reportingWeekPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ledgerSettlementLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["weeklyLedgerHeader"].waitForExistence(timeout: 5))

        let leadingColumns = ["type", "status", "day", "person", "item"].map {
            app.buttons["ledgerSort-\($0)"]
        }
        leadingColumns.forEach { XCTAssertTrue($0.waitForExistence(timeout: 5)) }
        for (left, right) in zip(leadingColumns, leadingColumns.dropFirst()) {
            XCTAssertLessThan(left.frame.minX, right.frame.minX)
        }

        let copyWeek = app.buttons["copyLedgerWeek"]
        XCTAssertTrue(copyWeek.waitForExistence(timeout: 5))
        copyWeek.tap()
        XCTAssertTrue(app.navigationBars["Copy Rewards & Fines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["copySourceWeek"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testRuleCatalogsHaveSingleBackButton() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()

        let rulesTab = app.tabBars.buttons["Rules"]
        XCTAssertTrue(rulesTab.waitForExistence(timeout: 5), "Expected Rules to be a direct tab.")
        rulesTab.tap()

        XCTAssertFalse(app.staticTexts["Rewards Shop"].exists)

        for title in ["Earn Points", "Lose Points"] {
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
