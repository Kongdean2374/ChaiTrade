import XCTest

@MainActor final class NavigationFlowTests:IsolatedUITestCase{
    private func verifyBrowsingOnly(_ id:String,query:String,crypto:Bool)throws{
        let app=launchClean();var completed=false;defer{finish(includeHierarchy:!completed)}
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh navigation account missing");start.tap()
        try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Navigation account failed to load")
        let initial=try state(app)
        try check(initial["session"] as? String==session,"Navigation test reused another case")
        for key in ["orders","fills","journals","watchlist"]{try check((initial[key] as? [Any])?.isEmpty==true,"Navigation case inherited "+key)}
        app.tabBars.buttons["行情"].tap();if crypto{app.buttons["marketCrypto"].tap()}
        let search=app.textFields["marketSearch"]
        let hint=search.placeholderValue ?? ""
        try check(crypto ? hint.contains("BTC") && hint.contains("ETH") && !hint.contains("2330"):hint.contains("2330") && hint.contains("0050") && !hint.contains("BTC") && !hint.contains("ETH"),"Search guidance belongs to another market")
        search.tap();search.typeText(query)
        let product=app.buttons["market-"+id];try check(product.waitForExistence(timeout:5),"Exact product is missing: "+id);product.tap()
        let viewed=try state(app)
        try check(viewed["tab"] as? Int==1,"Browsing "+query+" silently switched from markets to trade")
        try check(app.tabBars.buttons["行情"].isSelected,"Product detail does not belong to the market tab")
        try check(viewed["selected"] as? String==id,"Detail used another venue or asset identity")
        try check(!app.navigationBars["模擬下單"].exists,"Viewing a product opened an order form")
        try check((viewed["cash"] as? [String:String])==(initial["cash"] as? [String:String]),"Browsing moved account funds")
        try check((viewed["orders"] as? [Any])?.isEmpty==true && (viewed["fills"] as? [Any])?.isEmpty==true,"Browsing created an order")
        capture("FLOW markets-only detail "+query,includeHierarchy:false,snapshot:viewed)
        app.navigationBars.buttons.element(boundBy:0).tap()
        try check(app.textFields["marketSearch"].value as? String==query,"Back reset market search")
        try check(try state(app)["quoteFocus"] as? String=="","Back retained an invisible detail subscription")
        completed=true
    }
    func test2330DetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:TWSE:2330",query:"2330",crypto:false)}
    func testBTCDetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:Coinbase_Exchange:BTC-USD",query:"BTC",crypto:true)}
    func testETHDetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:Coinbase_Exchange:ETH-USD",query:"ETH",crypto:true)}
    func testEditingSearchDuringBrowsingWritePersistsLatestValueAfterColdRelaunch()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog","--uitest-browsing-write-barrier"]);defer{finish()};try ready(app)
        let initial=try state(app)
        app.tabBars.buttons["行情"].tap();let search=app.textFields["marketSearch"];search.tap();search.typeText("2330")
        try waitUntil("Controlled browsing write never began",timeout:5){
            guard let s=try? self.state(app) else{return false}
            return s["browsingWriteBarrierStarted"] as? Bool==true && s["browsingSaving"] as? Bool==true
        }
        // A real keystroke overlaps the pending SQLite write. It must only
        // replace the debounce timer, never cancel the writer's transaction.
        search.typeText(XCUIKeyboardKey.delete.rawValue)
        try waitUntil("Latest interleaved search did not finish saving",timeout:10){
            guard let s=try? self.state(app) else{return false}
            return s["search"] as? String=="233" && s["browsingWriteBarrierEdited"] as? Bool==true && s["browsingSaving"] as? Bool==false && (s["browsingPending"] as? [String])?.isEmpty==true
        }
        let saved=try state(app)
        try check(saved["notice"] as? String != "瀏覽偏好尚未保存，請重試","Normal interleaved browsing left a false save warning")
        capture("FLOW interleaved browsing writer saves latest search without cancellation warning",includeHierarchy:false,snapshot:saved)
        app.terminate();app.launch();try ready(app);app.tabBars.buttons["行情"].tap()
        try check(app.textFields["marketSearch"].value as? String=="233","Cold relaunch lost the latest interleaved search")
        let restored=try state(app)
        try check(restored["market"] as? String=="stocks" && (restored["mode"] as? String)==(initial["mode"] as? String),"Browsing write changed market or account")
        try check(restored["session"] as? String==session,"Browsing relaunch changed isolated session")
        try check((restored["cash"] as? [String:String])==(initial["cash"] as? [String:String]),"Browsing write changed cash")
        try check((restored["time"] as? Int64)==(initial["time"] as? Int64),"Browsing write advanced offline time")
        for key in ["orders","fills","journals","watchlist"]{try check((restored[key] as? [Any])?.isEmpty==true,"Browsing write changed "+key)}
        try check(restored["notice"] as? String != "瀏覽偏好尚未保存，請重試","Relaunch retained a browsing failure warning")
        capture("FLOW latest browsing search survives cold relaunch with account unchanged",includeHierarchy:false,snapshot:restored)
    }
}

