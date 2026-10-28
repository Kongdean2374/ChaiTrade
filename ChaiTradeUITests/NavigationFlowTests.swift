import XCTest

@MainActor final class NavigationFlowTests:IsolatedUITestCase{
    private func verifyBrowsingOnly(_ id:String,query:String,crypto:Bool)throws{
        let app=launchClean();defer{finish()}
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh navigation account missing");start.tap()
        try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Navigation account failed to load")
        let initial=try state(app)
        try check(initial["session"] as? String==session,"Navigation test reused another case")
        for key in ["orders","fills","journals","watchlist"]{try check((initial[key] as? [Any])?.isEmpty==true,"Navigation case inherited "+key)}
        app.tabBars.buttons["行情"].tap();if crypto{app.buttons["marketCrypto"].tap()}
        let search=app.textFields["marketSearch"];search.tap();search.typeText(query)
        let product=app.buttons["market-"+id];try check(product.waitForExistence(timeout:5),"Exact product is missing: "+id);product.tap()
        let viewed=try state(app)
        try check(viewed["tab"] as? Int==1,"Browsing "+query+" silently switched from markets to trade")
        try check(app.tabBars.buttons["行情"].isSelected,"Product detail does not belong to the market tab")
        try check(viewed["selected"] as? String==id,"Detail used another venue or asset identity")
        try check(!app.navigationBars["模擬下單"].exists,"Viewing a product opened an order form")
        try check((viewed["cash"] as? [String:String])==(initial["cash"] as? [String:String]),"Browsing moved account funds")
        try check((viewed["orders"] as? [Any])?.isEmpty==true && (viewed["fills"] as? [Any])?.isEmpty==true,"Browsing created an order")
        capture("FLOW markets-only detail "+query)
        app.navigationBars.buttons.element(boundBy:0).tap()
        try check(app.textFields["marketSearch"].value as? String==query,"Back reset market search")
        try check(try state(app)["quoteFocus"] as? String=="","Back retained an invisible detail subscription")
    }
    func test2330DetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:TWSE:2330",query:"2330",crypto:false)}
    func testBTCDetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:Coinbase_Exchange:BTC-USD",query:"BTC",crypto:true)}
    func testETHDetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:Coinbase_Exchange:ETH-USD",query:"ETH",crypto:true)}
}

@MainActor final class TradingHandoffTests:IsolatedUITestCase{
    private func onboardUSD(_ app:XCUIApplication)throws{
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh onboarding missing")
        let currency=app.buttons["baseCurrency"];try reveal(currency,in:app);currency.tap();app.buttons["USD"].tap();try reveal(start,in:app);start.tap()
        try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Clean account failed")
        let s=try state(app);for key in ["orders","fills","journals","watchlist"]{try check((s[key] as? [Any])?.isEmpty==true,"Inherited "+key)}
    }
    private func detail(_ app:XCUIApplication,_ symbol:String)throws{
        app.tabBars.buttons["行情"].tap();app.buttons["marketCrypto"].tap()
        let search=app.textFields["marketSearch"];try check(search.waitForExistence(timeout:5),"Market list not restored");search.tap();search.typeText(symbol)
        app.buttons["market-SIM:Coinbase_Exchange:"+symbol+"-USD"].tap()
        try check(app.tabBars.buttons["行情"].isSelected,"Browsing changed tab")
        capture("FLOW list to "+symbol+" detail stays in markets")
    }
    func testExplicitSellHandsExactETHIdentityToTradeWithoutSubmitting()throws{
        let app=launchClean();defer{finish()};try onboardUSD(app);try detail(app,"ETH")
        app.buttons["openSellOrder"].tap()
        try check(app.navigationBars["模擬下單"].waitForExistence(timeout:5),"Explicit sell did not open trade form")
        let s=try state(app);try check(s["tab"] as? Int==2 && s["tradeProduct"] as? String=="SIM:Coinbase_Exchange:ETH-USD" && s["tradeSide"] as? String=="sell","ETH sell handoff changed identity, tab or side")
        try check((s["orders"] as? [String])?.isEmpty==true,"Handoff submitted automatically")
        try check(app.segmentedControls.buttons["賣出"].isSelected,"Form lost explicit sell direction")
        capture("FLOW ETH explicit sell exact identity no auto order")
    }
    func testMarketDetailTradePickerThenOneSimulatedOrder()throws{
        let app=launchClean();defer{finish()};try onboardUSD(app);try detail(app,"BTC")
        app.buttons["openOrder"].tap();try check(app.navigationBars["模擬下單"].waitForExistence(timeout:5),"Buy handoff failed")
        try check((try state(app)["orders"] as? [String])?.isEmpty==true,"Buy handoff submitted automatically")
        capture("FLOW explicit buy switches to trade form");app.buttons["完成"].tap()
        let picker=app.buttons["tradeProductPicker"];try reveal(picker,in:app);picker.tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("ETH")
        let eth=app.buttons["trade-product-SIM:Coinbase_Exchange:ETH-USD"];try reveal(eth,in:app);eth.tap()
        try waitUntil("Independent trade picker failed"){(try? self.state(app)["tradeProduct"] as? String)=="SIM:Coinbase_Exchange:ETH-USD"}
        capture("FLOW independent trade picker changed BTC to ETH")
        let open=app.buttons["openOrder"];try check(open.waitForExistence(timeout:5),"New ETH quote did not enable an explicit order entry");open.tap();let size=app.textFields["orderQuantity"];try reveal(size,in:app)
        try check(size.value as? String=="0.001","Another product quantity leaked into ETH")
        size.tap();size.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:8)+"0.01")
        app.buttons["orderKind"].tap();app.buttons["市價"].tap()
        let submit=app.buttons["submitOrder"];try reveal(submit,in:app);submit.tap()
        try check(app.alerts["確認本機模擬委託"].waitForExistence(timeout:5),"No order review")
        capture("FLOW exact ETH quantity and local account before confirm");rapid(app.buttons["確認送出"])
        try waitUntil("Confirmed simulation did not return receipt",timeout:10){app.navigationBars["委託與成交"].exists}
        let s=try state(app),intents=try XCTUnwrap(s["orderIntents"] as? [[String:String]])
        try check(intents.count==1 && intents[0]["instrument"]=="SIM:Coinbase_Exchange:ETH-USD" && intents[0]["side"]=="buy","One intent used wrong product/side or duplicated")
        try check((s["fills"] as? [[String:String]])?.count==1,"Simulation filled more than once")
        try check((s["positions"] as? [String:String])?["SIM:Coinbase_Exchange:ETH-USD"]=="0.01","Simulation position wrong")
        capture("FLOW single local fill and receipt")
    }
}

