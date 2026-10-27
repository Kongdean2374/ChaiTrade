import XCTest

@MainActor final class SmokeTests: XCTestCase {
    func testOfflineOnboardingAndNavigation() throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitest"]
        app.launch()
        let start=app.buttons["startTrading"]
        if start.waitForExistence(timeout:5) { start.tap() }
        XCTAssertTrue(app.tabBars.buttons["行情"].waitForExistence(timeout:30))
        app.tabBars.buttons["行情"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout:5))
        app.tabBars.buttons["委託"].tap()
        XCTAssertTrue(app.staticTexts["最近成交（模擬）"].waitForExistence(timeout:5))
        app.tabBars.buttons["資產"].tap()
        XCTAssertTrue(app.buttons["調整虛擬資金／換匯"].waitForExistence(timeout:5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout:30))
    }
}