@MainActor final class TradingHandoffTests:IsolatedUITestCase{
    @discardableResult private func onboardUSD(_ app:XCUIApplication)throws->[String:Any]{
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh onboarding missing")
        let currency=app.buttons["baseCurrency"];try reveal(currency,in:app,identifier:"baseCurrency");currency.tap();app.buttons["USD"].tap();try reveal(start,in:app,identifier:"startTrading");start.tap()
        try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Clean account failed")
        let s=try state(app);for key in ["orders","fills","journals","watchlist"]{try check((s[key] as? [Any])?.isEmpty==true,"Inherited "+key)}
        return s
    }
    private func detail(_ app:XCUIApplication,_ symbol:String)throws{
        app.tabBars.buttons["行情"].tap();app.buttons["marketCrypto"].tap()
        let search=app.textFields["marketSearch"];try check(search.waitForExistence(timeout:5),"Market list not restored");search.tap();search.typeText(symbol)
        app.buttons["market-SIM:Coinbase_Exchange:"+symbol+"-USD"].tap()
        try check(app.tabBars.buttons["行情"].isSelected,"Browsing changed tab")
        capture("FLOW list to "+symbol+" detail stays in markets",includeHierarchy:false)
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
        let app=launchClean();var completed=false;defer{finish(includeHierarchy:!completed)}
        let initial=try onboardUSD(app);try detail(app,"BTC")
        app.buttons["openOrder"].tap();try check(app.navigationBars["模擬下單"].waitForExistence(timeout:5),"Buy handoff failed")
        let handed=try state(app)
        try check((handed["orders"] as? [String])?.isEmpty==true,"Buy handoff submitted automatically")
        try check(handed["tab"] as? Int==2 && handed["tradeProduct"] as? String=="SIM:Coinbase_Exchange:BTC-USD" && handed["tradeSide"] as? String=="buy","BTC buy handoff changed exact product, side or tab")
        try check(app.staticTexts["orderPriceLabel"].label=="限價（USD）" && app.staticTexts["orderPriceLabel"].isHittable,"Filled BTC price lost its visible currency label")
        try check(app.staticTexts["orderQuantityLabel"].label=="數量（BTC）" && app.staticTexts["orderQuantityLabel"].isHittable,"Filled BTC quantity lost its visible coin unit")
        capture("FLOW explicit buy switches to trade form",includeHierarchy:false,snapshot:handed);app.buttons["完成"].tap()
        let picker=app.buttons["tradeProductPicker"];try reveal(picker,in:app,identifier:"tradeProductPicker");picker.tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("ETH")
        let eth=app.buttons["trade-product-SIM:Coinbase_Exchange:ETH-USD"];try reveal(eth,in:app,identifier:"trade-product-SIM:Coinbase_Exchange:ETH-USD");eth.tap()
        var picked:[String:Any]?
        try waitUntil("Independent trade picker failed"){
            picked=try? self.state(app)
            return picked?["tradeProduct"] as? String=="SIM:Coinbase_Exchange:ETH-USD"
        }
        capture("FLOW independent trade picker changed BTC to ETH",includeHierarchy:false,snapshot:picked)
        let open=app.buttons["openOrder"];try check(open.waitForExistence(timeout:5),"New ETH quote did not enable an explicit order entry");open.tap();let size=app.textFields["orderQuantity"];try reveal(size,in:app,identifier:"orderQuantity")
        try check(size.value as? String=="0.001","Another product quantity leaked into ETH")
        try check(app.staticTexts["orderQuantityLabel"].label=="數量（ETH）" && app.staticTexts["orderQuantityLabel"].isHittable,"Changing BTC to ETH left a missing or wrong visible quantity unit")
        size.tap();size.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:8)+"0.01")
        app.buttons["orderKind"].tap();app.buttons["市價"].tap()
        let submit=app.buttons["submitOrder"];try reveal(submit,in:app,identifier:"submitOrder");submit.tap()
        try check(app.alerts["確認本機模擬委託"].waitForExistence(timeout:5),"No order review")
        let pending=try state(app)
        try check((pending["orders"] as? [String])?.isEmpty==true && (pending["fills"] as? [[String:String]])?.isEmpty==true,"Review submitted before explicit confirmation")
        try check((pending["cash"] as? [String:String])==(initial["cash"] as? [String:String]),"Review moved funds before confirmation")
        capture("FLOW exact ETH quantity and local account before confirm",includeHierarchy:false,snapshot:pending);rapid(app.buttons["確認送出"])
        try waitUntil("Confirmed simulation did not return receipt",timeout:10){app.navigationBars["委託與成交"].exists}
        let s=try state(app),intents=try XCTUnwrap(s["orderIntents"] as? [[String:String]])
        try check(intents.count==1 && intents[0]["instrument"]=="SIM:Coinbase_Exchange:ETH-USD" && intents[0]["side"]=="buy","One intent used wrong product/side or duplicated")
        try check((s["fills"] as? [[String:String]])?.count==1,"Simulation filled more than once")
        try check((s["positions"] as? [String:String])?["SIM:Coinbase_Exchange:ETH-USD"]=="0.01","Simulation position wrong")
        let fill=try XCTUnwrap((s["fills"] as? [[String:String]])?.first)
        let price=number(try XCTUnwrap(fill["price"])),quantity=number(try XCTUnwrap(fill["quantity"]))
        let fee=number(try XCTUnwrap(fill["fee"])),tax=number(try XCTUnwrap(fill["tax"]))
        let initialCash=number(try XCTUnwrap((initial["cash"] as? [String:String])?["USD"]))
        let actualCash=number(try XCTUnwrap((s["cash"] as? [String:String])?["USD"]))
        let expectedCash=initialCash.subtracting(price.multiplying(by:quantity).adding(fee).adding(tax))
        try check(actualCash==expectedCash,"One ETH intent must debit exact notional, fee and tax only once")
        capture("FLOW single local fill and receipt",includeHierarchy:false,snapshot:s)
        completed=true
    }
    func testNewDefaultLimitPricesFollowEachProductTickAndSubmitOnlyTheETHIntent()throws{
        let app=launchClean();defer{finish()};try onboardUSD(app);let baseline=try state(app);try detail(app,"BTC")
        app.buttons["openOrder"].tap();let btcPriceField=app.textFields["orderPrice"]
        try check(btcPriceField.waitForExistence(timeout:5),"New BTC limit price is missing")
        try waitUntil("Default BTC limit was not initialized to its legal tick",timeout:3){
            let value=btcPriceField.value as? String ?? ""
            return self.number(value).compare(NSDecimalNumber.zero) == .orderedDescending && (value.split(separator:".").dropFirst().first?.count ?? 0)<=2
        }
        let btcPrice=try XCTUnwrap(btcPriceField.value as? String)
        try check(number(btcPrice).compare(NSDecimalNumber.zero) == .orderedDescending && (btcPrice.split(separator:".").dropFirst().first?.count ?? 0)<=2,"Default BTC price violates its 0.01 tick")
        let prepared=try state(app)
        try check(app.buttons["orderKind"].value as? String=="限價" && (prepared["orders"] as? [String])?.isEmpty==true,"Preparing a limit order submitted automatically")
        capture("FLOW new BTC limit proposal fits its own tick without an order");app.buttons["完成"].tap()
        let picker=app.buttons["tradeProductPicker"];try reveal(picker,in:app);picker.tap()
        let search=app.textFields["tradePickerSearch"];search.tap();search.typeText("ETH")
        let eth=app.buttons["trade-product-SIM:Coinbase_Exchange:ETH-USD"];try reveal(eth,in:app);eth.tap()
        try waitUntil("Default-limit product switch failed"){(try? self.state(app)["tradeProduct"] as? String)=="SIM:Coinbase_Exchange:ETH-USD"}
        app.buttons["openOrder"].tap();let ethPriceField=app.textFields["orderPrice"]
        try check(ethPriceField.waitForExistence(timeout:5),"New ETH limit price is missing")
        try waitUntil("Default ETH limit was not initialized to its legal tick",timeout:3){
            let value=ethPriceField.value as? String ?? ""
            return self.number(value).compare(NSDecimalNumber.zero) == .orderedDescending && (value.split(separator:".").dropFirst().first?.count ?? 0)<=2
        }
        let ethPrice=try XCTUnwrap(ethPriceField.value as? String)
        try check(number(ethPrice).compare(NSDecimalNumber.zero) == .orderedDescending && (ethPrice.split(separator:".").dropFirst().first?.count ?? 0)<=2 && ethPrice != btcPrice,"ETH inherited an invalid or BTC limit price")
        let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);quantity.tap();quantity.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:8)+"0.01")
        try waitUntil("Limit quantity input was not delivered",timeout:3){quantity.value as? String=="0.01"}
        let before=try state(app);try check((before["orders"] as? [String])?.isEmpty==true && (before["cash"] as? [String:String])==(baseline["cash"] as? [String:String]),"Unsubmitted default limit moved funds or created an order")
        let submit=app.buttons["submitOrder"];try reveal(submit,in:app);submit.tap();app.buttons["確認送出"].tap()
        try waitUntil("The unchanged legal default ETH limit was rejected",timeout:10){app.navigationBars["委託與成交"].exists && !app.navigationBars["模擬下單"].exists}
        let after=try state(app),intents=try XCTUnwrap(after["orderIntents"] as? [[String:String]])
        try check(intents.count==1 && intents[0]["instrument"]=="SIM:Coinbase_Exchange:ETH-USD" && intents[0]["side"]=="buy" && intents[0]["kind"]=="limit" && intents[0]["price"]==ethPrice && intents[0]["quantity"]=="0.01","Limit order did not preserve the exact current product, side, type, price and quantity")
        try check(((after["fills"] as? [[String:String]])?.count ?? 0)<=1,"One limit intent produced duplicate fills")
        capture("FLOW exact ETH default limit accepted once; waiting is distinct from a fill")
    }
}

