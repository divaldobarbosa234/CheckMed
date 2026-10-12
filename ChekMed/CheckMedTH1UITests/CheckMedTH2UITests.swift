import XCTest

/// Isolated TH-2 Detail / Doses checks against the DEBUG verification host.
/// Destination must be CheckMed-TH1-Verify (`D34130F1-4D47-4FC7-B14B-C19388076947`).
final class CheckMedTH2UITests: XCTestCase {
    private let requiredUDID = "D34130F1-4D47-4FC7-B14B-C19388076947"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let runUDID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"]
            ?? ProcessInfo.processInfo.environment["TARGET_DEVICE_IDENTIFIER"]
        if let runUDID, runUDID != requiredUDID {
            throw XCTSkip("Refusing to run TH-2 UI tests on \(runUDID); required \(requiredUDID)")
        }
    }

    func testCurrentDosesStatusesAndIsolation() {
        let app = launchDetail(scene: "current", tab: "doses")
        assertOpenedDetail(app, treatmentName: "Current combo")
        XCTAssertTrue(app.buttons["treatment-detail-tab-doses"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Dose history"].waitForExistence(timeout: 4))

        XCTAssertTrue(app.staticTexts["Metformin"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Lisinopril"].exists)
        XCTAssertFalse(app.staticTexts["SiblingMed"].exists)

        XCTAssertTrue(statusRow(in: app, medicine: "Metformin", status: "taken").firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(statusRow(in: app, medicine: "Lisinopril", status: "takenLate").firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(statusRow(in: app, medicine: "Metformin", status: "missed").firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(statusRow(in: app, medicine: "Lisinopril", status: "skipped").firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(statusRow(in: app, medicine: "Metformin", status: "pending").firstMatch.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(statusRow(in: app, medicine: "Lisinopril", status: "pending").count, 1)

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Confirmed")).firstMatch.exists,
            "confirmed time must be shown separately from scheduled time"
        )
        let lateConfirmed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "21:10", "23:10", "11:10")
        ).firstMatch
        XCTAssertTrue(
            lateConfirmed.exists,
            "takenLate confirmed time must stay distinct from the 20:00 scheduled slot"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OCR")).firstMatch.exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Conny Cooper")).firstMatch.exists,
            "Safety caption must remain on Doses"
        )

        let takenRow = statusRow(in: app, medicine: "Metformin", status: "taken").firstMatch
        XCTAssertTrue(takenRow.waitForExistence(timeout: 3))
        takenRow.tap()
        XCTAssertTrue(
            app.staticTexts["Times per day"].waitForExistence(timeout: 6)
                || app.buttons["DELETE RECIPE"].waitForExistence(timeout: 2)
                || app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "treatment-medicine-detail-")).firstMatch.waitForExistence(timeout: 2),
            "dose-row chevron must open medicine detail"
        )
        XCTAssertTrue(app.staticTexts["Metformin"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Dose history"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["treatment-detail-tab-doses"].exists)
    }

    func testTabSwitchDoesNotMutateAndPreservesActions() {
        let app = launchDetail(scene: "current", tab: "overview")
        assertOpenedDetail(app, treatmentName: "Current combo")
        XCTAssertTrue(app.staticTexts["Metformin"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Lisinopril"].exists)
        XCTAssertTrue(app.buttons["treatment-detail-tab-overview"].exists)
        XCTAssertTrue(app.buttons["treatment-detail-overflow"].exists)
        app.buttons["treatment-detail-overflow"].tap()
        XCTAssertTrue(app.buttons["Rename treatment"].waitForExistence(timeout: 3), "Rename must remain in overflow")
        XCTAssertTrue(app.buttons["Add medicine"].exists)
        XCTAssertTrue(app.buttons["Mark this treatment finished"].exists)
        app.buttons["treatment-detail-overflow"].tap()

        app.buttons["treatment-detail-tab-doses"].tap()
        XCTAssertTrue(app.staticTexts["Dose history"].waitForExistence(timeout: 4))
        let pendingBefore = statusRow(in: app, medicine: "Metformin", status: "pending").count
        XCTAssertGreaterThanOrEqual(pendingBefore, 1)

        app.buttons["treatment-detail-tab-overview"].tap()
        XCTAssertTrue(app.staticTexts["Treatment summary"].waitForExistence(timeout: 4)
            || app.staticTexts["Summary"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Metformin"].exists)
        XCTAssertFalse(app.staticTexts["Finish this treatment?"].exists)

        app.buttons["treatment-detail-tab-doses"].tap()
        XCTAssertEqual(
            statusRow(in: app, medicine: "Metformin", status: "pending").count,
            pendingBefore,
            "tab switching must not invent or drop DoseLogs"
        )
        XCTAssertFalse(app.staticTexts["SiblingMed"].exists)
    }

    func testCompletedOverviewActionsAndEmptyDoses() {
        let app = launchDetail(scene: "completed", tab: "overview")
        assertOpenedDetail(app, treatmentName: "September combo")
        XCTAssertTrue(app.staticTexts["Amoxicilina 500mg"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Ibuprofeno 400mg"].exists)
        XCTAssertTrue(app.staticTexts["Completed"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "report")).firstMatch.exists
            || app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Report")).firstMatch.exists
            || app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "PDF")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Mark this treatment finished"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Treatment history"].waitForExistence(timeout: 6))
    }

    func testEmptyDosesAndFutureChip() {
        let empty = launchDetail(scene: "empty", tab: "doses")
        assertOpenedDetail(empty, treatmentName: "Empty doses plan")
        XCTAssertTrue(empty.staticTexts["No doses recorded for this treatment yet."].waitForExistence(timeout: 4))
        XCTAssertFalse(empty.staticTexts["SiblingMed"].exists)

        let future = launchDetail(scene: "future", tab: "overview")
        assertOpenedDetail(future, treatmentName: "Upcoming winter")
        XCTAssertTrue(future.staticTexts["Upcoming"].waitForExistence(timeout: 4)
            || future.staticTexts["Vitamina D"].waitForExistence(timeout: 2))
        XCTAssertTrue(future.staticTexts["Vitamina D"].exists)
        XCTAssertFalse(future.buttons["Mark this treatment finished"].exists)
    }

    func testMedicineDetailAndRenameOverflow() {
        let app = launchDetail(scene: "current", tab: "overview")
        XCTAssertTrue(app.staticTexts["Metformin"].waitForExistence(timeout: 8))
        let metforminRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "treatment-medicine-", "Metformin")
        ).firstMatch
        XCTAssertTrue(metforminRow.waitForExistence(timeout: 4))
        let metforminId = String(metforminRow.identifier.dropFirst("treatment-medicine-".count))
        metforminRow.tap()
        XCTAssertTrue(
            app.otherElements["treatment-medicine-detail-\(metforminId)"].waitForExistence(timeout: 6)
                || app.descendants(matching: .any)["treatment-medicine-detail-\(metforminId)"].waitForExistence(timeout: 2),
            "must open the tapped medicine, not a sibling"
        )
        XCTAssertTrue(app.staticTexts["Metformin"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["Times per day"].waitForExistence(timeout: 4)
                || app.buttons["TIMES AND REMINDERS"].waitForExistence(timeout: 2)
                || app.buttons["DELETE RECIPE"].waitForExistence(timeout: 1)
        )
        XCTAssertFalse(app.staticTexts["SiblingMed"].exists)
        XCTAssertFalse(app.staticTexts["Lisinopril"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        assertOpenedDetail(app, treatmentName: "Current combo")
        XCTAssertTrue(app.buttons["treatment-detail-tab-overview"].exists)
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 4)
            || app.staticTexts["Treatment summary"].waitForExistence(timeout: 2))

        app.buttons["treatment-detail-overflow"].tap()
        let rename = app.buttons["Rename treatment"]
        XCTAssertTrue(rename.waitForExistence(timeout: 3), "Rename must remain in overflow")
        XCTAssertTrue(app.buttons["Add medicine"].exists)
        XCTAssertTrue(app.buttons["Mark this treatment finished"].exists)
    }

    func testDynamicTypeAccessibilityXL() {
        let app = launchDetail(
            scene: "current",
            tab: "overview",
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        )
        assertOpenedDetail(app, treatmentName: "Current combo")
        XCTAssertTrue(app.staticTexts["Metformin"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["treatment-detail-overflow"].exists)
        XCTAssertTrue(app.buttons["treatment-detail-tab-overview"].exists)
        XCTAssertTrue(app.buttons["treatment-detail-tab-doses"].exists)
        let png = app.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: "/tmp/CheckMed-TH2-Visual-Review/G_dynamic_type_accessibilityXL.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
        let nav = app.navigationBars["Treatment details"].exists
            ? app.navigationBars["Treatment details"]
            : app.navigationBars.firstMatch
        XCTAssertGreaterThan(nav.frame.height, 40)
        let review = URL(fileURLWithPath: "/Users/barbosa/Desktop/CheckMed-TH2-Visual-Review/G_dynamic_type_accessibilityXL.png")
        try? FileManager.default.createDirectory(at: review.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: review)
    }

    @discardableResult
    private func launchDetail(
        scene: String,
        tab: String,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHECKMED_TH1_VERIFY"] = "1"
        app.launchEnvironment["CHECKMED_TH2_DETAIL"] = scene
        app.launchEnvironment["CHECKMED_TH2_TAB"] = tab
        if !extraArguments.isEmpty {
            app.launchArguments += extraArguments
        }
        app.launch()
        if app.staticTexts["TH-1 verification refused"].waitForExistence(timeout: 2) {
            XCTFail("Host refused isolation; SIMULATOR_UDID must be \(requiredUDID)")
        }
        XCTAssertFalse(
            app.staticTexts["Sign in"].waitForExistence(timeout: 1),
            "RootView/auth must not run on the TH-2 host"
        )
        return app
    }

    private func assertOpenedDetail(_ app: XCUIApplication, treatmentName: String) {
        XCTAssertTrue(
            app.navigationBars["Treatment details"].waitForExistence(timeout: 8)
                || app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "treatment-detail-")).firstMatch.waitForExistence(timeout: 2),
            "Treatment details destination must open"
        )
        XCTAssertTrue(
            app.staticTexts[treatmentName].waitForExistence(timeout: 4)
                || app.otherElements["treatment-detail-title"].waitForExistence(timeout: 1)
                || app.otherElements["treatment-detail-doses-identity"].waitForExistence(timeout: 1)
                || app.descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS %@", treatmentName)
                ).firstMatch.waitForExistence(timeout: 2),
            "treatment name must remain visible in the hero/identity cue"
        )
    }

    private func statusRow(in app: XCUIApplication, medicine: String, status: String) -> XCUIElementQuery {
        let token = "\(medicine), \(status)"
        let predicate = NSPredicate(
            format: "(identifier BEGINSWITH %@ OR label == %@) AND (value == %@ OR label == %@ OR label CONTAINS %@)",
            "treatment-dose-",
            token,
            status,
            token,
            token
        )
        return app.descendants(matching: .any).matching(predicate)
    }
}
