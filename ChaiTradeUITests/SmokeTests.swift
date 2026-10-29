import XCTest

@MainActor final class SmokeTests: IsolatedUITestCase {
    private func startFreshOffline(_ app:XCUIApplication)throws{
        // launchClean always owns a new empty directory. Assert its onboarding
        // directly instead of waiting for a tab known not to exist yet.
        let start=app.buttons["startTrading"]
        try check(start.waitForExistence(timeout:15),"Fresh account did not show onboarding")
        for _ in 0..<5 where !start.isHittable{app.swipeUp()}
        try check(start.isHittable,"Fresh onboarding start is unreachable");start.tap()
        try check(app.tabBars.buttons["交易"].waitForExistence(timeout:30),"Fresh offline account did not open")
    }
    func testOfflineMarketOrderUsesLocalEngine() throws {
        let app=launchClean();defer{finish()}
        try startFreshOffline(app)
        app.tabBars.buttons["交易"].tap()
        let regularBoard=app.buttons["整股（張）"];try reveal(regularBoard,in:app);regularBoard.tap()
        try waitUntil("Whole-lot selection did not take effect before opening an order",timeout:5){regularBoard.isSelected}
        XCTAssertTrue(app.buttons["openOrder"].waitForExistence(timeout:10))
        for _ in 0..<5 where !app.buttons["openOrder"].isHittable{app.swipeUp()}
        app.buttons["openOrder"].tap()
        let kind=app.buttons["orderKind"];try reveal(kind,in:app);kind.tap()
        try check(app.buttons["市價"].waitForExistence(timeout:5),"Whole-lot order menu did not expose market orders");app.buttons["市價"].tap()
        let submit=app.buttons["submitOrder"]
        for _ in 0..<5 where !submit.isHittable{app.swipeUp()}
        XCTAssertTrue(submit.isHittable);submit.tap()
        app.buttons["確認送出"].tap()
        XCTAssertTrue(app.tabBars.buttons["資產"].waitForExistence(timeout:15))
        app.tabBars.buttons["資產"].tap()
        XCTAssertEqual((try state(app)["positions"] as? [String:String])?["SIM:TWSE:2330"],"1000")
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="Offline local fill and position";shot.lifetime = .keepAlways;add(shot)
    }
    func testOfflineOnboardingAndNavigation() throws {
        let app=launchClean();defer{finish()}
        let launchShot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());launchShot.name="Launch screen evidence";launchShot.lifetime = .keepAlways;add(launchShot)
        print("APP_LAUNCH_STATE",app.state.rawValue)
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:15),"App terminated during startup")
        guard app.state == .runningForeground else{return}
        try startFreshOffline(app)
        XCTAssertTrue(app.tabBars.buttons["行情"].waitForExistence(timeout:30),app.debugDescription)
        app.tabBars.buttons["行情"].tap()
        XCTAssertTrue(app.textFields["marketSearch"].waitForExistence(timeout:5))
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
        let app=launchClean();defer{finish()}
        try startFreshOffline(app)
        app.tabBars.buttons["交易"].tap()
        let regularBoard=app.buttons["整股（張）"];try reveal(regularBoard,in:app);regularBoard.tap()
        try waitUntil("Whole-lot selection did not take effect before opening an order",timeout:5){regularBoard.isSelected}
        let open=app.buttons["openOrder"];for _ in 0..<5 where !open.isHittable{app.swipeUp()};open.tap()
        app.buttons["orderKind"].tap();app.buttons["市價"].tap()
        let submit=app.buttons["submitOrder"];for _ in 0..<5 where !submit.isHittable{app.swipeUp()};submit.tap();app.buttons["確認送出"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout:15));app.tabBars.buttons["總覽"].tap()
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        app.buttons["設定"].tap()
        app.buttons["模式與帳戶"].tap()
        app.buttons["A 真實行情・模擬交易"].tap()
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        try waitUntil("Settings sheet did not dismiss before backgrounding"){
            !app.navigationBars["設定"].exists && app.tabBars.buttons["總覽"].isHittable
        }
        // Retained source30 failure already showed the real Home screen and
        // foreground=false, but XCUIApplication.state never reported either
        // background enum. Require independent system and App scene evidence;
        // keep the same Home event and original ten-second deadline.
        let expectedBackground=try state(app)
        let expectedMode=try XCTUnwrap(expectedBackground["mode"] as? String)
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        XCUIDevice.shared.press(.home)
        var backgroundEvidence:[String:Any]=[:]
        try waitUntil("System Home and App lifecycle did not confirm background",timeout:10){
            let systemState=springboard.state,applicationState=app.state
            guard systemState == .runningForeground,
                  let snapshot=try? app.staticTexts["uiTestState"].firstMatch.snapshot(),
                  let raw=try? JSONSerialization.jsonObject(with:Data(snapshot.label.utf8)),
                  let scene=raw as? [String:Any] else{return false}
            backgroundEvidence=["systemHomeState":String(describing:systemState),"applicationState":String(describing:applicationState),"foreground":scene["foreground"] ?? "missing","mode":scene["mode"] ?? "missing","session":scene["session"] ?? "missing"]
            let observedMode=scene["mode"] as? String,observedSession=scene["session"] as? String
            return scene["foreground"] as? Bool == false && observedMode == expectedMode && observedSession == self.session
        }
        capture("System Home and application background verified",includeHierarchy:false,snapshot:backgroundEvidence)
        app.activate()
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["activeModeBanner"].waitForExistence(timeout:30))
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"A 真實行情・模擬交易")
        app.buttons["設定"].tap();app.buttons["模式與帳戶"].tap();app.buttons["B 離線市場・模擬交易"].tap();app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完成"].tap()
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["activeModeBanner"].waitForExistence(timeout:30))
        XCTAssertEqual(app.staticTexts["activeModeBanner"].label,"B 離線市場・模擬交易")
        app.tabBars.buttons["資產"].tap()
        XCTAssertEqual((try state(app)["positions"] as? [String:String])?["SIM:TWSE:2330"],"1000")
    }

    func testChartScreenshotCanBeAttachedToLocalJournal()throws{
        let app=launchClean();var completed=false;defer{finish(includeHierarchy:!completed)}
        try startFreshOffline(app);app.tabBars.buttons["交易"].tap()
        let capture=app.buttons["截圖"]
        // Retained c333 failure put the entire canvas below the fixed actions.
        // Inspect the visible chart before the same 10-second draw assertion.
        try reveal(app.webViews["inlineChartWeb"].firstMatch,in:app,identifier:"inlineChartWeb")
        try waitUntil("Chart screenshot requested before actual canvas rendering",timeout:10){((try? self.state(app)["chartRendered"] as? [String:Int])?["inline"] ?? 0)>0}
        try reveal(capture,in:app,identifier:"captureChart")
        XCTAssertTrue(capture.isHittable);capture.tap()
        let captured=app.buttons["dismissNotice"]
        try check(captured.waitForExistence(timeout:10),"Actual chart capture did not show its completion notice")
        try check(captured.label.hasPrefix("已保存本機圖表草稿"),"Chart capture returned an unrelated notice")
        let capturedState=try state(app)
        try check(capturedState["chartCapturing"] as? Bool==false && (capturedState["journalScreenshotBytes"] as? Int ?? 0)>0,"Notice did not correspond to a completed PNG capture")
        captured.tap()
        app.tabBars.buttons["資產"].tap()
        let journal=app.buttons["本機交易日誌"]
        for _ in 0..<5 where !journal.isHittable{app.swipeUp()}
        XCTAssertTrue(journal.isHittable);journal.tap()
        let attachment=app.switches["attachJournalChart"]
        XCTAssertTrue(attachment.waitForExistence(timeout:10))
        if attachment.value as? String != "1"{attachment.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.5)).tap()}
        XCTAssertEqual(attachment.value as? String,"1")
        XCTAssertTrue(app.images["journalChartPreview"].waitForExistence(timeout:5))
        let text=app.textViews["journalText"];try enterVerified("CT_CHART_JOURNAL_2374",into:text)
        let save=app.buttons["保存日誌"]
        for _ in 0..<5 where !save.isHittable{app.swipeUp()}
        XCTAssertTrue(save.isHittable);save.tap()
        let exportImage=app.buttons["匯出這張模擬圖表"]
        for _ in 0..<6 where !exportImage.isHittable{app.swipeUp()}
        if !exportImage.exists{self.capture("FAIL saved chart export missing before original assertion")}
        XCTAssertTrue(exportImage.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.alerts["操作未完成"].exists)
        XCTAssertTrue(app.images["savedJournalChart"].exists)
        XCTAssertEqual((try state(app)["journals"] as? [[String:String]])?.first?["text"],"CT_CHART_JOURNAL_2374")
        app.buttons["完成"].tap()
        completed=true
    }

    func testChartScreenshotTimeoutLeavesAccountAndJournalUnchanged()throws{
        let app=launchClean(flags:["--uitest-snapshot-timeout"]);var completed=false;defer{finish(includeHierarchy:!completed)}
        try startFreshOffline(app);app.tabBars.buttons["交易"].tap()
        try reveal(app.webViews["inlineChartWeb"].firstMatch,in:app,identifier:"inlineChartWeb")
        try waitUntil("Timeout scenario requires an actually rendered canvas",timeout:10){((try? self.state(app)["chartRendered"] as? [String:Int])?["inline"] ?? 0)>0}
        let capture=app.buttons["captureChart"];try reveal(capture,in:app,identifier:"captureChart")
        let before=try state(app);capture.tap()
        let failure=app.alerts["操作未完成"]
        try check(failure.waitForExistence(timeout:10),"Missing WebKit callback left the capture spinning indefinitely")
        try check(failure.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","圖表截圖逾時")).firstMatch.exists,"Timeout did not explain the next step")
        self.capture("Screenshot callback timeout preserves account and offers retry",includeHierarchy:false)
        failure.buttons["知道了"].tap()
        let after=try state(app)
        try check(after["chartCapturing"] as? Bool==false && after["journalScreenshotBytes"] as? Int==0,"Failed capture created a draft or remained busy")
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Failed capture changed cash")
        try check((after["orders"] as? [String])==(before["orders"] as? [String]),"Failed capture created orders")
        try check((after["journals"] as? [[String:String]])==(before["journals"] as? [[String:String]]),"Failed capture saved a journal")
        // The offline clock can start a separate candle refresh between the
        // state snapshot above and this native query. A loading chart is
        // intentionally disabled; require the real retry control to recover
        // within five seconds without changing the 120-second case allowance.
        try waitUntil("Timeout did not release the retry control",timeout:5){capture.isEnabled}
        completed=true
    }

}
