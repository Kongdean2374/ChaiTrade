import XCTest

/// Read-only page evidence complements the financial/interaction journeys; it never replaces them.
@MainActor final class ProductEvidenceTests:IsolatedUITestCase{
    private func pageCapture(_ stage:String){capture(stage,includeHierarchy:false)}
    private func start(_ app:XCUIApplication,online:Bool=false)throws{
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Evidence onboarding missing")
        if online{app.buttons["A 真實行情"].tap()};start.tap()
        try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Evidence account not ready")
        try check((try state(app))["session"] as? String==session,"Evidence inherited another account");capture("Clean page evidence baseline")
    }
    private func openSettings(_ app:XCUIApplication)throws{app.buttons["設定"].tap();try check(app.navigationBars["設定"].waitForExistence(timeout:5),"Settings sheet missing")}
    private func page(_ title:String,in app:XCUIApplication)throws{
        let button=app.buttons[title];try reveal(button,in:app);button.tap()
        try check(app.navigationBars[title].waitForExistence(timeout:5),"Evidence page missing: "+title)
        pageCapture("AFTER page "+title+" top");app.swipeUp();pageCapture("AFTER page "+title+" lower")
        app.navigationBars[title].buttons.element(boundBy:0).tap()
        try check(app.navigationBars["設定"].exists,"Evidence back lost settings")
    }
    private func unchanged(_ app:XCUIApplication)throws{
        let s=try state(app);try check((s["orders"] as? [String])?.isEmpty==true && (s["fills"] as? [[String:String]])?.isEmpty==true,"Read-only evidence changed trading history")
        try check((s["cash"] as? [String:String])==["TWD":"1000000"],"Read-only evidence changed capital")
        try check((s["positions"] as? [String:String])?.isEmpty==true,"Read-only evidence changed positions")
        for key in ["journals","watchlist"]{try check((s[key] as? [Any])?.isEmpty==true,"Read-only evidence changed "+key)}
    }
    func testSettingsAccountTradeAndOfflinePageEvidence()throws{
        let app=launchClean();defer{finish()};try start(app);try openSettings(app);pageCapture("AFTER settings first level")
        for title in ["模式與帳戶","交易偏好","離線模擬"]{try page(title,in:app)}
        try unchanged(app)
    }
    func testSettingsNotificationBackupAndDiagnosticsPageEvidence()throws{
        let app=launchClean();defer{finish()};try start(app);try openSettings(app)
        for title in ["外觀與通知","資料備份／還原","進階診斷"]{try page(title,in:app)}
        try unchanged(app)
    }
    func testOnlineConnectionWizardAndLegalScopePageEvidence()throws{
        let app=launchClean();defer{finish()};try start(app,online:true);try openSettings(app)
        app.buttons["settingsConnections"].tap();try check(app.navigationBars["行情連線"].waitForExistence(timeout:5),"Connection wizard missing");pageCapture("AFTER A connection wizard sources")
        for title in ["Coinbase Exchange","Fugle 台股","Alpaca（IEX）"]{
            let link=app.buttons.containing(.staticText,identifier:title).firstMatch;try reveal(link,in:app);link.tap()
            try check(app.navigationBars[title].waitForExistence(timeout:5),"Provider page missing "+title);pageCapture("AFTER A source "+title)
            app.navigationBars[title].buttons.element(boundBy:0).tap()
        }
        try unchanged(app)
    }
    func testCatalogGroupsCashPerformanceAndDataToolsEvidence()throws{
        let app=launchClean();defer{finish()};try start(app)
        app.tabBars.buttons["行情"].tap();app.buttons["openCatalog"].tap();try check(app.navigationBars["商品目錄"].waitForExistence(timeout:5),"Catalog missing");pageCapture("AFTER catalog first launch");app.buttons["完成"].tap()
        app.buttons["分組"].tap();try check(app.navigationBars["自選分組"].waitForExistence(timeout:5),"Watch groups missing");pageCapture("AFTER watch groups editor");app.buttons["完成"].tap()
        app.tabBars.buttons["資產"].tap();let cash=app.buttons["調整虛擬資金／換匯"];try reveal(cash,in:app);cash.tap();try check(app.navigationBars["模擬資金操作"].waitForExistence(timeout:5),"Local cash tools missing");pageCapture("AFTER local virtual currency tools");app.buttons["完成"].tap()
        let performance=app.buttons["績效與資金流分析"];try reveal(performance,in:app);performance.tap();try check(app.navigationBars["績效分析"].waitForExistence(timeout:5),"Performance missing");pageCapture("AFTER performance and capital flows");app.buttons["完成"].tap()
        let tools=app.buttons["資料工具：匯出與帳本"];try reveal(tools,in:app);tools.tap();try check(app.navigationBars["資料工具"].waitForExistence(timeout:5),"Data tools missing");pageCapture("AFTER data exports and ledger")
        try unchanged(app)
    }
    func testVisibleChartDepthAdvancedOrderAndProductRulesEvidence()throws{
        let app=launchClean();var completed=false;defer{finish(includeHierarchy:!completed)};try start(app)
        app.tabBars.buttons["交易"].tap()
        let board=app.buttons["整股（張）"];try reveal(board,in:app,identifier:"board-regular");board.tap()
        try waitUntil("Evidence did not actually select whole lots",timeout:5){board.isSelected}
        // Inspect the specifications while the product header is already here.
        // Keep every original check/capture and the later Tab roundtrip, without
        // walking to the product bottom and then back to this same header.
        try specifications(app)
        let chart=app.webViews["inlineChartWeb"];try check(chart.waitForExistence(timeout:10),"Inline chart missing");try reveal(chart,in:app,identifier:"inlineChartWeb")
        try waitUntil("Evidence chart has no rendered candles",timeout:10){((try? self.state(app)["chartRendered"] as? [String:Int])?["inline"] ?? 0)>0}
        pageCapture("AFTER complete inline stock chart volume and indicators")
        let book=app.otherElements["productBookTitle"].firstMatch
        let bookText=app.staticTexts["買賣盤"].firstMatch
        if book.exists{try reveal(book,in:app,identifier:"productBookTitle")}else{try reveal(bookText,in:app)}
        pageCapture("AFTER stock available depth")
        let bottom=app.staticTexts["productBottom"];try reveal(bottom,in:app,identifier:"productBottom");pageCapture("AFTER stock related news and product bottom")
        let order=app.buttons["openOrder"];try reveal(order,in:app,identifier:"openOrder");order.tap()
        let advanced=app.buttons["進階委託與保護"];try reveal(advanced,in:app);advanced.tap();pageCapture("AFTER stock advanced order options")
        app.swipeUp();pageCapture("AFTER stock advanced order summary");app.buttons["完成"].firstMatch.tap()
        app.tabBars.buttons["行情"].tap();app.tabBars.buttons["交易"].tap()
        try check(board.isSelected,"Read-only page and Tab roundtrip changed the selected whole-lot board")
        try unchanged(app)
        completed=true
    }
    private func specifications(_ app:XCUIApplication)throws{
        let specification=app.buttons["商品規格"];try reveal(specification,in:app);specification.tap()
        let unit=app.staticTexts["specQuantityUnit"].firstMatch
        try waitUntil("Product specification content has not finished presenting",timeout:5){unit.exists && unit.isHittable}
        // SwiftUI localizes the integral interpolation as 1,000. Verify the
        // complete units and conversion while accepting that grouping separator.
        let lot=(app.staticTexts["specBoardLot"].value as? String)?.replacingOccurrences(of:",",with:"")
        try check(lot=="1 張 = 1000 股","Stock specifications lost the board lot conversion")
        pageCapture("AFTER stock identity and explicit trading units")
        let precision=app.staticTexts["specPricePrecision"];try reveal(precision,in:app,identifier:"specPricePrecision")
        try check(precision.value as? String=="1","2330 price precision does not match its current price tier")
        let minimum=(app.staticTexts["specQuantityStep"].value as? String)?.replacingOccurrences(of:",",with:"")
        try check(minimum=="1 張（1000 股）","Whole-lot minimum quantity is incorrect")
        pageCapture("AFTER stock price precision and minimum quantities")
        app.swipeUp()
        let rules=app.cells.containing(.staticText,identifier:"規則版本").firstMatch
        try reveal(rules,in:app)
        try check(app.staticTexts["規則版本"].exists,"Visible rule-version row lost its actual label")
        pageCapture("AFTER stock rules and execution limits")
        app.buttons["完成"].firstMatch.tap()
    }
}
