import XCTest

final class MyScreenTimeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testParentSetupCreatesTheDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 5))

        let nameField = app.textFields["parent-name-field"]
        nameField.tap()
        nameField.typeText("Alex")
        app.buttons["save-parent-profile"].tap()

        XCTAssertTrue(app.navigationBars["MyScreenTime"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome, Alex"].exists)

        app.buttons["add-child-button"].tap()
        XCTAssertTrue(app.navigationBars["Add Child"].waitForExistence(timeout: 5))

        let childNameField = app.textFields["child-name-field"]
        childNameField.tap()
        childNameField.typeText("Sam")
        app.buttons["save-child-profile"].tap()

        XCTAssertTrue(app.staticTexts["Sam"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 min used • 2 hr remaining"].exists)

        app.staticTexts["Sam"].tap()
        XCTAssertTrue(app.navigationBars["Sam"].waitForExistence(timeout: 5))

        app.buttons["add-device-button"].tap()
        XCTAssertTrue(app.navigationBars["Add Device"].waitForExistence(timeout: 5))

        let deviceNameField = app.textFields["device-name-field"]
        deviceNameField.tap()
        deviceNameField.typeText("Sam's iPhone")
        app.buttons["save-device"].tap()

        XCTAssertTrue(app.staticTexts["Sam's iPhone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Phone"].exists)

        app.swipeUp()
        app.buttons["add-usage-button"].tap()
        XCTAssertTrue(app.navigationBars["Add Usage"].waitForExistence(timeout: 5))
        let durationPreview = app.descendants(matching: .any)["duration-preview"]
        XCTAssertTrue(durationPreview.exists)
        app.buttons["save-usage"].tap()

        XCTAssertTrue(app.staticTexts["30 min"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["today-used-total"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["today-limit-balance"].exists)

        app.buttons["add-usage-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["overlap-warning"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-usage"].isEnabled)
        app.buttons["Cancel"].tap()

        let usageRow = app.descendants(matching: .any)["usage-session-row"]
        usageRow.tap()
        XCTAssertTrue(app.navigationBars["Edit Usage"].waitForExistence(timeout: 5))

        let noteField = app.textFields["usage-note-field"]
        noteField.tap()
        noteField.typeText("Homework")
        app.buttons["save-usage"].tap()

        XCTAssertTrue(usageRow.waitForExistence(timeout: 5))
        usageRow.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete this usage session?"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Usage Recorded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["today-used-total"].exists)
    }
}
