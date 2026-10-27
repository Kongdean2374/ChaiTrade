import XCTest

/// Read-only page evidence complements the financial/interaction journeys; it never replaces them.
@MainActor final class ProductEvidenceTests:IsolatedUITestCase{
    private func start(_ app:XCUIApplication,online:Bool=false)throws{
        let start=app.buttons["startTrading"];try check(start.waitForExistence(timeout:15),"Evidence onboarding missing")
        if online{app.buttons["A 真實行情"].tap()};start.tap()
        try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"Evidence account not ready")
        try check((try state(app))["session"] as? String==session,"Evidence inherited another account")
    }
    private func openSettings(_ app:XCUIApplication)throws{app.buttons["設定"].tap();try check(app.navigationBars["設定"].waitForExistence(timeout:5),"Settings sheet missing")}
    private func page(_ title:String,in app:XCUIApplication)throws{
        let button=app.buttons[title];try reveal(button,in:app);button.tap()
        try check(app.navigationBars[title].waitForExistence(timeout:5),"Evidence page missing: "+title)
        capture("AFTER page "+title+" top");app.swipeUp();capture("AFTER page "+title+" lower")
        app.navigationBars[title].buttons.element(boundBy:0).tap()
        try check(app.navigationBars["設定"].exists,"Evidence back lost settings")
    }
    private func unchanged(_ app:XCUIApplication)throws{
        let s=try state(app);try check((s["orders"] as? [String])?.isEmpty==true && (s["fills"] as? [[String:String]])?.isEmpty==true,"Read-only evidence changed trading history")
        try check((s["cash"] as? [String:String])==["TWD":"1000000"],"Read-only evidence changed capital")
    }
    func testSettingsAccountTradeAndOfflinePageEvidence()throws{
        let app=launchClean();defer{finish()};try start(app);try openSettings(app);capture("AFTER settings first level")
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
        app.buttons["行情連線"].tap();try check(app.navigationBars["行情連線"].waitForExistence(timeout:5),"Connection wizard missing");capture("AFTER A connection wizard sources")
        for title in ["Coinbase Exchange","Fugle 台股","Alpaca（IEX）"]{
            let link=app.buttons.containing(.staticText,identifier:title).firstMatch;try reveal(link,in:app);link.tap()
            try check(app.navigationBars[title].waitForExistence(timeout:5),"Provider page missing "+title);capture("AFTER A source "+title)
            app.navigationBars[title].buttons.element(boundBy:0).tap()
        }
        try unchanged(app)
    }
    func testCatalogGroupsCashPerformanceAndDataToolsEvidence()throws{
        let app=launchClean();defer{finish()};try start(app)
        app.tabBars.buttons["行情"].tap();app.buttons["openCatalog"].tap();try check(app.navigationBars["商品目錄"].waitForExistence(timeout:5),"Catalog missing");capture("AFTER catalog first launch");app.buttons["完成"].tap()
        app.buttons["分組"].tap();try check(app.navigationBars["自選分組"].waitForExistence(timeout:5),"Watch groups missing");capture("AFTER watch groups editor");app.buttons["完成"].tap()
        app.tabBars.buttons["資產"].tap();let cash=app.buttons["調整虛擬資金／換匯"];try reveal(cash,in:app);cash.tap();try check(app.navigationBars["模擬資金操作"].waitForExistence(timeout:5),"Local cash tools missing");capture("AFTER local virtual currency tools");app.buttons["完成"].tap()
        let performance=app.buttons["績效與資金流分析"];try reveal(performance,in:app);performance.tap();try check(app.navigationBars["績效分析"].waitForExistence(timeout:5),"Performance missing");capture("AFTER performance and capital flows");app.buttons["完成"].tap()
        let tools=app.buttons["資料工具：匯出與帳本"];try reveal(tools,in:app);tools.tap();try check(app.navigationBars["資料工具"].waitForExistence(timeout:5),"Data tools missing");capture("AFTER data exports and ledger")
        try unchanged(app)
    }
}
