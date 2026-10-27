import Foundation
import Testing
@testable import ChaiTradeCore

private struct UnitTransport:MarketTransport{
    var flag:String?
    func get(_ url:URL,headers:[String:String])async throws->Data{
        var result:[String:Any]
        if url.path.contains("candles"){
            let query=Dictionary(uniqueKeysWithValues:(URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []).map{($0.name,$0.value ?? "")})
            result=["symbol":"2330","timeframe":query["timeframe"] ?? "1","market":"TSE","data":[["date":query["timeframe"] == "D" ? "2026-10-27":"2026-10-27T09:30:00+08:00","open":100,"high":101,"low":99,"close":100,"volume":7]]]
        }else{
            result=["symbol":"2330","market":"TSE","lastPrice":100,"lastUpdated":Int64(1_793_064_600_000_000),"bids":[["price":99,"size":2]],"asks":[["price":100,"size":3]],"total":["tradeVolume":7,"tradeValue":700000],"previousClose":99]
            if flag=="halt"{result["tradingHalt"]=["isHalted":true]}
            if flag=="trial"{result["isTrial"]=true}
            if flag=="close"{result["isClose"]=true}
            if flag=="crossed"{result["bids"]=[["price":101,"size":2]]}
        }
        return try JSONSerialization.data(withJSONObject:result)
    }
}
@Test func malformedSourceBookHasSpecificStateAndCannotFill()async throws{
    let stock=try #require(InstrumentCatalog.builtIn(mode:.online).first{$0.symbol=="2330"})
    let quote=try await MarketDataProvider(id:.fugle,credentials:ProviderCredentials(key:"synthetic-fixture-not-a-key"),transport:UnitTransport(flag:"crossed")).quote(stock,now:1_793_064_600)
    #expect(quote.sourceIssue == .invalidData);#expect(!quote.valid)
}
@Test func fugleRegularLotsOddSharesAndMinuteVersusDailyVolumeStayDistinct()async throws{
    let stock=try #require(InstrumentCatalog.builtIn(mode:.online).first{$0.symbol=="2330"})
    let provider=MarketDataProvider(id:.fugle,credentials:ProviderCredentials(key:"synthetic-fixture-not-a-key"),transport:UnitTransport())
    let regular=try await provider.quote(stock,now:1_793_064_600,board:.regular),odd=try await provider.quote(stock,now:1_793_064_600,board:.oddLot)
    #expect(try regular.asks.first?.quantity==Amount("3000"));#expect(try regular.bids.first?.quantity==Amount("2000"));#expect(try regular.summary?.volume==Amount("7000"))
    #expect(try odd.asks.first?.quantity==Amount("3"));#expect(try odd.summary?.volume==Amount("7"))
    #expect(regular.storageKey != odd.storageKey)
    let minute=try await provider.candles(stock,interval:60,now:1_793_064_600),daily=try await provider.candles(stock,interval:86400,now:1_793_064_600),oddMinute=try await provider.candles(stock,interval:60,now:1_793_064_600,board:.oddLot)
    #expect(minute.first?.volume==7000);#expect(daily.first?.volume==7);#expect(oddMinute.first?.volume==7)
}
@Test(arguments:["halt","trial","close"])
func declaredSourceSessionStatesNeverFillButLocalCancellationRemainsAvailable(flag:String)async throws{
    let stock=try #require(InstrumentCatalog.builtIn(mode:.online).first{$0.symbol=="2330"})
    let provider=MarketDataProvider(id:.fugle,credentials:ProviderCredentials(key:"synthetic-fixture-not-a-key"),transport:UnitTransport(flag:flag))
    let quote=try await provider.quote(stock,now:1_793_064_600)
    #expect(quote.sourceIssue == (flag=="halt" ? .halted:flag=="trial" ? .auction:.closed))
    if flag=="close"{#expect(quote.quality == .historical);#expect(quote.valid)}else{#expect(!quote.valid)}
    let context=AccountContext(mode:.online),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var state=try TradingEngine.initial(mode:.online,capital:Amount("1000000"),time:1_793_064_600);state.instruments=[stock]
    let engine=try TradingEngine(context:context,repository:AccountRepository(root:root,mode:.online),initial:state)
    let healthy=try await MarketDataProvider(id:.fugle,credentials:ProviderCredentials(key:"synthetic-fixture-not-a-key"),transport:UnitTransport()).quote(stock,now:1_793_064_600)
    try await engine.ingest(healthy,now:1_793_064_600,context:context)
    try await engine.ingest(quote,now:1_793_064_600,context:context)
    var order=OrderRequest(instrumentID:stock.id,side:.buy,kind:.limit,quantity:try Amount("1000"),price:try Amount("100"));order.board = .regular
    _=try await engine.submit(order,time:1_793_064_600,context:context)
    #expect(await engine.snapshot().fills.isEmpty);#expect(await engine.snapshot().orders[order.requestID]?.status.open==true)
    try await engine.cancel(id:order.requestID,time:1_793_064_601,context:context)
    #expect(await engine.snapshot().orders[order.requestID]?.status == .cancelled)
    #expect(try await engine.snapshot().cash["TWD"]==Amount("1000000"))
}

@Test func sourceVerifiedBoardLotControlsQuoteAndMinuteShareNormalization()async throws{
    var stock=try #require(InstrumentCatalog.builtIn(mode:.online).first{$0.symbol=="2330"});stock.identity?.boardLot=100
    let provider=MarketDataProvider(id:.fugle,credentials:ProviderCredentials(key:"synthetic-fixture-not-a-key"),transport:UnitTransport())
    let quote=try await provider.quote(stock,now:1_793_064_600,board:.regular)
    #expect(try quote.asks.first?.quantity==Amount(300));#expect(try quote.summary?.volume==Amount(700))
    let minute=try await provider.candles(stock,interval:60,now:1_793_064_600),daily=try await provider.candles(stock,interval:86400,now:1_793_064_600)
    #expect(minute.first?.volume==700 && daily.first?.volume==7)
}
