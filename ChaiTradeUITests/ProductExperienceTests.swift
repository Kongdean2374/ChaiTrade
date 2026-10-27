import XCTest

@MainActor final class ProductExperienceTests:IsolatedUITestCase{
    private func onboard(_ app:XCUIApplication,online:Bool=false)throws{
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh onboarding missing")
        if online{let choice=app.buttons["A 真實行情・模擬交易"];if !choice.exists{app.swipeDown()};choice.tap()}
        try reveal(start,in:app);start.tap();try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Fresh account failed")
        let s=try state(app)
        try check(s["session"] as? String==session,"Wrong product test directory")
        try check((s["instruments"] as? [[String:String]])?.count==125,"Fresh account did not contain the complete built-in catalog")
        for field in ["orders","fills","journals","watchlist"]{try check((s[field] as? [Any])?.isEmpty==true,"New case inherited "+field)}
        capture("PRODUCT clean fresh "+(online ? "A":"B"))
    }
    func testOfflineThreeActionDiscoveryAndFullStockJourney()throws{
        let app=launchClean();defer{finish()};try onboard(app)
        // Home's first stock is reachable directly; no hidden settings or catalog prerequisite.
        let product=app.buttons["market-SIM:TWSE:2330"].firstMatch;try reveal(product,in:app);product.tap()
        try check((try state(app))["selected"] as? String=="SIM:TWSE:2330","2330 selected the wrong identity")
        capture("AFTER B stock detail chart")
        app.buttons["整股（張）"].tap()
        let open=app.buttons["openOrder"];try check(open.isHittable,"Valid local quote has no reachable buy entry");open.tap()
        app.buttons["orderKind"].tap();app.buttons["市價"].tap()
        capture("AFTER stock basic order summary")
        let submit=app.buttons["submitOrder"];try reveal(submit,in:app);submit.tap();app.buttons["確認送出"].tap()
        try waitUntil("Stock receipt did not close and navigate",timeout:15){app.navigationBars["委託與成交"].exists && !app.navigationBars["模擬下單"].exists}
        let s=try state(app);try check((s["positions"] as? [String:String])?["SIM:TWSE:2330"]=="1000","A one-lot order did not produce exactly 1,000 shares")
        try check((s["orders"] as? [String])?.count==1,"One stock intent created multiple orders")
        capture("AFTER B orders and fills")
        try journal(app);try enterVerified("PRODUCT_STOCK_JOURNEY",into:app.textViews["journalText"])
        let save=app.buttons["saveJournal"];try reveal(save,in:app);save.tap()
        try waitUntil("Journey journal was not saved"){(try? self.state(app)["journals"] as? [[String:String]])?.count==1}
        capture("AFTER B journal");app.buttons["完成"].tap();capture("AFTER B assets with holding")
    }
    func testOfflineCryptoDiscoveryNewsAndContractSeparation()throws{
        let app=launchClean();defer{finish()};try onboard(app)
        app.buttons["marketCrypto"].tap()
        let btc=app.buttons["market-SIM:Coinbase_Exchange:BTC-USD"].firstMatch;try reveal(btc,in:app);btc.tap()
        try check((try state(app))["selected"] as? String=="SIM:Coinbase_Exchange:BTC-USD","BTC discovery selected a contract or another venue")
        try check(app.buttons["openOrder"].label=="買入","Crypto spot did not use spot language")
        capture("AFTER B BTC chart and price")
        app.tabBars.buttons["行情"].tap();let search=app.textFields["marketSearch"];search.tap();search.typeText("ETH")
        try check(app.buttons["market-SIM:Coinbase_Exchange:ETH-USD"].waitForExistence(timeout:5),"ETH is not searchable on first offline launch")
        try check(!app.buttons["market-SIM:TWSE:2330"].exists,"Crypto search leaked a stock")
        capture("AFTER B ETH search")
        app.buttons["清除搜尋"].tap();app.buttons["合約"].tap()
        try check(app.buttons["market-SIM:Binance_USDⓈ-M:BTCUSDT"].waitForExistence(timeout:5),"Contract entrance missing")
        try check(!app.buttons["market-SIM:Coinbase_Exchange:BTC-USD"].exists,"Spot and contract default lists were mixed")
        capture("AFTER B crypto contracts")
        app.tabBars.buttons["總覽"].tap();let news=app.buttons["全部"].firstMatch;try reveal(news,in:app);news.tap()
        try check(app.navigationBars["新聞"].waitForExistence(timeout:5),"Market news cannot be opened")
        let items=try state(app)["news"] as? [[String:String]] ?? []
        try check(!items.isEmpty && items.allSatisfy{$0["origin"]=="simulated" && $0["label"]=="模擬情境，非真實新聞"},"Offline news lacks explicit simulation labels")
        capture("AFTER B crypto simulated news")
    }
    func testRapidMarketSwitchKeepsQueriesFavoritesAndMoneyAcrossRestart()throws{
        let app=launchClean();defer{finish()};try onboard(app)
        let original=try state(app)["cash"] as? [String:String]
        app.tabBars.buttons["行情"].tap();app.textFields["marketSearch"].tap();app.textFields["marketSearch"].typeText("2330")
        let favorite=app.buttons["watch-SIM:TWSE:2330"];try check(favorite.waitForExistence(timeout:5),"Stock favorite entry missing");favorite.tap()
        app.buttons["marketCrypto"].tap();app.textFields["marketSearch"].tap();app.textFields["marketSearch"].typeText("ETH")
        for _ in 0..<3{app.buttons["marketStocks"].tap();app.buttons["marketCrypto"].tap()}
        try check(app.textFields["marketSearch"].value as? String=="ETH","Crypto query lost during rapid switching")
        try check(app.buttons["market-SIM:Coinbase_Exchange:ETH-USD"].exists,"Crypto query points to wrong market")
        app.buttons["marketStocks"].tap()
        try check(app.textFields["marketSearch"].value as? String=="2330","Stock query replaced by crypto query")
        try check((try state(app)["watchlist"] as? [String])==["SIM:TWSE:2330"],"Market switching lost favorite")
        try check((try state(app)["cash"] as? [String:String])==original,"Browsing moved account money")
        // Home/background flushes the same persistence path used outside tests.
        XCUIDevice.shared.press(.home);app.activate();app.terminate();app.launch()
        try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Relaunch failed")
        app.tabBars.buttons["行情"].tap();try check(app.textFields["marketSearch"].value as? String=="2330","Stock search did not survive restart")
        app.buttons["marketCrypto"].tap();try check(app.textFields["marketSearch"].value as? String=="ETH","Crypto search did not survive restart")
        try check((try state(app)["cash"] as? [String:String])==original,"Relaunch changed browsing account cash")
        capture("AFTER per-market browsing restored")
    }
    func testFreshAHasSpecificKeyStateAndLoadsMultiplePublicQuotes()throws{
        let app=launchClean();defer{finish()};try onboard(app,online:true)
        app.tabBars.buttons["行情"].tap()
        let stock=app.buttons["market-fugle:2330"]
        try check(stock.waitForExistence(timeout:5),"A built-in stock directory missing")
        try check(stock.label.contains("尚未設定行情金鑰"),"Missing stock key was not explained specifically")
        capture("AFTER A stocks without credentials")
        app.buttons["marketCrypto"].tap()
        try waitUntil("Visible BTC and ETH did not both receive actual public prices",timeout:40){
            guard let quotes=try? self.state(app)["quotes"] as? [String:[String:String]] else{return false}
            return quotes["coinbase:BTC-USD"]?["valid"]=="true" && quotes["coinbase:ETH-USD"]?["valid"]=="true"
        }
        capture("AFTER A visible BTC ETH quotes actual HTTP")
        app.buttons["marketStocks"].tap();stock.tap()
        try check(!app.buttons["openOrder"].exists,"Unconfigured A stock exposed an operational buy panel")
        app.tabBars.buttons["委託"].tap();try check(app.navigationBars["委託與成交"].exists,"Unavailable quote hid local order records")
    }
    func testSettingsSectionsCancelAndSafeAreaReachability()throws{
        let app=launchClean();defer{finish()};try onboard(app)
        app.buttons["設定"].tap()
        for title in ["模式與帳戶","行情連線","交易偏好","離線模擬","外觀與通知","資料備份／還原","進階診斷"]{try check(app.buttons[title].exists,"Missing settings group "+title)}
        capture("AFTER settings seven sections")
        app.buttons["行情連線"].tap();try check(app.staticTexts["目前是完全離線帳戶"].waitForExistence(timeout:5),"B incorrectly offered online credentials")
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完成"].tap()
        let bottom=app.staticTexts["homeBottom"];try reveal(bottom,in:app);try check(bottom.isHittable,"Home cannot scroll below final content")
        capture("AFTER home bottom safe area")
        app.tabBars.buttons["資產"].tap();let end=app.staticTexts["portfolioBottom"];try reveal(end,in:app);try check(end.isHittable,"Assets cannot scroll to final content")
        capture("AFTER assets bottom safe area")
    }
    func testChartLandscapeAndReturnKeepsSelectedProduct()throws{
        let app=launchClean();defer{finish()};try onboard(app)
        app.tabBars.buttons["交易"].tap()
        let selected=try state(app)["selected"] as? String
        let fullscreen=app.buttons["openFullscreenChart"];try reveal(fullscreen,in:app);fullscreen.tap();XCUIDevice.shared.orientation = .landscapeLeft
        defer{XCUIDevice.shared.orientation = .portrait}
        try check(app.otherElements["fullscreenChart"].waitForExistence(timeout:10),"Landscape chart did not open")
        try check(app.frame.width>app.frame.height,"Chart did not actually rotate")
        capture("AFTER landscape chart")
        app.buttons["完成"].tap();XCUIDevice.shared.orientation = .portrait
        try check((try state(app))["selected"] as? String==selected,"Returning from landscape changed product")
        try check(app.tabBars.buttons["交易"].isHittable,"Chart left an overlay over navigation")
    }
}
