import XCTest

@MainActor final class SmokeTests: XCTestCase {
    func testOfflineMarketOrderUsesLocalEngine() throws {
        let app=XCUIApplication();app.launchArguments=["--uitest"];app.launch()
        let start=app.buttons["startTrading"]
        if !app.tabBars.buttons["交易"].waitForExistence(timeout:3){for _ in 0..<5 where !start.isHittable{app.swipeUp()};XCTAssertTrue(start.isHittable);start.tap()}
        XCTAssertTrue(app.tabBars.buttons["交易"].waitForExistence(timeout:30))
        app.tabBars.buttons["交易"].tap()
        XCTAssertTrue(app.buttons["openOrder"].waitForExistence(timeout:10))
        for _ in 0..<5 where !app.buttons["openOrder"].isHittable{app.swipeUp()}
        app.buttons["openOrder"].tap()
        app.buttons["orderKind"].tap()
        app.buttons["市價"].tap()
        let submit=app.buttons["submitOrder"]
        for _ in 0..<5 where !submit.isHittable{app.swipeUp()}
        XCTAssertTrue(submit.isHittable);submit.tap()
        app.buttons["確認送出"].tap()
        XCTAssertTrue(app.tabBars.buttons["資產"].waitForExistence(timeout:15))
        app.tabBars.buttons["資產"].tap()
        XCTAssertTrue(app.staticTexts["SIM:TAIWANSTOCK01"].waitForExistence(timeout:10))
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="Offline local fill and position";shot.lifetime = .keepAlways;add(shot)
    }
    func testOfflineOnboardingAndNavigation() throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitest"]
        app.launch()
        let launchShot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());launchShot.name="Launch screen evidence";launchShot.lifetime = .keepAlways;add(launchShot)
        print("APP_LAUNCH_STATE",app.state.rawValue)
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:15),"App terminated during startup")
        guard app.state == .runningForeground else{return}
        let start=app.buttons["startTrading"]
        if !app.tabBars.buttons["行情"].waitForExistence(timeout:3){for _ in 0..<5 where !start.isHittable{app.swipeUp()};XCTAssertTrue(start.isHittable);start.tap()}
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
