import XCTest

@MainActor final class ProductVisualTests:IsolatedUITestCase{
    private func start(_ app:XCUIApplication,theme:String,large:Bool)throws{
        let button=app.buttons["startTrading"];try check(button.waitForExistence(timeout:15) && button.isHittable,"Onboarding start is not reachable at this screen/font size")
        capture("VISUAL onboarding "+theme+(large ? " accessibility3":" standard"));button.tap()
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
        capture("AFTER VISUAL Chinese search keyboard");item.tap()
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
        app.buttons["完成"].firstMatch.tap()
        try check(!app.navigationBars["模擬下單"].exists,"Order cancel left a sheet")
        let s=try state(app);try check((s["orders"] as? [String])?.isEmpty==true && (s["fills"] as? [[String:String]])?.isEmpty==true,"Canceled visual order changed account")
        app.tabBars.buttons["資產"].tap();try check(app.navigationBars["資產"].exists,"Cancel blocked Tab switching")
    }
    func testDarkLargeTextAssetsAndSettingsScrollToBottom()throws{
        let app=launchClean(flags:["--uitest-dark","--uitest-large-type"]);defer{finish()};try start(app,theme:"dark",large:true)
        app.tabBars.buttons["資產"].tap();capture("AFTER VISUAL dark accessibility assets")
        let bottom=app.staticTexts["portfolioBottom"];try reveal(bottom,in:app);try check(bottom.isHittable,"Large text asset bottom is not reachable");capture("AFTER VISUAL dark accessibility assets bottom")
        app.tabBars.buttons["總覽"].tap();app.buttons["設定"].tap()
        let diagnostic=app.buttons["進階診斷"];try reveal(diagnostic,in:app);try check(diagnostic.isHittable,"Large text settings final group is blocked")
        capture("AFTER VISUAL dark accessibility settings bottom")
        app.buttons["完成"].tap();try check(app.tabBars.buttons["總覽"].isHittable,"Closing settings left an overlay")
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

}
