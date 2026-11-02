import XCTest

/// Real XCUIApplication interactions against UUID-isolated Debug stores.
/// HTTP fixtures are explicit; live services are tested separately in FueliTests.
@MainActor final class AppJourneyTests: XCTestCase {
    private var app: XCUIApplication!
    private var storeID = UUID().uuidString
    private var fixtureRoot: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        storeID = UUID().uuidString
        app = XCUIApplication()
    }
    override func tearDownWithError() throws {
        if testRun?.failureCount ?? 0 > 0, app.state == .runningForeground {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
    }
    private func launch(_ extra: [String] = [], photo: Bool = false, receipt: Bool = false) {
        app.launchArguments = ["--fueli-ui-testing", "--fueli-ui-store", storeID,
            "--fueli-ui-network-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        if photo { app.launchEnvironment["FUELI_UI_PHOTO_PATH"] = fixtureRoot + "/FueliTests/ApplicationFixtures/banana.jpg" }
        if receipt { app.launchEnvironment["FUELI_UI_RECEIPT_PATH"] = fixtureRoot + "/FueliTests/SyntheticReceipt.png" }
        app.launch()
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI Form lazily creates offscreen rows. Scroll before asserting existence.
        if !element.exists { _ = element.waitForExistence(timeout: 2) }
        for _ in 0..<7 {
            if element.exists && element.isHittable { break }
            scroll(up: true)
        }
        if !element.exists || !element.isHittable {
            for _ in 0..<7 {
                scroll(up: false)
                if element.exists && element.isHittable { break }
            }
        }
        XCTAssertTrue(element.exists, "Missing control: \(element)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Control cannot be reached", file: file, line: line)
        element.tap()
    }
    private func scroll(up: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.15))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.15 : 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    private func fill(_ field: XCUIElement, _ text: String) {
        tap(field)
        let old = field.value as? String ?? ""
        // A center tap can put the caret before existing trailing-aligned digits.
        // Move it to the end before deleting, then assert the actual replacement.
        if !old.isEmpty && field.elementType == .textField && !["confirm.Calories", "confirm.Protein", "confirm.Carbs", "confirm.Fat", "confirm.Fiber"].contains(field.identifier) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        }
        if !app.keyboards.firstMatch.exists && !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
        if app.buttons["Done Editing"].exists { app.buttons["Done Editing"].tap() }
        let actual = field.value as? String ?? ""
        if let expectedNumber = Double(text), expectedNumber.isFinite {
            XCTAssertEqual(Double(actual.replacingOccurrences(of: ",", with: "")), expectedNumber,
                "Numeric replacement must not retain digits from the previous value")
        } else { XCTAssertEqual(actual, text) }
    }
    private func route(_ title: String) {
        tap(app.tabBars.buttons["Log"])
        tap(app.buttons["hub." + title])
        if title == "My Foods" { XCTAssertTrue(app.navigationBars["My Foods"].waitForExistence(timeout: 10)) }
    }
    private func closeFoods() { tap(app.navigationBars["My Foods"].buttons["Close"]) }
    private func manual(_ name: String, calories: String = "150.125") {
        route("Enter Manually")
        fill(app.textFields["manual.name"], name)
        for (field, value) in [("caloriesText", calories), ("proteinText", "10"), ("carbsText", "20"), ("fatText", "3"), ("fiberText", "0")] {
            fill(app.textFields["manual." + field], value)
        }
        tap(app.buttons["Next"])
        XCTAssertTrue(app.navigationBars["Confirm"].waitForExistence(timeout: 10))
    }
    private func assertEaten(_ calories: Int) {
        XCTAssertTrue(app.staticTexts["\(calories) eaten"].waitForExistence(timeout: 10))
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testEveryLoggingRouteOpensAndCancelsWithoutLogging() {
        launch()
        for (routeName, close) in [("Enter Manually", "Cancel"), ("Describe a Meal", "Cancel"),
            ("Scan a Barcode", "Cancel"), ("Take a Photo", "Cancel"), ("Scan Receipt", "Done"),
            ("Create Meal", "Close"), ("My Foods", "Close"), ("Log a Workout", "Cancel")] {
            route(routeName)
            if routeName == "My Foods" { closeFoods() } else { tap(app.buttons[close].firstMatch) }
            assertEaten(0)
        }
    }

    func testSaveThreeServingsPersistsOneStandardThenLogsHalfAfterRelaunch() {
        launch(); manual("QA Saved Food")
        fill(app.textFields["serving.amount"], "3")
        tap(app.buttons["Save to My Foods"])
        XCTAssertTrue(app.alerts["Saved to My Foods"].waitForExistence(timeout: 5))
        tap(app.alerts.buttons["Done"]); assertEaten(0)
        app.terminate(); launch()
        route("My Foods"); tap(app.buttons["library.QA Saved Food"])
        XCTAssertEqual(app.textFields["confirm.Calories"].value as? String, "150.125")
        fill(app.textFields["serving.amount"], "0.5")
        screenshot("Half serving of a saved standard")
        tap(app.buttons["Log Food"]); assertEaten(75)
        route("My Foods"); tap(app.buttons["library.QA Saved Food"])
        XCTAssertEqual(app.textFields["confirm.Calories"].value as? String, "150.125")
        tap(app.buttons["Cancel"])
    }

    func testLogOnlyAndInvalidManualInput() {
        launch(); route("Enter Manually")
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        fill(app.textFields["manual.name"], "Invalid food")
        fill(app.textFields["manual.caloriesText"], "nan")
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        tap(app.buttons["Cancel"]); assertEaten(0)
        manual("QA Log Only", calories: "200")
        fill(app.textFields["serving.amount"], "2.5")
        tap(app.buttons["Log Food"]); assertEaten(500)
        route("My Foods")
        XCTAssertFalse(app.buttons["library.QA Log Only"].exists)
        closeFoods()
    }

    func testSavedFoodEditCannotChangeHistoricalSnapshotAndDeleteRequiresConfirmation() {
        launch(); route("My Foods"); tap(app.buttons["library.QA Oats"])
        fill(app.textFields["serving.amount"], "0.5"); tap(app.buttons["Log Food"]); assertEaten(75)
        route("My Foods"); tap(app.buttons["library.QA Oats"])
        fill(app.textFields["confirm.Calories"], "900")
        tap(app.buttons["Update Saved Food"]); tap(app.alerts.buttons["Done"]); assertEaten(75)
        route("My Foods")
        app.buttons["library.QA Oats"].swipeLeft()
        tap(app.buttons["Delete"].firstMatch)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        tap(app.buttons["Delete"].firstMatch)
        XCTAssertFalse(app.buttons["library.QA Oats"].exists)
        closeFoods()
        tap(app.tabBars.buttons["History"])
        XCTAssertTrue(app.staticTexts["QA Oats"].waitForExistence(timeout: 5))
    }

    func testRecipeBuilderFractionalIngredientsSaveAndLog() {
        launch(); route("Create Meal")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "QA Oats ·")).firstMatch)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "QA Yogurt ·")).firstMatch)
        fill(app.textFields.matching(identifier: "serving.amount").element(boundBy: 0), "2.5")
        fill(app.textFields.matching(identifier: "serving.amount").element(boundBy: 1), "0.5")
        tap(app.buttons["Save Recipe to My Foods"]); assertEaten(0)
        route("My Foods"); tap(app.buttons["library.My Meal"])
        fill(app.textFields["serving.amount"], "0.5")
        tap(app.buttons["Log Food"]); assertEaten(213)
    }

    func testBarcodeManualFallbackAndInvalidChecksum() {
        launch(); route("Scan a Barcode")
        fill(app.textFields["Barcode number"], "036000291453")
        tap(app.buttons["Look Up"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "checksum")).firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["Cancel"]); route("Scan a Barcode")
        fill(app.textFields["Barcode number"], "036000291452")
        tap(app.buttons["Look Up"])
        XCTAssertTrue(app.navigationBars["Confirm"].waitForExistence(timeout: 15))
        fill(app.textFields["serving.amount"], "2.5")
        tap(app.buttons["Log Food"]); assertEaten(375)
    }

    func testManualDescriptionUSDAAndDatabaseReview() {
        launch(); route("Describe a Meal")
        fill(app.textViews.firstMatch, "120 g banana")
        tap(app.buttons["Enter ingredients without AI"])
        XCTAssertTrue(app.textFields["ingredient.grams.0"].waitForExistence(timeout: 5))
        fill(app.textFields["ingredient.grams.0"], "150")
        tap(app.buttons["Continue to USDA Lookup"])
        XCTAssertTrue(app.navigationBars["Confirm"].waitForExistence(timeout: 15))
        tap(app.buttons["Log Food"]); assertEaten(134)
    }

    func testPhotoDescriptionEditAndOpenFoodFactsExplicitConfirmation() {
        launch(photo: true); route("Take a Photo")
        tap(app.buttons["Describe Photo with AI"])
        XCTAssertTrue(app.staticTexts["Review AI description"].waitForExistence(timeout: 15))
        fill(app.textFields["ingredient.grams.0"], "150")
        tap(app.buttons["nutrition.database"])
        tap(app.buttons["Open Food Facts"].firstMatch)
        tap(app.buttons["Continue to Open Food Facts Lookup"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "QA Banana Chips")).firstMatch)
        XCTAssertTrue(app.staticTexts["Confirm product match"].waitForExistence(timeout: 12))
        screenshot("Reviewed product match and quantity")
        tap(app.buttons["Use this product for this ingredient"])
        XCTAssertTrue(app.navigationBars["Confirm"].waitForExistence(timeout: 10))
        tap(app.buttons["Log Food"]); assertEaten(225)
    }

    func testNetworkFailurePreservesEditedDescriptionAndAllowsCancel() {
        launch(["--fueli-ui-network-error"]); route("Describe a Meal")
        fill(app.textViews.firstMatch, "120 g banana")
        tap(app.buttons["Enter ingredients without AI"])
        fill(app.textFields["ingredient.grams.0"], "150")
        tap(app.buttons["Continue to USDA Lookup"])
        XCTAssertTrue(app.buttons["Retry nutrition lookup"].waitForExistence(timeout: 12))
        tap(app.buttons["Edit ingredients / change database"])
        XCTAssertEqual(app.textFields["ingredient.grams.0"].value as? String, "150")
        tap(app.buttons["Cancel"]); assertEaten(0)
    }

    func testWorkoutSummaryDiscardAndSave() {
        launch(); route("Log a Workout"); tap(app.buttons["Walking"])
        tap(app.buttons["Finish Workout"])
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 5))
        tap(app.buttons["Discard"]); assertEaten(0)
        route("Log a Workout"); tap(app.buttons["Running"])
        tap(app.buttons["Finish Workout"]); tap(app.buttons["Save Workout"])
        assertEaten(0)
        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Walking"].exists)
    }

    func testReceiptOnDeviceOCRRequiresReviewAndNeverLogsConsumption() {
        launch(receipt: true); route("Scan Receipt")
        let recognized = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND NOT label BEGINSWITH %@", "receipt.summary", "0 rows")).firstMatch
        XCTAssertTrue(recognized.waitForExistence(timeout: 60), "On-device OCR must produce review rows")
        screenshot("On-device OCR receipt review")
        fill(app.textFields["receipt.name"].firstMatch, "banana")
        tap(app.buttons["Search USDA — review match"].firstMatch)
        tap(app.buttons["Bananas, raw · USDA 173944"])
        XCTAssertTrue(app.staticTexts["Saved to My Foods"].firstMatch.waitForExistence(timeout: 15))
        tap(app.buttons["Done"]); assertEaten(0)
        route("My Foods"); tap(app.buttons["library.Bananas, raw"])
        tap(app.textFields["confirm.Calories"])
        XCTAssertEqual(app.textFields["confirm.Calories"].value as? String, "89.0")
        fill(app.textFields["serving.amount"], "0.5")
        tap(app.buttons["Log Food"]); assertEaten(45)
    }

    func testWaterDateIsolationAndSettingsManualBurn() {
        launch(); tap(app.buttons["+16 oz"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "16 oz /")).firstMatch.exists)
        tap(app.buttons["Previous day"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "0 oz /")).firstMatch.exists)
        tap(app.buttons["Next day"])
        tap(app.buttons["Undo last water entry"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "0 oz /")).firstMatch.exists)
        tap(app.tabBars.buttons["Settings"]); tap(app.buttons["Goals & Profile"])
        fill(app.textFields["maintenance.burn"], "3000")
        tap(app.buttons["Use This Daily Burn"])
        screenshot("Manual total daily burn and goal-based intake")
        tap(app.navigationBars["Goals & Profile"].buttons["Save"])
        tap(app.navigationBars.buttons["Settings"])
        app.terminate(); launch(); assertEaten(0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3,000 kcal/day")).firstMatch.exists)
    }

    func testOnboardingManualBurnSkipsStepQuestionnaireAndPersists() {
        launch(["--fueli-ui-onboarding"])
        tap(app.buttons["Next"]); tap(app.buttons["Next"])
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        fill(app.textFields["onboarding.feet"], "5")
        fill(app.textFields["onboarding.inches"], "9")
        fill(app.textFields["onboarding.weight"], "165")
        tap(app.buttons["Next"]); tap(app.buttons["Next"])
        fill(app.textFields["onboarding.goalWeight"], "150")
        tap(app.buttons["Next"]); tap(app.buttons["Next"])
        fill(app.textFields["maintenance.burn"], "2500")
        tap(app.buttons["Use This Daily Burn"]); tap(app.buttons["Next"])
        XCTAssertTrue(app.staticTexts["Diet preference?"].exists)
        XCTAssertFalse(app.staticTexts["How many steps do you average each day?"].exists)
        tap(app.buttons["Next"])
        XCTAssertTrue(app.staticTexts["Your daily targets"].exists)
        screenshot("Goal calculation during onboarding")
        tap(app.buttons["Next"]); tap(app.buttons["Finish"])
        assertEaten(0); app.terminate(); launch(); assertEaten(0)
    }

    private func dismissFileSheet() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
    }

    func testBackupSystemFileSheetsCanBeCancelledWithoutMutation() {
        launch(); tap(app.tabBars.buttons["Settings"]); tap(app.buttons["Nutrition Backup"])
        tap(app.buttons["Export Foods, Recipes & Logs"])
        screenshot("System backup export sheet")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        dismissFileSheet()
        XCTAssertTrue(app.buttons["Import Backup"].isHittable)
        tap(app.buttons["Import Backup"])
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        if app.buttons["Cancel"].firstMatch.exists && app.buttons["Cancel"].firstMatch.isHittable {
            app.buttons["Cancel"].firstMatch.tap()
        } else { dismissFileSheet() }
        XCTAssertTrue(app.buttons["Export Foods, Recipes & Logs"].isHittable)
        tap(app.navigationBars.buttons["Settings"])
        tap(app.tabBars.buttons["Today"]); assertEaten(0)
    }

    func testSavedFoodLoggingWorksWhenEveryNetworkRequestIsOffline() {
        launch(["--fueli-ui-network-offline"]); route("My Foods")
        tap(app.buttons["library.QA Oats"])
        fill(app.textFields["serving.amount"], "0.5")
        tap(app.buttons["Log Food"]); assertEaten(75)
    }

    func testLibrarySearchAndFavoriteRemovalArePersistent() {
        launch(); route("My Foods")
        tap(app.buttons["library.filter"]); tap(app.buttons["Favorites"].firstMatch)
        XCTAssertTrue(app.buttons["library.QA Oats"].exists)
        XCTAssertFalse(app.buttons["library.QA Yogurt"].exists)
        app.buttons["library.QA Oats"].press(forDuration: 1)
        tap(app.buttons["Remove Favorite"])
        XCTAssertFalse(app.buttons["library.QA Oats"].exists)
        tap(app.buttons["library.filter"]); tap(app.buttons["All"].firstMatch)
        fill(app.searchFields.firstMatch, "Yogurt")
        XCTAssertTrue(app.buttons["library.QA Yogurt"].exists)
        XCTAssertFalse(app.buttons["library.QA Oats"].exists)
        // Submit search to dismiss its native interface and restore navigation.
        app.searchFields.firstMatch.typeText("\n")
        closeFoods()
        app.terminate(); launch(); route("My Foods")
        tap(app.buttons["library.filter"]); tap(app.buttons["Favorites"].firstMatch)
        XCTAssertFalse(app.buttons["library.QA Oats"].exists)
        closeFoods(); assertEaten(0)
    }

    func testHistoricalEntryCanBeEditedAndExplicitlyDeleted() {
        launch(); manual("QA History Entry", calories: "200")
        tap(app.buttons["Log Food"]); assertEaten(200)
        tap(app.tabBars.buttons["History"])
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.log.")).firstMatch)
        fill(app.textFields["editLog.name"], "QA Corrected History")
        fill(app.textFields["serving.amount"], "0.5")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["QA Corrected History"].waitForExistence(timeout: 5))
        tap(app.tabBars.buttons["Today"]); assertEaten(200)
        tap(app.tabBars.buttons["History"])
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.log.")).firstMatch)
        tap(app.buttons["Delete meal"]); tap(app.buttons["Delete"].firstMatch)
        tap(app.tabBars.buttons["Today"]); assertEaten(0)
    }

    func testSettingsHistoryStreaksAndBackupEntryPoints() {
        launch(); tap(app.tabBars.buttons["Settings"])
        for destination in ["Goals & Profile", "Food Database", "Health Connections", "Nutrition Backup", "AI Provider"] {
            tap(app.buttons[destination])
            XCTAssertTrue(app.navigationBars[destination == "Goals & Profile" ? "Goals & Profile" : destination].waitForExistence(timeout: 5))
            screenshot(destination)
            tap(app.navigationBars.buttons["Settings"])
        }
        tap(app.tabBars.buttons["History"]); tap(app.buttons["Add Weight"])
        fill(app.alerts.textFields.firstMatch, "-10")
        XCTAssertFalse(app.alerts.buttons["Save"].isEnabled)
        fill(app.alerts.textFields.firstMatch, "165")
        tap(app.alerts.buttons["Save"])
        tap(app.tabBars.buttons["Streaks"])
        XCTAssertTrue(app.navigationBars["Milestones"].waitForExistence(timeout: 5))
    }
}
