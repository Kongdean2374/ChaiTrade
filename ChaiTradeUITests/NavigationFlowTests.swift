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
    }
    func test2330DetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:TWSE:2330",query:"2330",crypto:false)}
    func testBTCDetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:Coinbase_Exchange:BTC-USD",query:"BTC",crypto:true)}
    func testETHDetailRemainsInMarketsWithoutPreparingAnOrder()throws{try verifyBrowsingOnly("SIM:Coinbase_Exchange:ETH-USD",query:"ETH",crypto:true)}
}
