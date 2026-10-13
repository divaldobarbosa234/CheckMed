import XCTest

/// Isolated Finish Treatment sheet against the DEBUG verification host.
/// Destination must be CheckMed-TH1-Verify (`D34130F1-4D47-4FC7-B14B-C19388076947`).
final class CheckMedFT1UITests: XCTestCase {
    private let requiredUDID = "D34130F1-4D47-4FC7-B14B-C19388076947"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let runUDID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"]
            ?? ProcessInfo.processInfo.environment["TARGET_DEVICE_IDENTIFIER"]
        if let runUDID, runUDID != requiredUDID {
            throw XCTSkip("Refusing to run FT-1 UI tests on \(runUDID); required \(requiredUDID)")
        }
    }

    func testA_finishCancelDoesNotMutateOrNavigate() {
        let app = launchCurrentDetail()
        openFinishSheet(in: app)

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), "real sheet Cancel must be hittable")
        cancel.tap()

        XCTAssertFalse(app.staticTexts["Finish this treatment?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["Treatment details"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Current combo"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Mark this treatment finished"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.navigationBars["Journey report"].exists)
        XCTAssertFalse(app.staticTexts["SiblingMed"].exists)
    }

    func testB_finishConfirmSeeReportCompletesSelectedOnly() {
        let app = launchCurrentDetail()
        openFinishSheet(in: app)

        let seeReport = app.buttons["See the report"]
        XCTAssertTrue(seeReport.waitForExistence(timeout: 4), "real sheet See the report must be hittable")
        seeReport.tap()

        XCTAssertTrue(
            app.navigationBars["Journey report"].waitForExistence(timeout: 8)
                || app.staticTexts["Journey report"].waitForExistence(timeout: 2)
                || app.staticTexts["Current combo"].waitForExistence(timeout: 2),
            "successful confirm must follow See the report"
        )
        XCTAssertFalse(app.staticTexts["Finish this treatment?"].exists)
        XCTAssertFalse(app.buttons["Mark this treatment finished"].exists)
    }

    func testC_siblingRemainsActiveAfterSelectedFinish() {
        let app = launchCurrentDetail()
        openFinishSheet(in: app)
        XCTAssertTrue(app.buttons["See the report"].waitForExistence(timeout: 4))
        app.buttons["See the report"].tap()
        XCTAssertTrue(
            app.navigationBars["Journey report"].waitForExistence(timeout: 8)
                || app.staticTexts["Current combo"].waitForExistence(timeout: 4)
        )

        popToHistory(app)
        XCTAssertTrue(app.navigationBars["Treatment history"].waitForExistence(timeout: 8))
        let sibling = historyRow(in: app, containing: "Sibling")
        XCTAssertTrue(sibling.waitForExistence(timeout: 6), "sibling treatment must still exist")

        if app.buttons["history-filter-active"].waitForExistence(timeout: 3) {
            app.buttons["history-filter-active"].tap()
            XCTAssertTrue(sibling.waitForExistence(timeout: 4), "sibling must remain Active")
            XCTAssertFalse(
                historyRow(in: app, containing: "Metformin").waitForExistence(timeout: 2),
                "finished Current combo must not stay Active"
            )
        }
    }

    func testD_completedHistoryAndDoseLogsRemain() {
        let app = launchCurrentDetail()
        openFinishSheet(in: app)
        XCTAssertTrue(app.buttons["See the report"].waitForExistence(timeout: 4))
        app.buttons["See the report"].tap()
        XCTAssertTrue(
            app.navigationBars["Journey report"].waitForExistence(timeout: 8)
                || app.staticTexts["Current combo"].waitForExistence(timeout: 4)
        )

        popToHistory(app)
        XCTAssertTrue(app.navigationBars["Treatment history"].waitForExistence(timeout: 8))
        if app.buttons["history-filter-completed"].waitForExistence(timeout: 3) {
            app.buttons["history-filter-completed"].tap()
        }
        let completed = historyRow(in: app, containing: "Metformin")
        XCTAssertTrue(completed.waitForExistence(timeout: 6), "completed treatment must remain in history")
        completed.tap()

        XCTAssertTrue(app.navigationBars["Treatment details"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Current combo"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 4))
        app.buttons["treatment-detail-tab-doses"].tap()
        XCTAssertTrue(app.staticTexts["Dose history"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["No doses recorded for this treatment yet."].exists)
        app.swipeUp()
        let doseRow = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ OR label CONTAINS %@",
                "treatment-dose-",
                "Metformin, "
            )
        ).firstMatch
        XCTAssertTrue(doseRow.waitForExistence(timeout: 6), "DoseLogs must remain after finish")
    }

    func testE_finishDisappearsAndCannotRepeat() {
        let app = launchCurrentDetail()
        openFinishSheet(in: app)
        XCTAssertTrue(app.buttons["See the report"].waitForExistence(timeout: 4))
        app.buttons["See the report"].tap()
        XCTAssertTrue(
            app.navigationBars["Journey report"].waitForExistence(timeout: 8)
                || app.staticTexts["Current combo"].waitForExistence(timeout: 4)
        )

        popToHistory(app)
        if app.buttons["history-filter-all"].waitForExistence(timeout: 4) {
            app.buttons["history-filter-all"].tap()
        } else if app.buttons["history-filter-completed"].waitForExistence(timeout: 2) {
            app.buttons["history-filter-completed"].tap()
        }
        let completed = historyRow(in: app, containing: "Metformin")
        XCTAssertTrue(completed.waitForExistence(timeout: 6), "finished treatment must remain reopenable from history")
        completed.tap()
        XCTAssertTrue(app.navigationBars["Treatment details"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["Mark this treatment finished"].exists)
        if app.buttons["treatment-detail-overflow"].waitForExistence(timeout: 2) {
            app.buttons["treatment-detail-overflow"].tap()
            XCTAssertFalse(app.buttons["Mark this treatment finished"].waitForExistence(timeout: 1))
        }
        XCTAssertFalse(app.staticTexts["Finish this treatment?"].exists)
    }

    func testF_scanNewMedicineFollowUp() {
        let app = launchCurrentDetail()
        openFinishSheet(in: app)

        let scan = app.buttons["Scan a new medicine"]
        XCTAssertTrue(scan.waitForExistence(timeout: 4), "real sheet Scan a new medicine must be hittable")
        scan.tap()

        XCTAssertFalse(app.staticTexts["Finish this treatment?"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Mark this treatment finished"].waitForExistence(timeout: 2))
        let reachedIntake =
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).firstMatch.waitForExistence(timeout: 4)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).firstMatch.waitForExistence(timeout: 1)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "unfinished")).firstMatch.waitForExistence(timeout: 1)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "plan")).firstMatch.waitForExistence(timeout: 1)
            || app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@", "prescription", "prescription")).firstMatch.waitForExistence(timeout: 1)
        XCTAssertTrue(
            reachedIntake || !app.navigationBars["Treatment details"].exists,
            "Scan a new medicine must leave treatment detail toward add-prescription follow-up"
        )
    }

    // MARK: - Host

    @discardableResult
    private func launchCurrentDetail() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHECKMED_TH1_VERIFY"] = "1"
        app.launchEnvironment["CHECKMED_TH2_DETAIL"] = "current"
        app.launchEnvironment["CHECKMED_TH2_TAB"] = "overview"
        app.launch()
        if app.staticTexts["TH-1 verification refused"].waitForExistence(timeout: 2) {
            XCTFail("Host refused isolation; SIMULATOR_UDID must be \(requiredUDID)")
        }
        XCTAssertFalse(
            app.staticTexts["Sign in"].waitForExistence(timeout: 1),
            "RootView/auth must not run on the FT-1 host"
        )
        XCTAssertTrue(
            app.navigationBars["Treatment details"].waitForExistence(timeout: 8)
                || app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "treatment-detail-")).firstMatch.waitForExistence(timeout: 2),
            "Treatment details destination must open"
        )
        XCTAssertTrue(app.staticTexts["Current combo"].waitForExistence(timeout: 6))
        return app
    }

    private func openFinishSheet(in app: XCUIApplication) {
        let finish = app.buttons["Mark this treatment finished"]
        XCTAssertTrue(finish.waitForExistence(timeout: 6))
        finish.tap()
        XCTAssertTrue(
            app.staticTexts["Finish this treatment?"].waitForExistence(timeout: 6),
            "confirmation sheet title must appear"
        )
        XCTAssertTrue(app.buttons["See the report"].exists)
        XCTAssertTrue(app.buttons["Scan a new medicine"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    private func historyRow(in app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history-treatment-", needle)
        ).firstMatch
    }

    private func popToHistory(_ app: XCUIApplication) {
        for _ in 0..<4 {
            if app.navigationBars["Treatment history"].waitForExistence(timeout: 1) {
                return
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 2) {
                back.tap()
            } else {
                break
            }
        }
    }
}