@MainActor final class TradeWorkspaceInteractionTests:IsolatedUITestCase{
    func testBrowsingAndCancelledHandoffKeepDirtyDraft()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app)
        app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        let size=app.textFields["orderQuantity"];try reveal(size,in:app);size.tap();size.typeText(XCUIKeyboardKey.delete.rawValue+"7")
        app.buttons["完成"].tap();try waitUntil("Edited draft not retained"){(try? self.state(app)["tradeDraftQuantity"] as? String)=="7"}
        let saved=try state(app),original=try XCTUnwrap(saved["tradeProduct"] as? String)
        app.tabBars.buttons["行情"].tap();app.buttons["marketCrypto"].tap()
        let search=app.textFields["marketSearch"];search.tap();search.typeText("ETH");app.buttons["market-SIM:Coinbase_Exchange:ETH-USD"].tap()
        try check((try state(app)["tradeProduct"] as? String)==original,"Browsing changed draft product")
        app.buttons["openSellOrder"].tap();try check(app.buttons["保留原草稿"].waitForExistence(timeout:5),"Dirty draft silently overwritten")
        capture("FLOW explicit dirty draft conflict");app.buttons["保留原草稿"].tap()
        let kept=try state(app);try check(kept["tradeProduct"] as? String==original && kept["tradeDraftQuantity"] as? String=="7" && kept["tab"] as? Int==1,"Keep did not cancel handoff")
        app.buttons["openSellOrder"].tap();app.buttons["放棄草稿並切換商品／方向"].tap()
        try check(app.navigationBars["模擬下單"].waitForExistence(timeout:5),"Discard did not open requested form")
        try check(app.textFields["orderQuantity"].value as? String=="0.001","Discard reused old stock size in ETH")
        try check((try state(app)["orders"] as? [String])?.isEmpty==true,"Draft conflict sent an order")
        capture("FLOW discard resets ETH quantity and keeps orders empty")
    }
    func testDirectTradePickerCategoriesEmptyAndClearPreserveAccount()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app);let original=try state(app)
        app.tabBars.buttons["交易"].tap();app.buttons["tradeProductPicker"].tap()
        app.buttons["tradePickerMarket"].tap();app.buttons["加密貨幣"].tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("NO_SUCH_PRODUCT_293")
        try check(app.staticTexts["沒有符合的商品"].waitForExistence(timeout:5),"Picker has no clear empty state")
        app.buttons["tradePickerClear"].tap();try check(search.value as? String=="搜尋名稱、代碼或交易所" || search.value as? String=="","Clear did not clear query")
        search.tap();search.typeText("BTC")
        let btc=app.buttons["trade-product-SIM:Coinbase_Exchange:BTC-USD"];try reveal(btc,in:app);btc.tap()
        let selected=try state(app);try check(selected["tradeProduct"] as? String=="SIM:Coinbase_Exchange:BTC-USD","Picker selected another venue")
        try check(selected["market"] as? String==original["market"] as? String,"Trade picker polluted market browsing classification")
        try check((selected["cash"] as? [String:String])==(original["cash"] as? [String:String]),"Picker changed funds")
        try check((selected["orders"] as? [String])?.isEmpty==true,"Picker auto submitted")
        capture("FLOW direct trade categorized picker search clear and selection")
    }
    func testPickerDismissesBeforeDirtyDraftConfirmationAndKeepCancelsSwitch()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app)
        app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);quantity.tap();quantity.typeText(XCUIKeyboardKey.delete.rawValue+"7");app.buttons["完成"].tap()
        let original=try state(app)["tradeProduct"] as? String
        let choose=app.buttons["tradeProductPicker"];try reveal(choose,in:app);choose.tap();app.buttons["tradePickerMarket"].tap();app.buttons["加密貨幣"].tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("BTC")
        let product=app.buttons["trade-product-SIM:Coinbase_Exchange:BTC-USD"];try reveal(product,in:app);product.tap()
        try check(app.buttons["保留原草稿"].waitForExistence(timeout:5),"Picker dismissal lost draft confirmation")
        try check(!app.navigationBars["選擇交易商品"].exists,"Draft confirmation stacked over picker")
        app.buttons["保留原草稿"].tap();let kept=try state(app)
        try check(kept["tradeProduct"] as? String==original && kept["tradeDraftQuantity"] as? String=="7","Keeping picker conflict overwrote original draft")
        try check((kept["orders"] as? [String])?.isEmpty==true,"Picker confirmation sent order")
        capture("FLOW picker fully closed then keep original unsent draft")
    }
    func testCryptoTradeNewsDoNotUseTheStockBrowserMarket()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app)
        app.tabBars.buttons["交易"].tap();app.buttons["tradeProductPicker"].tap();app.buttons["tradePickerMarket"].tap();app.buttons["加密貨幣"].tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("BTC")
        let product=app.buttons["trade-product-SIM:Coinbase_Exchange:BTC-USD"];try reveal(product,in:app);product.tap()
        try check(try state(app)["market"] as? String=="stocks","Trade selection changed browser market")
        let news=app.buttons["查看全部市場新聞"];try reveal(news,in:app);news.tap()
        try check(app.staticTexts["加密貨幣新聞"].waitForExistence(timeout:5),"BTC all-news link opened stock news")
        try check(!app.staticTexts["股票新聞"].exists,"Crypto news mixed stock browsing category")
        try check(try state(app)["market"] as? String=="stocks","News changed browser market")
        try check((try state(app)["orders"] as? [String])?.isEmpty==true,"Reading news submitted an order")
        capture("FLOW crypto trade news remains crypto with stock browser preserved")
    }
    func testKeyboardOpenCanScrollAndSelectASecondSearchResultWithoutChangingFavorites()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app)
        app.tabBars.buttons["交易"].tap();app.buttons["tradeProductPicker"].tap();app.buttons["tradePickerMarket"].tap();app.buttons["加密貨幣"].tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("ETH")
        try check(app.keyboards.firstMatch.exists,"Picker scroll case did not open keyboard")
        let rows=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","trade-product-"))
        try check(rows.firstMatch.identifier=="trade-product-SIM:Coinbase_Exchange:ETH-USD","Exact ETH ticker is ranked below a name substring")
        let second=app.buttons["trade-product-SIM:Coinbase_Exchange:ETC-USD"];try reveal(second,in:app);second.tap()
        try waitUntil("Second result could not be selected after keyboard scrolling"){(try? self.state(app)["tradeProduct"] as? String)=="SIM:Coinbase_Exchange:ETC-USD"}
        let after=try state(app);try check((after["watchlist"] as? [String])?.isEmpty==true,"Scroll accidentally toggled a favorite")
        try check((after["orders"] as? [String])?.isEmpty==true,"Search result selection sent an order")
        capture("FLOW keyboard second result scrolls and selects with favorites unchanged")
    }
    func testOrderKindWholeRowOpensRepeatedlyWhileChartLoadsBehindModal()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let baseline=try state(app);app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        try check(app.navigationBars["模擬下單"].waitForExistence(timeout:5),"Order form missing")
        for label in ["市價","限價","市價","限價","市價","限價"]{
            let kind=app.buttons["orderKind"];try check(kind.isHittable,"Order kind row is not reachable")
            kind.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
            let option=app.buttons[label];try check(option.waitForExistence(timeout:3),"Whole-row order menu tap did not present "+label);option.tap()
            try check(app.navigationBars["模擬下單"].exists,"Menu changed page or dismissed order form")
        }
        let after=try state(app);try check((after["orders"] as? [String])?.isEmpty==true && (after["cash"] as? [String:String])==(baseline["cash"] as? [String:String]),"Order type changes submitted or moved funds")
        capture("FLOW repeated order type row taps remain in exact unsent form")
    }
    func testVerticalDragInsideRenderedInlineChartScrollsTheProductPage()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        app.tabBars.buttons["交易"].tap();let chart=app.webViews["inlineChartWeb"].firstMatch
        try check(chart.waitForExistence(timeout:10),"Inline chart missing");try reveal(chart,in:app)
        try waitUntil("Scroll case has no actual rendered chart",timeout:10){((try? self.state(app)["chartRendered"] as? [String:Int])?["inline"] ?? 0)>0}
        let frame=chart.frame,baseline=try state(app);capture("FLOW chart fully visible before vertical page drag")
        let origin=app.coordinate(withNormalizedOffset:.zero),x=frame.midX,y=frame.midY
        origin.withOffset(CGVector(dx:x,dy:y)).press(forDuration:0.1,thenDragTo:origin.withOffset(CGVector(dx:x,dy:y-120)),withVelocity:.slow,thenHoldForDuration:0.1)
        try check(chart.frame.minY<frame.minY-40,"Inline chart consumed vertical page drag")
        let after=try state(app);try check(after["selected"] as? String==baseline["selected"] as? String,"Chart page drag changed product")
        try check((after["orders"] as? [String])?.isEmpty==true && (after["cash"] as? [String:String])==(baseline["cash"] as? [String:String]),"Chart drag changed account")
        capture("FLOW vertical chart gesture scrolls page without changing product or account")
    }
    func testUnsentTradeDraftAndIdentitySurviveColdRelaunch()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let before=try state(app);app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);quantity.tap();quantity.typeText(XCUIKeyboardKey.delete.rawValue+"7")
        app.buttons["完成"].tap();try waitUntil("Draft not retained before relaunch"){(try? self.state(app)["tradeDraftQuantity"] as? String)=="7"}
        let saved=try state(app);XCUIDevice.shared.press(.home);app.activate();app.terminate();app.launch()
        try check(app.tabBars.buttons["交易"].waitForExistence(timeout:30),"Draft restart failed")
        app.tabBars.buttons["交易"].tap();let restored=try state(app)
        try check(restored["tradeProduct"] as? String==saved["tradeProduct"] as? String && restored["tradeSide"] as? String==saved["tradeSide"] as? String,"Restart changed draft identity or side")
        try check(restored["tradeDraftQuantity"] as? String=="7","Restart lost unsubmitted editor")
        app.buttons["openOrder"].tap();try check(app.textFields["orderQuantity"].value as? String=="7","Restored editor did not use saved fields")
        try check((restored["cash"] as? [String:String])==(before["cash"] as? [String:String]) && (restored["orders"] as? [String])?.isEmpty==true,"Unsent restart changed funds or submitted")
        capture("FLOW cold relaunch restored exact product side and unsent fields")
    }
    func testRapidOfflineRefreshLeavesWorldAndFormUnchanged()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        app.tabBars.buttons["交易"].tap();let refresh=app.buttons["refreshMarketQuotes"];try reveal(refresh,in:app)
        let before=try state(app);rapid(refresh)
        let after=try state(app)
        try check((before["quotes"] as? [String:[String:String]])==(after["quotes"] as? [String:[String:String]]),"B refresh regenerated prices")
        try check((before["time"] as? NSNumber)==(after["time"] as? NSNumber),"B refresh advanced simulation time")
        try check((before["cash"] as? [String:String])==(after["cash"] as? [String:String]),"Refresh changed money")
        try check(before["tradeProduct"] as? String==after["tradeProduct"] as? String && before["tradeSide"] as? String==after["tradeSide"] as? String,"Refresh changed form identity or side")
        capture("FLOW rapid offline refresh unchanged clock prices account and form")
    }
}
