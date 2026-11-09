import XCTest

/// Drives the real app against the real map, search and routing services: find a place, tap a
/// route onto the map, drag its end, save it and find it back in the list. Screenshots of each
/// step are attached to the test result.
final class PlanningFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFindPlanSaveAndListARoute() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["TIK OP DE KAART"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 6)
        attachScreenshot(of: app, named: "1-start")

        // The map settings sheet.
        app.buttons["layersButton"].tap()
        XCTAssertTrue(element(in: app, labelled: "TOPOGRAFISCH").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        attachScreenshot(of: app, named: "2-kaart-en-tempo")
        app.buttons["Klaar"].tap()

        // Find a mountain hut and jump to it.
        app.buttons["searchButton"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Refuge du Lac Blanc")
        let firstResult = app.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 30), "the search returned no places")
        attachScreenshot(of: app, named: "3-zoeken")
        firstResult.tap()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 5)

        // Three taps on the map make a route with a numbered point in the middle. They are a
        // second apart so they are not taken for a double tap.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.50)).tap()
        XCTAssertTrue(app.staticTexts["Tik op de kaart voor het volgende punt."].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.47)).tap()
        Thread.sleep(forTimeInterval: 1)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.42)).tap()

        let saveButton = app.buttons["saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        waitForRoute(in: app)
        let distance = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Afstand")).firstMatch
        XCTAssertTrue(distance.exists)
        let distanceBeforeDrag = distance.label
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(of: app, named: "4-route")

        // Pick up the end marker and move it: the route is computed again.
        let endMarker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Eindpunt")).firstMatch
        XCTAssertTrue(endMarker.waitForExistence(timeout: 5), "the end marker is not exposed to accessibility")
        endMarker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1.2,
            thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.33))
        )
        Thread.sleep(forTimeInterval: 1)
        waitForRoute(in: app)
        XCTAssertNotEqual(distance.label, distanceBeforeDrag, "dragging the end marker did not change the route")
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(of: app, named: "5-versleept")

        // Save it under the suggested name.
        saveButton.tap()
        let confirm = app.buttons["confirmSaveButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 40))
        XCTAssertTrue(app.textFields["saveNameField"].exists)
        attachScreenshot(of: app, named: "6-bewaren")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10))

        // It is in the list of saved routes.
        app.buttons["routesButton"].tap()
        XCTAssertTrue(element(in: app, labelled: "MIJN ROUTES").waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "7-mijn-routes")
    }

    /// The route is ready once it can be saved. A tap that landed far from any path is answered
    /// with the offer to draw a straight line; accept it.
    @MainActor
    private func waitForRoute(in app: XCUIApplication) {
        let saveButton = app.buttons["saveButton"]
        let straightLine = app.buttons["straightLineFallbackButton"]
        let deadline = Date().addingTimeInterval(60)
        while !saveButton.isEnabled, Date() < deadline {
            if straightLine.exists {
                straightLine.tap()
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(saveButton.isEnabled, "the route was not computed in time")
    }

    /// Any element whose label contains the text, whatever kind of element SwiftUI made of it.
    @MainActor
    private func element(in app: XCUIApplication, labelled text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