@MainActor final class TradeWorkspaceInteractionTests:IsolatedUITestCase{
    func testEarlyStockBoardTapAndSummaryRefreshKeepGeometryAndAccount()throws{
        let app=launchClean();var completed=false;defer{finish(includeHierarchy:!completed)}
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Fresh header-regression onboarding missing");start.tap()
        try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Fresh header-regression account missing")
        let before=try state(app);app.tabBars.buttons["行情"].tap()
        let product=app.buttons["market-SIM:TWSE:2330"];try check(product.waitForExistence(timeout:5),"2330 missing before early board tap");product.tap()
        let board=app.buttons["board-regular"],first=try board.snapshot().frame
        // One early real tap, without retrying until an eventual success.
        board.tap();try waitUntil("First visible whole-lot tap was lost",timeout:5){board.isSelected}
        let summary=app.otherElements["productSummaryMetrics"]
        try check(summary.waitForExistence(timeout:5),"Stable summary slot is missing")
        let refresh=app.buttons["refreshMarketQuotes"];try check(refresh.isHittable,"Detail refresh is not reachable");refresh.tap()
        try waitUntil("B detail refresh did not finish",timeout:5){refresh.isEnabled}
        let afterFrame=try board.snapshot().frame,after=try state(app)
        try check(abs(afterFrame.minY-first.minY)<1 && abs(afterFrame.height-first.height)<1,"Summary update moved the board after the tap target was located")
        try check(board.isSelected && (after["boardRequests"] as? [String])==["regular"],"Early board selection required multiple taps or lost its state")
        try check(after["tab"] as? Int==1 && after["selected"] as? String=="SIM:TWSE:2330","Header refresh changed market navigation or exact product")
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]) && (after["orders"] as? [String])?.isEmpty==true && (after["fills"] as? [[String:String]])?.isEmpty==true,"Header inspection or refresh submitted a trade or moved cash")
        capture("FLOW early stock board stays stationary through summary refresh",includeHierarchy:false,snapshot:after)
        completed=true
    }
    func testStockOrderTickTracksEditedLimitPriceWithoutSubmitting()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app)
        let before=try state(app);app.tabBars.buttons["交易"].tap()
        let board=app.buttons["整股（張）"];try reveal(board,in:app,identifier:"board-regular");board.tap()
        let open=app.buttons["openOrder"];try reveal(open,in:app,identifier:"openOrder");open.tap()
        let rules=app.staticTexts["orderTradingRules"]
        try check(rules.waitForExistence(timeout:5) && rules.label.contains("價格級距：0.1 TWD"),"Own2330quote band should be0.1TWD, not base0.01")
        capture("FLOW stock order current price band is 0.1 TWD",includeHierarchy:false)
        let price=app.textFields["orderPrice"];try reveal(price,in:app,identifier:"orderPrice")
        try check(app.staticTexts["orderPriceLabel"].label=="限價（TWD）" && app.staticTexts["orderPriceLabel"].isHittable,"Filled stock limit lost its visible TWD label")
        let old=try XCTUnwrap(price.value as? String);price.tap();price.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"1000")
        try waitUntil("Edited limit price was not delivered exactly",timeout:3){price.value as? String=="1000"}
        let keyboard=app.buttons["收起鍵盤"];try check(keyboard.isHittable,"Cannot dismiss keyboard while verifying own price band");keyboard.tap()
        try reveal(rules,in:app,identifier:"orderTradingRules")
        try check(rules.label.contains("價格級距：5 TWD"),"At1000TWD stock limit, displayed band should be5TWD without changing the quote")
        capture("FLOW stock limit 1000 updates displayed tick to 5 TWD without submitting",includeHierarchy:false)
        let quantityLabel=app.staticTexts["orderQuantityLabel"];try reveal(quantityLabel,in:app,identifier:"orderQuantityLabel")
        try check(quantityLabel.label=="數量（張）" && quantityLabel.isHittable,"Whole-lot stock quantity is missing its visible lot unit")
        app.navigationBars["模擬下單"].buttons["完成"].tap()
        try waitUntil("Tick inspection cancel left an overlay",timeout:5){!app.navigationBars["模擬下單"].exists && app.tabBars.buttons["交易"].isHittable}
        let after=try state(app)
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Inspecting tick bands changed cash")
        try check((after["orders"] as? [String])?.isEmpty==true && (after["fills"] as? [[String:String]])?.isEmpty==true,"Editing a tick reference submitted an order")
        try check(after["tradeProduct"] as? String=="SIM:TWSE:2330","Tick reference used another product identity")
    }
    func testOrderTypeChooserCancelAndSlideKeepTheExactUnsentDraft()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let before=try state(app);app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);let typed=(try XCTUnwrap(quantity.value as? String))+"0";quantity.tap();quantity.typeText("0")
        try waitUntil("Quantity input was not delivered intact",timeout:3){quantity.value as? String==typed}
        let kind=app.buttons["orderKind"],originalKind=kind.value as? String
        for attempt in 0..<2{
            try reveal(kind,in:app);kind.tap()
            let chooser=app.navigationBars["委託類型"];try check(chooser.waitForExistence(timeout:5),"Order type chooser missing")
            if attempt==0{app.buttons["取消選擇"].tap()}
            else{
                let start=chooser.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.25))
                let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.75))
                start.press(forDuration:0.05,thenDragTo:end,withVelocity:.fast,thenHoldForDuration:0.1)
            }
            try waitUntil("Canceling the type chooser dismissed or changed the order",timeout:8){
                !chooser.exists && app.navigationBars["模擬下單"].exists && kind.isHittable
            }
            try check(kind.value as? String==originalKind && quantity.value as? String==typed,"Type chooser cancellation changed the draft")
        }
        let after=try state(app)
        try check(after["tradeProduct"] as? String==before["tradeProduct"] as? String && after["tradeSide"] as? String==before["tradeSide"] as? String,"Type chooser cancellation changed product or direction")
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Type chooser cancellation moved cash")
        for key in ["orders","fills","journals","watchlist"]{try check((after[key] as? [Any])?.isEmpty==true,"Type chooser cancellation mutated "+key)}
        capture("FLOW order type chooser cancel and slide keep the exact unsent draft")
    }
    func testForegroundQuoteClockAdvancesAcrossTabsAndAppReactivation()throws{
        let app=launchClean();defer{finish()}
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Clock regression onboarding missing")
        app.buttons["A 真實行情"].tap();start.tap()
        try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Online clock account not ready")
        let before=try state(app),initial=before["marketClock"] as? Int64 ?? 0
        try waitUntil("Online foreground clock did not advance",timeout:6){
            guard let s=try? self.state(app),let clock=s["marketClock"] as? Int64 else{return false}
            return clock>initial+1 && abs(Int64(Date().timeIntervalSince1970)-clock)<=2
        }
        app.tabBars.buttons["行情"].tap();app.tabBars.buttons["總覽"].tap()
        let previous=try state(app)["marketClock"] as? Int64 ?? 0
        XCUIDevice.shared.press(.home);app.activate()
        try waitUntil("Online clock did not resume with the foreground scene",timeout:6){
            guard let s=try? self.state(app),let clock=s["marketClock"] as? Int64 else{return false}
            return s["foreground"] as? Bool==true && clock>previous+1 && abs(Int64(Date().timeIntervalSince1970)-clock)<=2
        }
        let after=try state(app)
        try check(after["mode"] as? String=="online" && (after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Foreground clock changed account or funds")
        for key in ["orders","fills","journals","watchlist"]{try check((after[key] as? [Any])?.isEmpty==true,"Foreground clock changed "+key)}
        capture("FLOW actual foreground quote clock after tabs and app reactivation")
    }
    func testOfflineAutomaticClockCanPauseAndResumeAfterAppReactivation()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let before=try state(app),initial=before["time"] as? Int64 ?? 0
        app.buttons["設定"].tap();app.buttons["離線模擬"].tap()
        let play=app.buttons["繼續模擬"];try reveal(play,in:app);play.tap()
        try waitUntil("Offline automatic time did not advance after play",timeout:12){
            guard let s=try? self.state(app) else{return false}
            return s["simulationPaused"] as? Bool==false && (s["time"] as? Int64 ?? 0)>initial
        }
        let pause=app.buttons["暫停模擬"];try reveal(pause,in:app);pause.tap()
        try waitUntil("Offline pause did not persist"){(try? self.state(app)["simulationPaused"] as? Bool)==true}
        let stopped=try state(app)["time"] as? Int64 ?? 0
        XCUIDevice.shared.press(.home);app.activate()
        try check(try state(app)["time"] as? Int64==stopped,"Paused offline time advanced during app reactivation")
        try reveal(play,in:app);play.tap()
        try waitUntil("Offline automatic time did not resume after reactivation",timeout:12){
            guard let snapshot=try? self.state(app),let time=snapshot["time"] as? Int64 else{return false}
            return time>stopped
        }
        try reveal(pause,in:app);pause.tap()
        let after=try state(app)
        try check(after["mode"] as? String=="offline" && (after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Offline clock changed account or cash")
        for key in ["orders","fills","journals","watchlist"]{try check((after[key] as? [Any])?.isEmpty==true,"Offline clock created "+key)}
        capture("FLOW offline automatic play pause and foreground resume without orders")
    }
    func testOrderSwipeWithKeyboardAndAcrossNavigationBarKeepsDraftAndAccount()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let before=try state(app)
        for attempt in 0..<2{
            try marketOrder(app)
            let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);quantity.tap();quantity.typeText("0")
            try check(app.keyboards.firstMatch.exists,"Order swipe regression did not open the keyboard")
            let typed=try XCTUnwrap(quantity.value as? String)
            capture("FLOW order keyboard before navigation swipe \(attempt+1)")
            let bar=app.navigationBars["模擬下單"]
            if attempt==0{bar.swipeDown()}
            else{bar.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.2)).press(forDuration:0.05,thenDragTo:bar.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:1.6)))}
            try waitUntil("A downward navigation drag with keyboard did not close the order sheet"){
                !app.navigationBars["模擬下單"].exists && app.tabBars.buttons["交易"].isHittable && !app.keyboards.firstMatch.exists
            }
            let after=try state(app)
            try check(after["tradeDraftQuantity"] as? String==typed,"Swipe silently discarded the unsubmitted trade draft")
            try check(after["tradeProduct"] as? String==before["tradeProduct"] as? String && after["tradeSide"] as? String==before["tradeSide"] as? String,"Swipe changed the product or side")
            try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Order swipe changed cash")
            for key in ["orders","fills","journals","watchlist"]{try check((after[key] as? [Any])?.isEmpty==true,"Order swipe changed "+key)}
            capture("FLOW navigation swipe closed order with preserved draft \(attempt+1)")
        }
    }
    func testMarketEmptySearchClearResetsVisibleQueryAndResultsWithoutChangingTrade()throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog"]);defer{finish()};try ready(app)
        let baseline=try state(app);app.tabBars.buttons["行情"].tap()
        let search=app.textFields["marketSearch"];search.tap();search.typeText("ZZZ_NOT_A_PRODUCT_2374")
        let finishSearch=app.buttons["完成搜尋"];try check(finishSearch.waitForExistence(timeout:5),"Market search keyboard toolbar missing");finishSearch.tap()
        try check(app.staticTexts["沒有符合的商品"].waitForExistence(timeout:5),"Impossible query did not show its specific empty state")
        capture("FLOW empty market results before clearing filters")
        let clear=app.buttons["清除篩選"];try reveal(clear,in:app);clear.tap()
        try waitUntil("Clear filters left the visible search or product results stale"){
            let value=search.value as? String ?? ""
            return (value.isEmpty || value==search.placeholderValue) && app.buttons["market-SIM:TWSE:2330"].exists
        }
        let after=try state(app)
        try check(after["search"] as? String=="","Clear filters did not persist an empty market query")
        try check(after["tradeProduct"] as? String==baseline["tradeProduct"] as? String && after["tradeSide"] as? String==baseline["tradeSide"] as? String,"Clearing browsing filters modified the trade workspace")
        try check((after["cash"] as? [String:String])==(baseline["cash"] as? [String:String]) && (after["orders"] as? [String])?.isEmpty==true && (after["watchlist"] as? [String])?.isEmpty==true,"Clearing filters mutated account data")
        capture("FLOW clear filters restores visible search and real stock results")
    }
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
        try waitUntil("Picker dismissal did not commit the exact BTC identity"){
            !app.textFields["tradePickerSearch"].exists && (try? self.state(app)["tradeProduct"] as? String)=="SIM:Coinbase_Exchange:BTC-USD"
        }
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
        let exact=app.buttons["trade-product-SIM:Coinbase_Exchange:ETH-USD"]
        let second=app.buttons["trade-product-SIM:Coinbase_Exchange:ETC-USD"]
        // Retained1.2.28 compared the preceding E/20-product presentation;
        // its next native tree already had ETH above ETC. Keep the original
        // first-row assertion and120s gate, but wait for this actual filter to
        // present, also checking physical order rather than tree order alone.
        try waitUntil("Exact ETH filtering has not finished presenting",timeout:5){
            guard search.value as? String=="ETH",rows.firstMatch.identifier=="trade-product-SIM:Coinbase_Exchange:ETH-USD",exact.exists,second.exists else{return false}
            let a=exact.frame,b=second.frame
            return !a.isNull && !a.isInfinite && !b.isNull && !b.isInfinite && a.height>0 && b.height>0 && a.minY.isFinite && b.minY.isFinite && a.maxY<=b.minY
        }
        try check(rows.firstMatch.identifier=="trade-product-SIM:Coinbase_Exchange:ETH-USD","Exact ETH ticker is ranked below a name substring")
        capture("FLOW settled exact ETH search ranks above ETC with keyboard",includeHierarchy:false)
        try reveal(second,in:app);second.tap()
        try waitUntil("Second result could not be selected after keyboard scrolling"){(try? self.state(app)["tradeProduct"] as? String)=="SIM:Coinbase_Exchange:ETC-USD"}
        let after=try state(app);try check((after["watchlist"] as? [String])?.isEmpty==true,"Scroll accidentally toggled a favorite")
        try check((after["orders"] as? [String])?.isEmpty==true,"Search result selection sent an order")
        capture("FLOW keyboard second result scrolls and selects with favorites unchanged")
    }
    func testOrderKindWholeRowOpensRepeatedlyWhileChartLoadsBehindModal()throws{
        let app=launchClean(fixture:true);defer{finish()};try ready(app)
        let baseline=try state(app);app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        try check(app.navigationBars["模擬下單"].waitForExistence(timeout:5),"Order form missing")
        let originalKind=app.buttons["orderKind"].value as? String
        app.buttons["orderKind"].tap();app.buttons["取消選擇"].tap()
        try waitUntil("Canceling order type selection changed the unsent form",timeout:3){
            !app.navigationBars["委託類型"].exists && app.buttons["orderKind"].isHittable && app.buttons["orderKind"].value as? String==originalKind
        }
        for label in ["市價","限價","市價","限價","市價","限價"]{
            let kind=app.buttons["orderKind"];try check(kind.isHittable,"Order kind row is not reachable")
            kind.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
            let option=app.buttons[label];try check(option.waitForExistence(timeout:3),"Whole-row order menu tap did not present "+label);option.tap()
            try waitUntil("Order type selection did not return the exact form",timeout:3){
                !app.navigationBars["委託類型"].exists && kind.isHittable && kind.value as? String==label
            }
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
        let app=launchClean(fixture:true,flags:["--uitest-trade-write-barrier"]);defer{finish()};try ready(app)
        let before=try state(app);app.tabBars.buttons["交易"].tap();app.buttons["openOrder"].tap()
        let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);quantity.tap();quantity.typeText(XCUIKeyboardKey.delete.rawValue+"3")
        try waitUntil("Controlled trade draft write never began",timeout:5){
            guard let s=try? self.state(app) else{return false}
            return s["tradeWriteBarrierStarted"] as? Bool==true && s["tradeSaving"] as? Bool==true
        }
        quantity.typeText(XCUIKeyboardKey.delete.rawValue+"1")
        try waitUntil("Returning to initial quantity left the previous edited draft",timeout:5){(try? self.state(app)["tradeDraftQuantity"] as? String)=="1"}
        quantity.typeText(XCUIKeyboardKey.delete.rawValue+"7")
        app.buttons["完成"].tap();try waitUntil("Draft not retained before relaunch"){(try? self.state(app)["tradeDraftQuantity"] as? String)=="7"}
        try waitUntil("Interleaved draft did not finish saving",timeout:10){
            guard let s=try? self.state(app) else{return false}
            return s["tradeWriteBarrierEdited"] as? Bool==true && s["tradeSaving"] as? Bool==false && s["tradePending"] as? Bool==false
        }
        try check(try state(app)["notice"] as? String != "交易草稿尚未保存，請稍後重試","Interleaved trade draft left a false cancellation warning")
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
