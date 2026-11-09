import XCTest

/// Drives the real app against the real map, search and routing services: find a place, tap a
/// route onto the map, save it and find it back in the list. Screenshots of each step are
/// attached to the test result.
final class PlanningFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFindPlanSaveAndListARoute() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Tik op de kaart om te beginnen"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 6)
        attachScreenshot(of: app, named: "1-start")

        // Find a mountain hut and jump to it.
        app.buttons["searchButton"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Refuge du Lac Blanc")
        let firstResult = app.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 30), "the search returned no places")
        attachScreenshot(of: app, named: "2-zoeken")
        firstResult.tap()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 5)
        attachScreenshot(of: app, named: "3-gevonden")

        // Two taps on the map make a route. They are a second apart so they are not a double tap.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.50)).tap()
        XCTAssertTrue(app.staticTexts["Tik op de kaart voor het volgende punt."].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.42)).tap()

        // The route is ready once it can be saved. A tap that landed far from any path is
        // answered with the offer to draw a straight line; accept it.
        let saveButton = app.buttons["saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        let straightLine = app.buttons["straightLineFallbackButton"]
        let deadline = Date().addingTimeInterval(60)
        while !saveButton.isEnabled, Date() < deadline {
            if straightLine.exists {
                straightLine.tap()
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(saveButton.isEnabled, "the route was not computed in time")
        let distance = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Afstand")).firstMatch
        XCTAssertTrue(distance.exists)
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(of: app, named: "4-route")

        // Save it under the suggested name.
        saveButton.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 40))
        attachScreenshot(of: app, named: "5-bewaren")
        alert.buttons["Opslaan"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10))

        // It is in the list of saved routes.
        app.buttons["routesButton"].tap()
        XCTAssertTrue(app.navigationBars["Mijn routes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "6-mijn-routes")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
