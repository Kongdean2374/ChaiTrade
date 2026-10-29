import XCTest

@MainActor final class ProductVisualTests:IsolatedUITestCase{
    private func start(_ app:XCUIApplication,theme:String,large:Bool)throws{
        let button=app.buttons["startTrading"];try check(button.waitForExistence(timeout:15) && button.isHittable,"Onboarding start is not reachable at this screen/font size")
        capture("VISUAL onboarding "+theme+(large ? " accessibility3":" standard"),includeHierarchy:false);button.tap()
        try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Fresh visual account did not load")
        let s=try state(app);try check(s["session"] as? String==session,"Visual case inherited another session")
        try check((s["orders"] as? [String])?.isEmpty==true && (s["fills"] as? [[String:String]])?.isEmpty==true,"Visual case inherited transactions")
        try check(s["visualTheme"] as? String==theme,"Requested theme was not actually applied")
        if large{try check(s["visualType"] as? String=="accessibility3","Accessibility text size was not actually applied")}
    }
    func testLightHomeAndChineseSearchRemainReachable()throws{
        let app=launchClean(flags:["--uitest-light"]);defer{finish()};try start(app,theme:"light",large:false)
        capture("AFTER VISUAL light home top")
        let bottom=app.staticTexts["homeBottom"];try reveal(bottom,in:app);try check(bottom.isHittable,"Light home bottom blocked");capture("AFTER VISUAL light home bottom")
        app.tabBars.buttons["行情"].tap();let search=app.textFields["marketSearch"];search.tap();search.typeText("台積電")
        let item=app.buttons["market-SIM:TWSE:2330"];try check(item.waitForExistence(timeout:5),"Chinese product search failed with keyboard present")
        capture("AFTER VISUAL Chinese search keyboard");try reveal(item,in:app)
        capture("AFTER VISUAL fully visible Chinese search result before selection");item.tap()
        try check(app.navigationBars["商品詳情"].waitForExistence(timeout:5),"Tapping a completely visible Chinese result did not enter market detail")
        try check(app.buttons["openOrder"].waitForExistence(timeout:10),"Light product buy action missing")
        capture("AFTER VISUAL light stock detail")
    }
    func testDarkLargeTextOrderKeyboardCancelHasNoSideEffects()throws{
        let app=launchClean(flags:["--uitest-dark","--uitest-large-type"]);defer{finish()};try start(app,theme:"dark",large:true)
        app.tabBars.buttons["交易"].tap();let open=app.buttons["openOrder"];try reveal(open,in:app)
        capture("VISUAL before order sheet tap");open.tap();capture("VISUAL after order sheet tap")
        let quantity=app.textFields["orderQuantity"];try reveal(quantity,in:app);quantity.tap()
        try check(try state(app)["visualType"] as? String=="accessibility3","Order sheet did not inherit accessibility text size")
        capture("AFTER VISUAL dark accessibility order keyboard")
        let submit=app.buttons["submitOrder"];try reveal(submit,in:app);try check(submit.isHittable,"Keyboard covers order review at large text size")
        capture("AFTER VISUAL dark accessibility order bottom")
        let cancel=app.navigationBars["模擬下單"].buttons["完成"].firstMatch
        try check(cancel.isHittable,"Order navigation cancel is not reachable above the keyboard");cancel.tap()
        // Retained e467da0 failure read the dismissing bar once, then its actual
        // failure PNG/tree already showed Trade with the sheet and keyboard gone.
        // Wait for that same presentation to finish, without another tap or any
        // change to the original 120-second case/financial checks.
        try waitUntil("Order cancel left a sheet or blocked the trade tab",timeout:5){
            !app.navigationBars["模擬下單"].exists && app.tabBars.buttons["交易"].isHittable
        }
        let s=try state(app);try check((s["orders"] as? [String])?.isEmpty==true && (s["fills"] as? [[String:String]])?.isEmpty==true,"Canceled visual order changed account")
        app.tabBars.buttons["資產"].tap();try check(app.navigationBars["資產"].exists,"Cancel blocked Tab switching")
    }
    func testDarkLargeTextAssetsAndSettingsScrollToBottom()throws{
        let app=launchClean(flags:["--uitest-dark","--uitest-large-type"]);var completed=false;defer{finish(includeHierarchy:!completed)};try start(app,theme:"dark",large:true)
        let before=try state(app)
        // Retained cb11e5c reached and closed both pages before120s, then
        // crossed the unchanged deadline while collecting another full AX tree.
        // Keep every native gesture, PNG and hit test; failure capture still
        // includes the complete hierarchy. Successful screenshots need no
        // repeated traversal of the same125-product account payload.
        app.tabBars.buttons["資產"].tap();capture("AFTER VISUAL dark accessibility assets",includeHierarchy:false)
        let bottom=app.staticTexts["portfolioBottom"];try reveal(bottom,in:app);try check(bottom.isHittable,"Large text asset bottom is not reachable");capture("AFTER VISUAL dark accessibility assets bottom",includeHierarchy:false)
        app.tabBars.buttons["總覽"].tap();app.buttons["設定"].tap()
        let diagnostic=app.buttons["進階診斷"];try reveal(diagnostic,in:app);try check(diagnostic.isHittable,"Large text settings final group is blocked")
        capture("AFTER VISUAL dark accessibility settings bottom",includeHierarchy:false)
        app.buttons["完成"].tap();try check(app.tabBars.buttons["總覽"].isHittable,"Closing settings left an overlay")
        let after=try state(app)
        try check((after["mode"] as? String)==(before["mode"] as? String),"Visual navigation changed the account mode")
        try check((after["cash"] as? [String:String])==(before["cash"] as? [String:String]),"Visual navigation changed funds")
        try check((after["orders"] as? [String])==(before["orders"] as? [String]),"Visual navigation created orders")
        try check((after["fills"] as? [[String:String]])==(before["fills"] as? [[String:String]]),"Visual navigation changed fills")
        try check((after["watchlist"] as? [String])==(before["watchlist"] as? [String]),"Visual navigation changed favorites")
        try check(after["visualType"] as? String=="accessibility3" && after["visualTheme"] as? String=="dark","Final screen lost requested text size or theme")
        completed=true
    }
    func testLongChineseJournalAtLargeTextPreservesContentOnce()throws{
        let app=launchClean(flags:["--uitest-dark","--uitest-large-type"]);defer{finish()};try start(app,theme:"dark",large:true)
        try journal(app)
        try check(try state(app)["visualType"] as? String=="accessibility3","Journal sheet did not inherit accessibility text size")
        let text="這是一段較長的中文交易日誌，用來驗證小螢幕與大字體的鍵盤、捲動及內容保存。觀察市場變化後，再記錄風險、進出場理由與後續檢討。"
        let editor=app.textViews["journalText"];editor.tap();editor.typeText(text)
        try check(editor.value as? String==text,"Long Chinese input differs before saving")
        capture("AFTER VISUAL long Chinese journal keyboard")
        let save=app.buttons["saveJournal"];try reveal(save,in:app);save.tap()
        try waitUntil("Long Chinese journal was not saved exactly once"){
            guard let journals=try? self.state(app)["journals"] as? [[String:String]] else{return false}
            return journals.count==1 && journals.first?["text"]==text
        }
        capture("AFTER VISUAL long Chinese journal saved")
        app.buttons["完成"].tap();try check(app.tabBars.buttons["資產"].isHittable,"Journal close left keyboard over navigation")
    }

