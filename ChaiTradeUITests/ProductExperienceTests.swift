import XCTest

@MainActor final class ProductExperienceTests:IsolatedUITestCase{
    private func onboard(_ app:XCUIApplication,online:Bool=false,currency:String="TWD")throws{
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh onboarding missing")
        if currency != "TWD"{let picker=app.buttons["baseCurrency"];try reveal(picker,in:app);picker.tap();app.buttons[currency].tap()}
        if online{let choice=app.buttons["A 真實行情"];if !choice.exists{app.swipeDown()};choice.tap()}
        try reveal(start,in:app);start.tap();try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Fresh account failed")
        let s=try state(app)
        try check(s["session"] as? String==session,"Wrong product test directory")
        try check((s["instruments"] as? [[String:String]])?.count==125,"Fresh account did not contain the complete built-in catalog")
        for field in ["orders","fills","journals","watchlist"]{try check((s[field] as? [Any])?.isEmpty==true,"New case inherited "+field)}
        capture("PRODUCT clean fresh "+(online ? "A":"B"))
    }
    func testPercentageAlertRapidCreateRemoveAndNotificationCenterIsolation()throws{
        let app=launchClean();defer{finish()};try onboard(app)
        let original=try state(app)["cash"] as? [String:String]
        let product=app.buttons["market-SIM:TWSE:2330"].firstMatch;try reveal(product,in:app);product.tap()
        let alert=app.buttons["openPriceAlert"];try reveal(alert,in:app);alert.tap()
        app.buttons["百分比變化"].tap();let input=app.textFields["priceAlertValue"];input.tap();input.typeText("5")
        let create=app.buttons["createPriceAlert"];try check(create.isHittable,"Keyboard hides percentage alert creation");rapid(create)
        try waitUntil("Rapid alert creation did not persist exactly once"){
            (try? self.state(app)["alerts"] as? [[String:String]])?.count==1
        }
        let saved=try XCTUnwrap((try state(app)["alerts"] as? [[String:String]])?.first)
        try check(saved["instrument"]=="SIM:TWSE:2330" && saved["percentage"]=="5","Alert belongs to wrong product or type")
        let baseline=number(try XCTUnwrap(saved["baseline"])),threshold=number(try XCTUnwrap(saved["price"]))
        try check(threshold==baseline.multiplying(by:number("1.05")),"Percentage basis or threshold was not fixed exactly")
        capture("AFTER percentage alert fixed basis and keyboard")
        app.buttons["收起鍵盤"].tap();let remove=app.buttons["刪除提醒"];try reveal(remove,in:app);rapid(remove)
        try waitUntil("Repeated alert deletion left an active reminder"){(try? self.state(app)["alerts"] as? [[String:String]])?.isEmpty==true}
        app.buttons["完成"].tap();app.tabBars.buttons["資產"].tap()
        try check((try state(app)["cash"] as? [String:String])==original,"Price alert changed cash")
        app.buttons["設定"].tap();app.buttons["外觀與通知"].tap();let inbox=app.buttons["通知中心"];try reveal(inbox,in:app);inbox.tap()
        try check(app.navigationBars["通知中心"].exists,"Account inbox is not reachable")
        try check((try state(app)["inbox"] as? [[String:String]])?.allSatisfy{$0["account"]=="account-offline"}==true,"Inbox leaked another account")
        capture("AFTER account notification center")
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
        app.tabBars.buttons["總覽"].tap();let news=app.buttons["openMarketNews"];try reveal(news,in:app);news.tap()
        try check(app.navigationBars["新聞"].waitForExistence(timeout:5),"Market news cannot be opened")
        let items=try state(app)["news"] as? [[String:String]] ?? []
        try check(!items.isEmpty && items.allSatisfy{$0["origin"]=="simulated" && $0["label"]=="模擬情境，非真實新聞"},"Offline news lacks explicit simulation labels")
        capture("AFTER B crypto simulated news")
        let first=try XCTUnwrap(items.first?["id"]),story=app.buttons["news-"+first]
        try reveal(story,in:app);story.tap()
        try check(app.navigationBars["新聞詳情"].waitForExistence(timeout:5),"Simulation news detail cannot be opened")
        try check(app.staticTexts["模擬情境，非真實新聞"].firstMatch.exists,"News detail loses simulation warning")
        capture("AFTER B crypto simulated news detail and causal factors")
        app.navigationBars.buttons.element(boundBy:0).tap()
        try check(app.navigationBars["新聞"].exists,"News back navigation lost the market feed")
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
        app.buttons["marketCrypto"].tap()
        try waitUntil("Crypto market did not activate after restart",timeout:5){(try? self.state(app)["market"] as? String)=="crypto"}
        try check(app.textFields["marketSearch"].value as? String=="ETH","Crypto search did not survive restart")
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
        try check(app.webViews["fullscreenChartWeb"].firstMatch.waitForExistence(timeout:10),"Landscape chart did not open")
        try check(app.frame.width>app.frame.height,"Chart did not actually rotate")
        capture("AFTER landscape chart")
        try check(app.buttons["closeFullscreenChart"].isHittable,"Landscape close button is outside the safe area")
        app.buttons["closeFullscreenChart"].tap();XCUIDevice.shared.orientation = .portrait
        try check((try state(app))["selected"] as? String==selected,"Returning from landscape changed product")
        try check(app.tabBars.buttons["交易"].isHittable,"Chart left an overlay over navigation")
    }
    func testFullFileArchiveExportAndCacheCleanupPreserveAccount()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let original=try state(app)
        app.buttons["設定"].tap();app.buttons["資料備份／還原"].tap()
        let export=app.buttons["exportFileArchive"];try check(export.waitForExistence(timeout:5),"Complete archive entry missing");rapid(export)
        try waitUntil("Complete file archive did not finish",timeout:30){
            guard let s=try? self.state(app) else{return false};return s["fileArchiveReady"] as? Bool==true && s["fileArchiveWorking"] as? Bool==false
        }
        let share=app.buttons["shareFileArchive"];try reveal(share,in:app);capture("AFTER complete file archive ready to share")
        let clear=app.buttons["clearFileShareCache"];try reveal(clear,in:app);clear.tap()
        try waitUntil("Share cache cleanup left a stale file reference"){(try? self.state(app)["fileArchiveReady"] as? Bool)==false}
        let after=try state(app)
        for key in ["cash","positions"]{try check((after[key] as? [String:String])==(original[key] as? [String:String]),"Archive altered "+key)}
        for key in ["orders","fills","journals","watchlist"]{try check((after[key] as? [Any])?.isEmpty==true,"Archive created "+key)}
        capture("AFTER file cache cleanup keeps account")
    }
    func testActualPublicSourceDirectoryAddsOnlySelectedIdentityAndRoutesToProduct()throws{
        let app=launchClean();defer{finish()};try onboard(app,online:true)
        let before=try state(app),initialIDs=Set((before["instruments"] as? [[String:String]] ?? []).compactMap{$0["id"]})
        app.tabBars.buttons["行情"].tap();app.buttons["openCatalog"].tap()
        let source=app.buttons["catalogSource-coinbase"];try reveal(source,in:app);source.tap()
        let message=app.staticTexts["sourceCatalogMessage"]
        try waitUntil("Actual public source directory did not load",timeout:30){message.exists && message.label.contains("已取得")}
        try check((try state(app)["instruments"] as? [[String:String]])?.count==initialIDs.count,"Browsing mass-imported source directory")
        capture("AFTER actual public source identity directory")
        let choices=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND identifier ENDSWITH %@","discover-coinbase:","-USD")).allElementsBoundByIndex
        let row=try XCTUnwrap(choices.first{!initialIDs.contains(String($0.identifier.dropFirst("discover-".count)))})
        let expected=String(row.identifier.dropFirst("discover-".count));try reveal(row,in:app);row.tap()
        try waitUntil("Selected directory identity did not return to product",timeout:15){
            guard let s=try? self.state(app) else{return false};return s["selected"] as? String==expected && s["tab"] as? Int==2 && !app.buttons["reloadSourceCatalog"].exists
        }
        let after=try state(app),catalog=try XCTUnwrap(after["instruments"] as? [[String:String]])
        try check(catalog.count==initialIDs.count+1 && catalog.filter{$0["id"]==expected}.count==1,"One selection did not add exactly one identity")
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Product discovery moved money")
        for key in ["orders","fills","journals","watchlist"]{try check((after[key] as? [Any])?.isEmpty==true,"Discovery created "+key)}
        capture("AFTER selected public identity in product")
    }
    func testMissingFugleKeyExplainsDirectoryFailureWithoutChangingAccount()throws{
        let app=launchClean();defer{finish()};try onboard(app,online:true)
        let before=try state(app)
        app.tabBars.buttons["行情"].tap();app.buttons["openCatalog"].tap()
        let source=app.buttons["catalogSource-fugle"];try reveal(source,in:app);source.tap()
        let message=app.staticTexts["sourceCatalogMessage"]
        try check(message.waitForExistence(timeout:10) && message.label.contains("金鑰"),"Missing directory credential was not explained")
        try check(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","discover-")).count==0,"Unconfigured source fabricated catalog entries")
        let after=try state(app)
        try check((after["instruments"] as? [[String:String]])==(before["instruments"] as? [[String:String]]),"Failed source discovery altered existing identities")
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Failed discovery changed cash")
        capture("AFTER source directory missing Key is explicit")
    }
    func testLocalRecoveryCancelThenVerifiedRestorePreservesOriginalPoint()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let cash=try state(app)["cash"] as? [String:String]
        app.buttons["設定"].tap();app.buttons["資料備份／還原"].tap();app.buttons["createRecoveryPoint"].tap()
        try check(app.staticTexts["本機恢復點已建立。"].waitForExistence(timeout:15),"Local point did not finish")
        capture("AFTER consistent local recovery point")
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完成"].tap()
        try journal(app);try enterVerified("AFTER_POINT",into:app.textViews["journalText"]);app.buttons["saveJournal"].tap()
        try waitUntil("Post-point journal missing"){(try? self.state(app)["journals"] as? [[String:String]])?.count==1}
        app.buttons["完成"].tap();app.tabBars.buttons["總覽"].tap();app.buttons["設定"].tap();app.buttons["資料備份／還原"].tap();app.buttons["本機恢復點"].tap()
        let point=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","recoveryPoint-manual-")).firstMatch
        try check(point.waitForExistence(timeout:5),"Manual point not listed in current account");point.tap();app.buttons["取消"].tap()
        try check((try state(app)["journals"] as? [[String:String]])?.count==1,"Canceled restore changed journal")
        point.tap();app.buttons["確認驗證並還原"].tap()
        try waitUntil("Verified local point did not restore",timeout:30){
            guard let s=try? self.state(app) else{return false};return s["fileArchiveWorking"] as? Bool==false && (s["journals"] as? [[String:String]])?.isEmpty==true
        }
        try check((try state(app)["cash"] as? [String:String])==cash,"Local point restore changed saved cash")
        try check(point.exists,"Original manual recovery point disappeared")
        capture("AFTER verified local point restored and original retained")
    }
    func testCryptoSpotBuySellJourneyHasExactLocalAccounting()throws{
        let app=launchClean();defer{finish()};try onboard(app,currency:"USD")
        app.buttons["marketCrypto"].tap();let product=app.buttons["market-SIM:Coinbase_Exchange:BTC-USD"].firstMatch;try reveal(product,in:app);product.tap()
        try waitUntil("Crypto chart has no actual local candles",timeout:10){guard let snapshot=try? self.state(app),let time=snapshot["chartTime"] as? NSNumber else{return false};return time.int64Value>0}
        capture("AFTER B USD crypto chart before trade")
        for action in ["openOrder","openSellOrder"]{
            app.tabBars.buttons["交易"].tap();let entry=app.buttons[action];try reveal(entry,in:app);entry.tap()
            app.buttons["orderKind"].tap();app.buttons["市價"].tap()
            let submit=app.buttons["submitOrder"];try reveal(submit,in:app);submit.tap();app.buttons["確認送出"].tap()
            try waitUntil("Crypto receipt did not reach orders",timeout:10){app.navigationBars["委託與成交"].exists && !app.navigationBars["模擬下單"].exists}
            capture("AFTER B crypto "+(action=="openOrder" ? "buy":"sell")+" order receipt")
        }
        let s=try state(app),fills=try XCTUnwrap(s["fills"] as? [[String:String]])
        try check((s["orders"] as? [String])?.count==2,"Crypto two intents created incorrect order count")
        try check(fills.count==2 && fills.allSatisfy{$0["quantity"]=="0.001"},"Crypto buy/sell quantity was duplicated or changed")
        try check((s["positions"] as? [String:String])?["SIM:Coinbase_Exchange:BTC-USD"]=="0","Crypto spot roundtrip left a position")
        let cash=try XCTUnwrap((s["cash"] as? [String:String])?["USD"]).replacingOccurrences(of:",",with:"")
        let entries=try XCTUnwrap(s["fillCash"] as? [[String:String]])
        var expected=Decimal(1000000)
        for entry in entries{expected+=try XCTUnwrap(entry["amount"].flatMap{Decimal(string:$0,locale:Locale(identifier:"en_US_POSIX"))})}
        try check(Decimal(string:cash,locale:Locale(identifier:"en_US_POSIX"))==expected,"Crypto account cash does not equal exact posted fill cash")
        app.tabBars.buttons["資產"].tap();capture("AFTER B crypto assets after roundtrip")
    }
    func testContractPositionHasAnExplicitReduceOnlyCloseJourney()throws{
        let app=launchClean();defer{finish()};try onboard(app,currency:"USDT")
        app.buttons["marketCrypto"].tap();app.tabBars.buttons["行情"].tap();app.buttons["合約"].tap()
        let instrument="SIM:Binance_USDⓈ-M:BTCUSDT",product=app.buttons["market-"+instrument];try reveal(product,in:app);product.tap()
        app.buttons["openOrder"].tap();app.buttons["orderKind"].tap();app.buttons["市價"].tap()
        var review=app.buttons["submitOrder"];try reveal(review,in:app);review.tap();app.buttons["確認送出"].tap()
        try waitUntil("Contract open did not reach receipt",timeout:12){app.navigationBars["委託與成交"].exists && !app.navigationBars["模擬下單"].exists}
        try check((try state(app)["positions"] as? [String:String])?[instrument]=="1","Contract open produced the wrong position")
        app.tabBars.buttons["交易"].tap();let close=app.buttons["closePosition-"+instrument];try reveal(close,in:app)
        capture("AFTER contract position with explicit close and risk");close.tap()
        try check(app.staticTexts["平多"].firstMatch.waitForExistence(timeout:5),"Close draft lost its direction")
        try check(app.textFields["orderQuantity"].value as? String=="1","Close draft did not use held quantity")
        app.buttons["orderKind"].tap();app.buttons["市價"].tap();review=app.buttons["submitOrder"];try reveal(review,in:app);review.tap();app.buttons["確認送出"].tap()
        try waitUntil("Contract close did not reach receipt",timeout:12){app.navigationBars["委託與成交"].exists && !app.navigationBars["模擬下單"].exists}
        let snapshot=try state(app),intents=try XCTUnwrap(snapshot["orderIntents"] as? [[String:String]])
        try check(intents.count==2 && intents.filter{$0["reduceOnly"]=="true" && $0["side"]=="sell"}.count==1,"Close was not exactly one reduce-only sell")
        try check((snapshot["positions"] as? [String:String])?[instrument]=="0","Explicit contract close reversed or retained the position")
        app.tabBars.buttons["資產"].tap();capture("AFTER contract local roundtrip assets")
    }

}
