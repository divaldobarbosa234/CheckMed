import XCTest

/// Isolated TH-1 History interactions against the DEBUG verification host.
/// Destination must be CheckMed-TH1-Verify (`D34130F1-4D47-4FC7-B14B-C19388076947`).
final class CheckMedTH1UITests: XCTestCase {
    private let requiredUDID = "D34130F1-4D47-4FC7-B14B-C19388076947"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let runUDID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"]
            ?? ProcessInfo.processInfo.environment["TARGET_DEVICE_IDENTIFIER"]
        if let runUDID, runUDID != requiredUDID {
            throw XCTSkip("Refusing to run TH-1 UI tests on \(runUDID); required \(requiredUDID)")
        }
    }

    func testA_searchCaseAccentAndNoResults() {
        let app = launchHost(empty: false)
        let search = app.searchFields["history-search"].firstMatch
        let searchField = search.exists ? search : app.textFields["history-search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "history-search must be discoverable")

        searchField.tap()
        searchField.typeText("METFORMIN")
        XCTAssertTrue(row(in: app, containing: "Metformin").waitForExistence(timeout: 4))
        XCTAssertFalse(row(in: app, containing: "Vitamina D").exists)

        clearSearch(searchField)
        searchField.tap()
        searchField.typeText("paracetamol")
        XCTAssertTrue(row(in: app, containing: "Paracétamol").waitForExistence(timeout: 4))
        XCTAssertFalse(row(in: app, containing: "Metformin").exists)

        clearSearch(searchField)
        searchField.tap()
        searchField.typeText("zzzz-no-such-medicine")
        XCTAssertTrue(app.otherElements["history-no-results"].waitForExistence(timeout: 4)
            || app.staticTexts["history-no-results"].waitForExistence(timeout: 1)
            || app.staticTexts["No treatments match this search."].waitForExistence(timeout: 2))

        clearSearch(searchField)
        XCTAssertTrue(row(in: app, containing: "Metformin").waitForExistence(timeout: 4))
        XCTAssertTrue(row(in: app, containing: "Vitamina D").exists)
    }

    func testB_filtersAllActiveCompleted() {
        let app = launchHost(empty: false)
        XCTAssertTrue(app.buttons["history-filter-all"].waitForExistence(timeout: 8))

        app.buttons["history-filter-all"].tap()
        XCTAssertTrue(row(in: app, containing: "Metformin").waitForExistence(timeout: 4))
        XCTAssertTrue(row(in: app, containing: "Vitamina D").exists)
        XCTAssertTrue(row(in: app, containing: "Amoxicilina 500mg").exists)
        let allCount = treatmentRowCount(in: app)

        app.buttons["history-filter-active"].tap()
        XCTAssertTrue(row(in: app, containing: "Metformin").waitForExistence(timeout: 4))
        XCTAssertFalse(row(in: app, containing: "Vitamina D").exists, "Upcoming must not appear under Active")
        XCTAssertFalse(row(in: app, containing: "Amoxicilina 500mg").exists)
        XCTAssertEqual(treatmentRowCount(in: app), 1)

        app.buttons["history-filter-completed"].tap()
        XCTAssertTrue(row(in: app, containing: "Amoxicilina 500mg").waitForExistence(timeout: 4))
        XCTAssertFalse(row(in: app, containing: "Metformin").exists)
        XCTAssertFalse(row(in: app, containing: "Vitamina D").exists)

        app.buttons["history-filter-all"].tap()
        XCTAssertTrue(row(in: app, containing: "Metformin").waitForExistence(timeout: 4))
        XCTAssertTrue(row(in: app, containing: "Vitamina D").exists)
        XCTAssertEqual(treatmentRowCount(in: app), allCount)
    }

    func testC_yearArchiveExpandCollapseAndRecentDedup() {
        let app = launchHost(empty: false)
        XCTAssertTrue(row(in: app, containing: "Paracétamol").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["history-year-2026"].exists, "newest year should be on screen expanded")
        XCTAssertFalse(row(in: app, containing: "Omeprazol").exists)
        XCTAssertFalse(row(in: app, containing: "Losartan").exists)

        let year2025 = app.buttons["history-year-2025"]
        reveal(year2025, in: app)
        XCTAssertTrue(year2025.exists)
        XCTAssertFalse(winterAmoxicilina(in: app).exists)

        year2025.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(
            winterAmoxicilina(in: app).waitForExistence(timeout: 4),
            "expanded 2025 should show the December–January treatment"
        )

        reveal(year2025, in: app)
        year2025.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertFalse(winterAmoxicilina(in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(row(in: app, containing: "Amoxicilina 500mg").waitForExistence(timeout: 4))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Amoxicilina 500mg")).count,
            1,
            "recent row must not duplicate inside a year group"
        )
        XCTAssertTrue(row(in: app, containing: "Metformin").exists)
        XCTAssertTrue(row(in: app, containing: "Paracétamol").exists)
    }

    func testD_rowOpensTreatmentDetailAndBack() {
        let app = launchHost(empty: false)
        let current = row(in: app, containing: "Metformin")
        XCTAssertTrue(current.waitForExistence(timeout: 8))
        current.tap()
        let detail = app.navigationBars["Current combo"]
        XCTAssertTrue(detail.waitForExistence(timeout: 6), "TreatmentDetailScreen title is the treatment record title")
        XCTAssertTrue(app.staticTexts["Metformin"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Lisinopril"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Treatment history"].waitForExistence(timeout: 6))
        XCTAssertTrue(row(in: app, containing: "Metformin").waitForExistence(timeout: 4))
        XCTAssertTrue(row(in: app, containing: "Vitamina D").exists)
    }

    func testE_emptyHistory() {
        let app = launchHost(empty: true)
        XCTAssertTrue(app.navigationBars["Treatment history"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.otherElements["history-empty"].waitForExistence(timeout: 6)
                || app.staticTexts["history-empty"].waitForExistence(timeout: 1)
                || app.staticTexts["No treatments yet"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.buttons["history-filter-all"].exists)
        XCTAssertFalse(row(in: app, containing: "Metformin").exists)
    }

    func testF_controlsAreDiscoverable() {
        let app = launchHost(empty: false)
        XCTAssertTrue(app.textFields["history-search"].waitForExistence(timeout: 8)
            || app.searchFields["history-search"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["history-filter-all"].exists)
        XCTAssertTrue(app.buttons["history-filter-active"].exists)
        XCTAssertTrue(app.buttons["history-filter-completed"].exists)
        XCTAssertTrue(app.buttons["history-year-2026"].exists)
        let yearLabel = app.buttons["history-year-2026"].label
        XCTAssertTrue(yearLabel.contains("2026"), "year header a11y should include the calendar year: \(yearLabel)")
        XCTAssertFalse(yearLabel.contains("2,026"), "year must not be spoken as a grouped quantity: \(yearLabel)")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-treatment-"))
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        let first = rows.element(boundBy: 0)
        XCTAssertFalse((first.label as String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(app.staticTexts["TH-1 verification refused"].exists)
    }

    // MARK: - Host

    @discardableResult
    private func launchHost(empty: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHECKMED_TH1_VERIFY"] = "1"
        if empty {
            app.launchEnvironment["CHECKMED_TH1_EMPTY"] = "1"
        }
        app.launch()

        if app.staticTexts["TH-1 verification refused"].waitForExistence(timeout: 2) {
            XCTFail("Host refused isolation; SIMULATOR_UDID must be \(requiredUDID)")
        }
        XCTAssertFalse(
            app.staticTexts["Sign in"].waitForExistence(timeout: 1),
            "RootView/auth must not run on the TH-1 host"
        )
        XCTAssertTrue(
            app.navigationBars["Treatment history"].waitForExistence(timeout: 10),
            "Verification host must present TreatmentHistoryScreen"
        )
        if !empty {
            XCTAssertTrue(
                row(in: app, containing: "Metformin").waitForExistence(timeout: 10),
                "Synthetic fixtures must finish seeding before interactions"
            )
        }
        return app
    }

    private func row(in app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history-treatment-", needle)).firstMatch
    }

    private func winterAmoxicilina(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND NOT label CONTAINS %@",
                "history-treatment-",
                "2025",
                "500mg"
            )
        ).firstMatch
    }

    private func treatmentRowCount(in app: XCUIApplication) -> Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-treatment-")).count
    }

    private func clearSearch(_ field: XCUIElement) {
        field.tap()
        if let value = field.value as? String, !value.isEmpty {
            let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            field.typeText(delete)
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Could not reveal \(element.identifier)")
        XCTAssertTrue(element.isHittable, "\(element.identifier) exists but is not hittable")
    }
}
