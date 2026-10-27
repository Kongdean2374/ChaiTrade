import Foundation
import Testing
@testable import ChaiTradeCore

@Test func foreignValuationRequiresFreshNonFutureCurrencySpecificRate()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.online)
    let state=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    let engine=try TradingEngine(context:context,repository:AccountRepository(root:root,mode:.online),initial:state)
    try await engine.setFX(FXRate(currency:"USD",base:"TWD",rate:try Amount("30"),time:1000,source:"synthetic exact fixture",maximumAge:60),context:context)
    try await engine.cashFlow(currency:"USD",amount:Amount("100"),time:1005,context:context)
    let funded=await engine.snapshot()
    #expect(try Analytics.valuation(funded,now:1005).total==Amount("103000"))
    #expect(try Analytics.valuation(funded,now:1005).complete)
    let stale=try Analytics.valuation(funded,now:1065)
    #expect(!stale.complete && stale.tradingPnL==nil);#expect(stale.missing.contains{$0.contains("USD/TWD")})
    try await engine.cashFlow(currency:"USD",amount:Amount("1"),time:1065,context:context)
    #expect(await engine.snapshot().equity.last?.value==nil);#expect(await engine.snapshot().equity.last?.flow == .zero)
    var future=funded;future.lifecycle!.rates[0].time=2000
    #expect(try !Analytics.valuation(future,now:1005).complete)
    var wrongCurrency=funded;wrongCurrency.lifecycle!.rates[0].currency="USDT"
    #expect(try !Analytics.valuation(wrongCurrency,now:1005).complete)
    await #expect(throws:TradeError.self){try await engine.setFX(FXRate(currency:"USD",base:"TWD",rate:Amount("30"),time:1000,source:"",maximumAge:60),context:context)}
    await #expect(throws:TradeError.self){try await engine.setFX(FXRate(currency:"USD",base:"TWD",rate:Amount("30"),time:1000,source:"simulated scenario",kind:.simulated),context:context)}
}
