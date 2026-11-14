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
            NSPredicate(format: "label BEGINSWITH 'Extra 15 minutes of screen time'")
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
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-current-member-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()

        let currentMemberCard = app.buttons["memberCard-UI Test Admin"]
        XCTAssertTrue(currentMemberCard.waitForExistence(timeout: 8), "Expected the current administrator's member card.")
        XCTAssertFalse(app.buttons["Create invitation for UI Test Admin"].exists)
        XCTAssertFalse(app.buttons["Share invitation for UI Test Admin"].exists)
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
        XCTAssertTrue(app.staticTexts["Extra 15 minutes of screen time"].waitForExistence(timeout: 5))

        let addItem = app.descendants(matching: .any)["addStoreItem"]
        XCTAssertTrue(addItem.waitForExistence(timeout: 5))

        let existingItem = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Extra 15 minutes of screen time'")
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
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'shop-'")).firstMatch.exists)
        let mateoCard = app.buttons["memberCard-Mateo"]
        XCTAssertTrue(mateoCard.waitForExistence(timeout: 5))
        mateoCard.tap()
        XCTAssertTrue(app.navigationBars["Mateo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["storefrontSign"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["memberDetailAvatar-Mateo"].exists)
        XCTAssertFalse(app.navigationBars["Send Invitation"].exists, "The card itself must not open invitation sharing.")
        XCTAssertTrue(app.staticTexts["Activity trends"].exists)
        app.buttons["Done"].tap()

        XCTAssertFalse(app.descendants(matching: .any)["familySettlementLink"].exists)
        XCTAssertFalse(app.tabBars.buttons["Settlement"].exists)

        let storeTabAgain = app.tabBars.buttons["Store"]
        XCTAssertTrue(storeTabAgain.waitForExistence(timeout: 5))
        storeTabAgain.tap()
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

        let familyActions = app.descendants(matching: .any)["familyActions"]
        XCTAssertTrue(familyActions.waitForExistence(timeout: 5))
        familyActions.tap()
        let editFamilySettingsButton = app.buttons["Edit family settings"]
        XCTAssertTrue(editFamilySettingsButton.waitForExistence(timeout: 5), "Expected the family-settings button to exist.")
        editFamilySettingsButton.tap()

        XCTAssertTrue(
            app.navigationBars["Family Settings"].waitForExistence(timeout: 5),
            "Expected tapping the family-settings button to open the editor."
        )
        XCTAssertTrue(app.textFields["familyCashValuePerPoint"].exists)
        app.buttons["Cancel"].tap()

        let adminCard = app.buttons["memberCard-UI Test Admin"]
        XCTAssertTrue(adminCard.waitForExistence(timeout: 5))
        adminCard.tap()
        XCTAssertTrue(app.navigationBars["UI Test Admin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["memberDetailAvatar-UI Test Admin"].exists)
        XCTAssertTrue(app.buttons["editMemberFromDetails"].exists)
        app.buttons["editMemberFromDetails"].tap()
        XCTAssertTrue(app.buttons["chooseMemberAvatar"].waitForExistence(timeout: 5))
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
            app.buttons["familyActions"].waitForExistence(timeout: 5),
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
        app.openAddMemberEditor()

        XCTAssertTrue(app.navigationBars["Add Family Member"].waitForExistence(timeout: 5))
        let birthdateField = app.textFields["Birthdate"]
        XCTAssertTrue(birthdateField.exists, "Expected a keyboard-accessible birthdate field.")
        XCTAssertEqual(birthdateField.value as? String, "Enter birthdate")
    }

    @MainActor
    func testBirthdatePickerWaitsForExplicitConfirmation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-birthday-confirmation-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.openAddMemberEditor()

        let birthdateField = app.textFields["Birthdate"]
        XCTAssertTrue(birthdateField.waitForExistence(timeout: 5))
        birthdateField.tap()

        let confirmButton = app.buttons["Use This Date"]
        if !confirmButton.waitForExistence(timeout: 1) {
            // The first tap can scroll this lower Form row into view without focusing it.
            birthdateField.tap()
        }
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2))

        let firstDateWheel = app.pickerWheels.firstMatch
        XCTAssertTrue(firstDateWheel.waitForExistence(timeout: 3))
        firstDateWheel.swipeUp()

        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 2),
            "Changing a date component must not dismiss the birthdate picker."
        )
        XCTAssertTrue(firstDateWheel.exists)

        confirmButton.tap()
        XCTAssertFalse(firstDateWheel.exists)
        XCTAssertNotEqual(birthdateField.value as? String, "Enter birthdate")
    }

    @MainActor
    func testAddMemberStartsWithNameFocused() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-member-focus-\(UUID().uuidString)@local"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.openAddMemberEditor()

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
        app.openAddMemberEditor()

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
    func testRegularWidthAddMemberControlsRemainInteractiveAfterTextEntry() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-ipad-member-controls-\(UUID().uuidString)@local"
        app.launch()

        try XCTSkipUnless(
            app.windows.firstMatch.frame.width >= 700,
            "This regression covers the regular-width iPad member editor."
        )

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.openAddMemberEditor()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("iPad Member")

        let rolePicker = app.descendants(matching: .any)["memberRolePicker"]
        XCTAssertTrue(rolePicker.waitForExistence(timeout: 5), "Expected the native iPad role picker.")
        rolePicker.tap()
        let parentRole = app.buttons["Parent"]
        XCTAssertTrue(parentRole.waitForExistence(timeout: 3), "Expected role choices to open after entering text.")
        parentRole.tap()

        let addBirthday = app.descendants(matching: .any)["addMemberBirthdate"]
        XCTAssertTrue(addBirthday.waitForExistence(timeout: 3), "Expected the optional birthday control to remain reachable.")
        addBirthday.tap()

        let birthdayPicker = app.descendants(matching: .any)["memberBirthdatePicker"]
        XCTAssertTrue(birthdayPicker.waitForExistence(timeout: 3), "Expected the native date picker after adding a birthday.")
        let clearBirthday = app.buttons["Clear optional birthday"]
        XCTAssertTrue(clearBirthday.waitForExistence(timeout: 3))
        clearBirthday.tap()

        app.navigationBars["Add Family Member"].buttons["Save"].tap()
        app.assertInviteReadySheetIsVisible()
    }

    @MainActor
    func testCaregiverCardDoesNotShowPoints() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_APPLE_ID"] = "ui-test-caregiver-card-\(UUID().uuidString)@local"
        app.launchEnvironment["UITEST_DEFAULT_MEMBER_ROLE"] = "caregiver"
        app.launch()

        app.signInAndCreateFamilyForAddingMembers()
        app.openFamilyTab()
        app.openAddMemberEditor()

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
        let familyOverview = app.descendants(matching: .any)["familyOverviewBanner"]
        XCTAssertTrue(familyOverview.exists)
        XCTAssertTrue(app.descendants(matching: .any)["familyNameHeading"].exists)
        XCTAssertLessThan(app.staticTexts["Children"].frame.minY, 220, "The compact summary should leave room for member cards.")

        let mateoCard = app.buttons["memberCard-Mateo"]
        XCTAssertFalse(mateoCard.label.contains("Child"), "Expected the Children heading, not a role label in Mateo's card.")
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

        let dishesAward = app.buttons["quickRule-Wash the dishes"]
        let laundryAward = app.buttons["quickRule-Help with laundry"]
        XCTAssertTrue(dishesAward.waitForExistence(timeout: 5))
        dishesAward.tap()
        for _ in 0..<4 where !laundryAward.exists {
            app.swipeUp()
        }
        XCTAssertTrue(laundryAward.waitForExistence(timeout: 5))
        laundryAward.tap()

        let configureButton = app.buttons["configureSelectedActivities"]
        XCTAssertTrue(configureButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isEnabled, "Defaults should support the fast select-and-save path.")
        configureButton.tap()
        XCTAssertTrue(app.navigationBars.buttons["Back"].waitForExistence(timeout: 5))

        let currentWeekday = Calendar.current.component(.weekday, from: Date.now)
        let secondWeekday = currentWeekday == 7 ? 1 : currentWeekday + 1
        let dishesCurrentDay = app.buttons["activityDay-Wash the dishes-\(currentWeekday)"]
        let dishesSecondDay = app.buttons["activityDay-Wash the dishes-\(secondWeekday)"]
        let laundryCurrentDay = app.buttons["activityDay-Help with laundry-\(currentWeekday)"]
        let laundrySecondDay = app.buttons["activityDay-Help with laundry-\(secondWeekday)"]
        for _ in 0..<4 where !dishesCurrentDay.exists || !dishesSecondDay.exists {
            app.swipeUp()
        }
        XCTAssertTrue(dishesCurrentDay.waitForExistence(timeout: 5))
        XCTAssertEqual(dishesCurrentDay.value as? String, "Selected")
        XCTAssertEqual(dishesSecondDay.value as? String, "Not selected")
        dishesSecondDay.tap()
        XCTAssertEqual(dishesSecondDay.value as? String, "Selected")
        dishesCurrentDay.tap()
        dishesSecondDay.tap()
        XCTAssertFalse(saveButton.isEnabled)
        dishesCurrentDay.tap()
        dishesSecondDay.tap()
        XCTAssertTrue(saveButton.isEnabled)
        let dishesPoints = app.descendants(matching: .any)["quickActivityPoints-Wash the dishes"]
        XCTAssertTrue(dishesPoints.waitForExistence(timeout: 5))
        let dishesTotal = app.descendants(matching: .any)["quickActivityTotal-Wash the dishes"]
        XCTAssertTrue(dishesTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(dishesTotal.label.contains("150"))
        for _ in 0..<4 where !laundryCurrentDay.exists || !laundrySecondDay.exists {
            app.swipeUp()
        }
        XCTAssertTrue(laundryCurrentDay.waitForExistence(timeout: 5))
        XCTAssertEqual(laundryCurrentDay.value as? String, "Selected")
        XCTAssertEqual(laundrySecondDay.value as? String, "Not selected")

        let laundryPoints = app.descendants(matching: .any)["quickActivityPoints-Help with laundry"]
        let laundryQuantity = app.descendants(matching: .any)["quickActivityQuantity-Help with laundry"]
        for _ in 0..<4 where !laundryPoints.exists || !laundryQuantity.exists {
            app.swipeUp()
        }
        XCTAssertTrue(laundryPoints.waitForExistence(timeout: 5))
        XCTAssertEqual(laundryQuantity.value as? String, "1")
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

        let dayRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "ledgerDay-Mateo-")
        )
        XCTAssertGreaterThanOrEqual(dayRows.count, 2, "Expected one collapsed row for each active day.")
        let dishesRows = app.descendants(matching: .any).matching(identifier: "ledgerSummary-Mateo-Wash the dishes")
        for index in 0..<dayRows.count where dishesRows.count < 2 {
            let dayRow = dayRows.element(boundBy: index)
            XCTAssertTrue(dayRow.waitForExistence(timeout: 5))
            dayRow.tap()
            _ = dishesRows.element(boundBy: 1).waitForExistence(timeout: 1)
        }

        XCTAssertGreaterThanOrEqual(dishesRows.count, 2)
        XCTAssertTrue(app.descendants(matching: .any)["ledgerSummary-Mateo-Help with laundry"].waitForExistence(timeout: 5))

        dishesRows.firstMatch.doubleTap()
        XCTAssertTrue(app.navigationBars["Edit Ledger Item"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wash the dishes"].exists)
        XCTAssertTrue(app.staticTexts["Mateo"].exists)
        XCTAssertTrue(app.staticTexts["Recorded by"].exists)
        app.navigationBars["Edit Ledger Item"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Weekly Ledger"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFamilyStatisticsPageIsAvailableAsTopLevelTab() throws {
        let app = XCUIApplication()
        app.launch()

        app.signInAndJoinDemoFamilyIfNeeded()

        XCTAssertEqual(app.tabBars.buttons.count, 5)
        let statsTab = app.tabBars.buttons["Stats"]
        XCTAssertTrue(statsTab.waitForExistence(timeout: 5))
        statsTab.tap()

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
        XCTAssertFalse(app.descendants(matching: .any)["ledgerSettlementLink"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["weeklyLedgerHeader"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Starting points"].exists)
        XCTAssertTrue(app.staticTexts["Activity by day"].exists)
        XCTAssertFalse(app.buttons["ledgerSort-item"].exists)

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
    func addMemberNamedForInviteSheetVerification() {
        openAddMemberEditor()

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
    func openAddMemberEditor() {
        let familyActions = descendants(matching: .any)["familyActions"]
        XCTAssertTrue(familyActions.waitForExistence(timeout: 5), "Expected Family actions menu to exist.")
        familyActions.tap()
        let addButton = buttons["Add family member"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Expected add member button to exist.")
        addButton.tap()
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
