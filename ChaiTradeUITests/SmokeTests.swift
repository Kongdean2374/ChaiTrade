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
        let performance=app.buttons["績效與資金流分析"]
        for _ in 0..<5 where !performance.isHittable{app.swipeUp()}
        performance.tap()
        XCTAssertTrue(app.buttons["匯出本期績效 JSON"].waitForExistence(timeout:15))
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout:30))
    }
    func testPendingSwitchRequiresColdLaunchAndPreservesOfflinePosition() throws {
        let app=XCUIApplication();app.launchArguments=["--uitest"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout:30))
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        app.buttons["設定"].tap()
        app.buttons["A 真實行情・模擬交易"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["activeModeBanner"].waitForExistence(timeout:30))
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"A 真實行情・模擬交易")
        app.buttons["設定"].tap();app.buttons["B 離線市場・模擬交易"].tap();app.buttons["完成"].tap()
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["activeModeBanner"].waitForExistence(timeout:30))
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        app.tabBars.buttons["資產"].tap()
        XCTAssertTrue(app.staticTexts["SIM:TAIWANSTOCK01"].waitForExistence(timeout:10))
    }

    func testChartScreenshotCanBeAttachedToLocalJournal()throws{
        let app=XCUIApplication();app.launchArguments=["--uitest"];app.launch()
        let start=app.buttons["startTrading"]
        if !app.tabBars.buttons["交易"].waitForExistence(timeout:3){for _ in 0..<5 where !start.isHittable{app.swipeUp()};XCTAssertTrue(start.isHittable);start.tap()}
        XCTAssertTrue(app.tabBars.buttons["交易"].waitForExistence(timeout:30));app.tabBars.buttons["交易"].tap()
        let capture=app.buttons["截圖"]
        for _ in 0..<5 where !capture.isHittable{app.swipeUp()}
        XCTAssertTrue(capture.isHittable);capture.tap()
        let captured=app.buttons.containing(NSPredicate(format:"label BEGINSWITH %@","已保存本機圖表草稿")).firstMatch
        XCTAssertTrue(captured.waitForExistence(timeout:10));captured.tap()
        app.tabBars.buttons["資產"].tap()
        let journal=app.buttons["本機交易日誌"]
        for _ in 0..<5 where !journal.isHittable{app.swipeUp()}
        XCTAssertTrue(journal.isHittable);journal.tap()
        let attachment=app.switches["attachJournalChart"]
        XCTAssertTrue(attachment.waitForExistence(timeout:10))
        if attachment.value as? String != "1"{attachment.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.5)).tap()}
        XCTAssertEqual(attachment.value as? String,"1")
        XCTAssertTrue(app.images["journalChartPreview"].waitForExistence(timeout:5))
        let text=app.textViews["journalText"];text.tap();text.typeText("Synthetic UI chart journal")
        let save=app.buttons["保存日誌"]
        for _ in 0..<5 where !save.isHittable{app.swipeUp()}
        XCTAssertTrue(save.isHittable);save.tap()
        let exportImage=app.buttons["匯出這張模擬圖表"]
        for _ in 0..<6 where !exportImage.isHittable{app.swipeUp()}
        XCTAssertTrue(exportImage.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.alerts["操作未完成"].exists)
        XCTAssertTrue(app.images["savedJournalChart"].exists)
        app.buttons["完成"].tap()
    }

}
