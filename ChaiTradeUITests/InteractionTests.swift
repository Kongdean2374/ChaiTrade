import XCTest

@MainActor final class InteractionTests:IsolatedUITestCase {
    func testRapidJournalSavePersistsExactlyOneEntry()throws{
        let app=launchClean(fixture:true,flags:["--uitest-contention"]);defer{capture("final")};try ready(app);try journal(app)
        let text=app.textViews["journalText"];text.tap();text.typeText("Rapid journal unique draft")
        let save=app.buttons["保存日誌"];try reveal(save,in:app);rapid(save,count:5)
        try waitUntil("Journal save did not finish"){(try? self.state(app)["journals"] as? [[String:String]])?.count ?? 0 > 0}
        let s=try state(app),entries=s["journals"] as? [[String:String]] ?? []
        try check(entries.count==1,"Rapid save duplicated journal: \(entries.count)")
        try check(entries.first?["text"]=="Rapid journal unique draft","Journal text changed")
        app.buttons["完成"].tap();app.terminate();app.launch()
        try check(app.tabBars.buttons["資產"].waitForExistence(timeout:30),"Relaunch failed")
        try check((try state(app)["journals"] as? [[String:String]])==entries,"Journal not persisted exactly once")
    }
    func testRapidOrderConfirmationAndCancelDebitExactlyOnce()throws{
        let app=launchClean(fixture:true);defer{capture("final")};try ready(app)
        let initial=try XCTUnwrap((try state(app)["cash"] as? [String:String])?["TWD"])
        try marketOrder(app);let submit=app.buttons["submitOrder"];try reveal(submit,in:app);rapid(submit)
        try check(app.buttons["確認送出"].waitForExistence(timeout:5),"Confirmation missing");app.buttons["取消"].tap()
        try check((try state(app)["fills"] as? [[String:String]])?.isEmpty==true,"Cancelled confirmation created fill")
        try check((try state(app)["cash"] as? [String:String])?["TWD"]==initial,"Cancelled order changed cash")
        submit.tap();let confirm=app.buttons["確認送出"];try check(confirm.waitForExistence(timeout:5),"Second confirmation missing");rapid(confirm,count:5)
        try waitUntil("Order did not settle"){app.tabBars.buttons["委託"].isHittable}
        let s=try state(app),fills=s["fills"] as? [[String:String]] ?? []
        try check(fills.count==1,"Rapid order produced \(fills.count) fills")
        try check((s["orders"] as? [String])?.count==1,"Rapid order created multiple requests")
        let f=try XCTUnwrap(fills.first)
        let cost=number(f["price"]!).multiplying(by:number(f["quantity"]!)).multiplying(by:number(f["multiplier"]!)).adding(number(f["fee"]!)).adding(number(f["tax"]!))
        let expected=number(initial).subtracting(cost)
        try check(number((s["cash"] as? [String:String])?["TWD"] ?? "NaN")==expected,"Cash was not deducted exactly once")
        let cash=s["fillCash"] as? [[String:String]] ?? []
        let debit=cash.reduce(NSDecimalNumber.zero){$0.adding(number($1["amount"]!))}
        try check(debit==cost.multiplying(by:NSDecimalNumber(value:-1)),"Fill ledger cash does not reconcile")
        app.terminate();app.launch();try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Relaunch failed")
        try check((try state(app)["fills"] as? [[String:String]])==fills,"Relaunch changed fills")
        try check(number((try state(app)["cash"] as? [String:String])?["TWD"] ?? "NaN")==expected,"Relaunch changed cash")
    }
    func testRapidTabsReselectAndFavoritesPersist()throws{
        let app=launchClean(fixture:true,flags:["--uitest-contention"]);defer{capture("final")};try ready(app)
        app.tabBars.buttons["交易"].tap();let watch=app.buttons["toggleWatch"];try check(watch.waitForExistence(timeout:5),"Favorite control missing");rapid(watch,count:4)
        // Four distinct toggle intents must end at the initial state, even while persistence is busy.
        try waitUntil("Four favorite toggles did not settle",timeout:6){(try? self.state(app)["operations"] as? Int)==0}
        try check(try state(app)["mutationStarts"] as? Int==4,"Rapid test did not dispatch four favorite intents")
        try check((try state(app)["watchlist"] as? [String])?.isEmpty==true,"Favorite toggles lost updates")
        watch.tap();try waitUntil("Favorite add missing"){watch.value as? String=="已加入"}
        for name in ["行情","行情","資產","總覽","交易","交易","委託","行情","交易"]{app.tabBars.buttons[name].tap()}
        try check(app.buttons["toggleWatch"].value as? String=="已加入","Tab switching lost favorite")
        let expected=try XCTUnwrap(try state(app)["watchlist"] as? [String]);try check(expected.count==1,"Unexpected favorite count")
        app.terminate();app.launch();try check(app.tabBars.buttons["行情"].waitForExistence(timeout:30),"Relaunch failed")
        try check((try state(app)["watchlist"] as? [String])==expected,"Favorite not durable")
    }
    func testBackNavigationSheetCancelSwipeAndKeyboard()throws{
        let app=launchClean(fixture:true);defer{capture("final")};try ready(app)
        app.tabBars.buttons["資產"].tap();let tools=app.buttons["帳務、交割與市場事件"];try reveal(tools,in:app);tools.tap()
        app.buttons["估值匯率與來源"].tap();try check(app.navigationBars["估值匯率"].waitForExistence(timeout:5),"Nested navigation missing")
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.coordinate(withNormalizedOffset:CGVector(dx:0.01,dy:0.5)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)))
        try check(app.navigationBars["資產"].waitForExistence(timeout:5),"Interactive back failed")
        try journal(app);let editor=app.textViews["journalText"];editor.tap();editor.typeText("Unsaved cancelled draft")
        try check(app.keyboards.firstMatch.exists,"Keyboard did not open")
        let save=app.buttons["保存日誌"];try reveal(save,in:app);try check(save.isHittable,"Keyboard blocks journal save")
        app.buttons["完成"].tap();try check((try state(app)["journals"] as? [[String:String]])?.isEmpty==true,"Closing journal saved an unconfirmed draft")
        try journal(app);try check((app.textViews["journalText"].value as? String)?.isEmpty==true,"Dismissed draft leaked into new sheet")
        app.navigationBars["交易日誌"].swipeDown();try check(app.tabBars.buttons["資產"].waitForExistence(timeout:5),"Swipe-dismiss did not close sheet")
        try marketOrder(app);let quantity=app.textFields["orderQuantity"];quantity.tap();quantity.typeText("0")
        let submit=app.buttons["submitOrder"];try reveal(submit,in:app);try check(submit.isHittable,"Keyboard blocks order submit")
        app.navigationBars["模擬下單"].swipeDown();try check(app.tabBars.buttons["交易"].waitForExistence(timeout:5),"Order sheet did not dismiss")
        try check((try state(app)["orders"] as? [String])?.isEmpty==true,"Dismissed order mutated account")
        try check((try state(app)["journals"] as? [[String:String]])?.isEmpty==true,"Cancelled journal mutated account")
    }
    func testCatchupBlocksAlreadyPresentedOrderAndCanPauseResume()throws{
        let app=launchClean(fixture:true,flags:["--uitest-controlled-catchup"]);defer{capture("final")};try ready(app);try marketOrder(app)
        let begin=app.buttons["uiTestBeginCatchup"];try check(begin.exists,"Controlled catchup button missing");begin.tap()
        try waitUntil("Actual catchup never started"){(try? self.state(app)["catchup"] as? Bool)==true}
        capture("Catchup running with order sheet already open")
        let submit=app.buttons["submitOrder"];for _ in 0..<7 where !submit.exists{app.swipeUp()};try check(submit.exists,"Order submit missing")
        try check(!submit.isEnabled,"Order sheet remains enabled during catchup")
        app.buttons["完成"].tap()
        let pause=app.buttons["暫停補算"];try check(pause.waitForExistence(timeout:5),"Cannot pause catchup");rapid(pause)
        try check(app.buttons["從檢查點繼續處理"].waitForExistence(timeout:5),"Paused checkpoint missing")
        let paused=try state(app);try check(paused["pendingCatchup"] as? Bool==true,"Pause discarded target")
        try check((paused["orders"] as? [String])?.isEmpty==true,"Catchup allowed order mutation")
        rapid(app.buttons["從檢查點繼續處理"])
        try waitUntil("Catchup did not finish from checkpoint",timeout:35){(try? self.state(app)["pendingCatchup"] as? Bool)==false}
        let complete=try state(app);try check((complete["orders"] as? [String])?.isEmpty==true,"Catchup replay created orders")
        try check((complete["fills"] as? [[String:String]])?.isEmpty==true,"Catchup replay created fills")
        try check(complete["catchupNotices"] as? Int==1,"Concurrent resume completed catchup more than once")
        try check((complete["time"] as? Int64 ?? 0)>(paused["time"] as? Int64 ?? 0),"Catchup did not advance")
    }
}
