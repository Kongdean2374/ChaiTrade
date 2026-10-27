import XCTest

@MainActor final class SmokeTests: XCTestCase {
    func testOfflineOnboardingAndNavigation() throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitest"]
        app.launch()
        let launchShot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());launchShot.name="Launch screen evidence";launchShot.lifetime = .keepAlways;add(launchShot)
        print("APP_LAUNCH_STATE",app.state.rawValue)
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:15),"App terminated during startup")
        guard app.state == .runningForeground else{return}
        let start=app.buttons["startTrading"]
        if start.waitForExistence(timeout:5) { start.tap() }
        XCTAssertTrue(app.tabBars.buttons["行情"].waitForExistence(timeout:30),app.debugDescription)
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