    private func verifyTradePicker(theme:String,large:Bool)throws{
        let app=launchClean(fixture:true,flags:["--uitest-full-catalog",theme=="dark" ? "--uitest-dark":"--uitest-light"]+(large ? ["--uitest-large-type"]:[]));defer{finish()};try ready(app)
        let before=try state(app);try check(before["visualTheme"] as? String==theme,"Picker requested theme missing")
        if large{try check(before["visualType"] as? String=="accessibility3","Picker large font not active")}
        app.tabBars.buttons["交易"].tap();let choose=app.buttons["tradeProductPicker"];try reveal(choose,in:app);choose.tap()
        let search=app.textFields["tradePickerSearch"];try reveal(search,in:app);search.tap();search.typeText("元大台灣")
        capture("AFTER VISUAL "+theme+" trade picker Chinese keyboard")
        let done=app.buttons["完成商品搜尋"];try check(done.isHittable,"Trade picker cannot dismiss search keyboard");done.tap()
        let filters=app.buttons["tradePickerFilters"];try reveal(filters,in:app,identifier:"tradePickerFilters");filters.tap()
        let clear=app.buttons["tradePickerClear"];try reveal(clear,in:app,identifier:"tradePickerClear");try check(clear.isHittable,"Picker clear inaccessible with expanded filters")
        capture("AFTER VISUAL "+theme+" picker filters and safe area");clear.tap()
        app.buttons["取消"].tap();try check(app.tabBars.buttons["交易"].isHittable,"Picker cancel traps tab bar")
        let after=try state(app);try check((before["cash"] as? [String:String])==(after["cash"] as? [String:String]),"Picker visual case changed funds")
        try check((after["orders"] as? [String])?.isEmpty==true,"Picker visual case sent an order")
    }
    func testLightTradePickerChineseKeyboardAndFilters()throws{try verifyTradePicker(theme:"light",large:false)}
    func testDarkLargeTradePickerChineseKeyboardAndFilters()throws{try verifyTradePicker(theme:"dark",large:true)}

}
