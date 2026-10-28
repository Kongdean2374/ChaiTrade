import Foundation
import Testing
@testable import ChaiTradeCore

private func a(_ text: String) throws -> Amount { try Amount(text) }
private struct Rig {
    let root: URL
    let context: AccountContext
    let repo: AccountRepository
    let engine: TradingEngine
    let instrument: Instrument
    init(mode: Mode = .online, capital: String = "100000", fee: String = "0", minimum: String = "0", derivative: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        context = AccountContext(mode:mode); repo = try AccountRepository(root:root,mode:mode)
        var rules = RulePack(tick:try a("0.01"),quantityStep:try a("0.001"))
        rules.fees.fixed = try a(fee); rules.fees.minimum = try a(minimum)
        instrument = Instrument(id:mode == .offline ? "SIM:TEST":"TEST",symbol:"TEST",name:"測試合成商品",asset:derivative ? .perpetual:.crypto,currency:"TWD",rules:rules,initialPrice:try a("100"))
        var s = try TradingEngine.initial(mode:mode,capital:a(capital),time:1000)
        s.instruments = [instrument]; s.leverageEnabled = true
        engine = try TradingEngine(context:context,repository:repo,initial:s)
    }
    func quote(price: String = "100", quantity: String = "1000", time: Int64 = 1000, grade: ExecutionGrade = .E1) throws -> Quote {
        var q = Quote(instrumentID:instrument.id,source:"synthetic-fixture",time:time,sequence:time,last:try a(price),bids:[Level(try a(price),try a(quantity))],asks:[Level(try a(price),try a(quantity))],grade:grade)
        // Non-crossed market with exact executable ask at the test price.
        q.bids = [Level(try a(price)-a("0.01"),try a(quantity))]
        q.mark = try a(price); return q
    }
    func buy(quantity: String = "100", price: String? = nil, id: String = UUID().uuidString) throws -> OrderRequest {
        var r = OrderRequest(instrumentID:instrument.id,side:.buy,kind:price == nil ? .market:.limit,quantity:try a(quantity),price:try price.map(a));r.requestID=id;return r
    }
}

@Test func exactDecimalAndSerialization() throws {
    #expect(try a("0.1") + a("0.2") == a("0.3"))
    #expect(try String(decoding:JSONEncoder().encode(a("123.4500")),as:UTF8.self) == "\"123.45\"")
    #expect(throws:TradeError.self) { try a("NaN") }
    #expect(throws:TradeError.self) { try a("1e40") }
    #expect(throws:TradeError.self) { try a("0.0000000000001") }
    #expect(throws:TradeError.self) { try Amount.max + .one }
    #expect(throws:TradeError.self) { try a("1") / .zero }
    #expect(try a("0.03").isMultiple(of:a("0.01")))
}

@Test func unchangedOrderProjectionDoesNotRewriteOrdersButCancellationPersists()async throws{
    let r=try Rig();try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    let id=try await r.engine.submit(r.buy(quantity:"1",price:"90",id:"write-amplification"),time:1000,context:r.context)
    let initial=await r.engine.snapshot()
    try r.repo.exec("CREATE TABLE synthetic_order_updates(value INTEGER NOT NULL); CREATE TRIGGER synthetic_order_update_probe AFTER UPDATE ON orders BEGIN INSERT INTO synthetic_order_updates VALUES(1); END")
    _=try r.repo.save(initial)
    #expect(try r.repo.scalar("SELECT count(*) FROM synthetic_order_updates")=="0")
    try await r.engine.cancel(id:id,time:1001,context:r.context)
    #expect(try r.repo.scalar("SELECT count(*) FROM synthetic_order_updates")=="1")
    let reopened=try AccountRepository(root:r.root,mode:.online),restored=try #require(try reopened.load())
    #expect(restored.orders[id]?.status == .cancelled)
    #expect(restored.orders[id]?.reserved == .zero)
    #expect(restored.cash==initial.cash)
    #expect(try reopened.scalar("PRAGMA synchronous")=="2")
}
@Test func vectorAAndIsolation() async throws {
    let r = try Rig()
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _ = try await r.engine.submit(r.buy(id:"buy"),time:1000,context:r.context)
    var s = await r.engine.snapshot()
    #expect(s.cash["TWD"] == (try a("90000")));#expect(s.positions["TEST"]?.quantity == (try a("100")))
    let other = try AccountRepository(root:r.root,mode:.offline)
    let b = try TradingEngine.initial(mode:.offline,capital:a("100000"),time:1000);try other.save(b)
    #expect(try other.load()?.fills.isEmpty == true)
    let restored = try AccountRepository(root:r.root,mode:.online).load()
    #expect(restored?.fills.count == 1)
    let q = try r.quote(price:"110",time:1005)
    try await r.engine.ingest(q,now:1005,context:r.context)
    let sell = OrderRequest(instrumentID:"TEST",side:.sell,kind:.market,quantity:try a("100"))
    _ = try await r.engine.submit(sell,time:1005,context:r.context)
    s = await r.engine.snapshot()
    // Sell executes at bid 109.99, proving that the engine does not use last trade price.
    #expect(s.cash["TWD"] == (try a("100999")))
    #expect(s.positions["TEST"]?.quantity == .zero)
    #expect(s.positions["TEST"]?.realized == (try a("999")))
    #expect(try sum(s.ledger.map(\.amount)) == .zero)
}
@Test func vectorBFees() async throws {
    let r=try Rig(fee:"10")
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _ = try await r.engine.submit(r.buy(),time:1000,context:r.context)
    var q=try r.quote(price:"110",time:1005);q.bids=[Level(try a("110"),try a("1000"))];q.asks=[Level(try a("110.01"),try a("1000"))]
    try await r.engine.ingest(q,now:1005,context:r.context)
    _ = try await r.engine.submit(OrderRequest(instrumentID:"TEST",side:.sell,kind:.market,quantity:a("100")),time:1005,context:r.context)
    let s=await r.engine.snapshot()
    #expect(s.cash["TWD"] == (try a("100980")))
    #expect(try sum(s.fills.map(\.fee)) == a("20"))
}
@Test func minimumFeeNotRepeatedOnPartialFills() async throws {
    let r=try Rig(minimum:"10")
    try await r.engine.ingest(r.quote(quantity:"40"),now:1000,context:r.context)
    let id = try await r.engine.submit(r.buy(quantity:"100",price:"100"),time:1000,context:r.context)
    var s=await r.engine.snapshot(); #expect(s.orders[id]?.filled == (try a("40")))
    try await r.engine.ingest(r.quote(quantity:"60",time:1005),now:1005,context:r.context)
    s=await r.engine.snapshot();#expect(s.orders[id]?.status == .filled)
    #expect(try sum(s.fills.map(\.fee)) == a("10"))
}
@Test func duplicateRequestAndEpoch() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    let request=try r.buy(id:"same-request")
    _=try await r.engine.submit(request,time:1000,context:r.context)
    _=try await r.engine.submit(request,time:1000,context:r.context)
    #expect(await r.engine.snapshot().fills.count == 1)
    await #expect(throws:TradeError.self) { try await r.engine.submit(request,time:1000,context:AccountContext(mode:.online)) }
}
@Test func reservationsAndCancel() async throws {
    let r=try Rig(capital:"1000")
    let id=try await r.engine.submit(r.buy(quantity:"8",price:"100"),time:1000,context:r.context)
    #expect(try TradingEngine.available(await r.engine.snapshot(),currency:"TWD") == a("200"))
    await #expect(throws:TradeError.self) { try await r.engine.submit(r.buy(quantity:"3",price:"100"),time:1000,context:r.context) }
    try await r.engine.cancel(id:id,time:1001,context:r.context)
    #expect(try TradingEngine.available(await r.engine.snapshot(),currency:"TWD") == a("1000"))
}
@Test func partialCancelAndSharedLiquidity() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(quantity:"30"),now:1000,context:r.context)
    let first=try await r.engine.submit(r.buy(quantity:"50",price:"100"),time:1000,context:r.context)
    _=try await r.engine.submit(r.buy(quantity:"50",price:"100"),time:1000,context:r.context)
    var s=await r.engine.snapshot();#expect(try sum(s.fills.map(\.quantity)) == a("30"))
    try await r.engine.cancel(id:first,time:1001,context:r.context)
    s=await r.engine.snapshot();#expect(s.orders[first]?.filled == (try a("30")));#expect(s.orders[first]?.reserved == .zero)
}
@Test func fokAndIOC() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(quantity:"30"),now:1000,context:r.context)
    var request=try r.buy(quantity:"50");request.timeInForce = .FOK
    let id=try await r.engine.submit(request,time:1000,context:r.context)
    #expect(await r.engine.snapshot().orders[id]?.filled == .zero)
    request=try r.buy(quantity:"50");request.timeInForce = .IOC
    let ioc=try await r.engine.submit(request,time:1000,context:r.context)
    let s=await r.engine.snapshot();#expect(s.orders[ioc]?.filled == (try a("30")));#expect(s.orders[ioc]?.status == .cancelled)
}
@Test func postOnlyAndAtomicAmend() async throws {
    let r=try Rig(capital:"1000");try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    var request=try r.buy(quantity:"1",price:"100");request.postOnly=true
    await #expect(throws:TradeError.self) { try await r.engine.submit(request,time:1000,context:r.context) }
    let id=try await r.engine.submit(r.buy(quantity:"5",price:"90"),time:1000,context:r.context)
    await #expect(throws:TradeError.self) { try await r.engine.amend(id:id,quantity:a("50"),price:a("90"),time:1000,context:r.context) }
    #expect(await r.engine.snapshot().orders[id]?.request.quantity == (try a("5")))
}
@Test func staleAndDelayedNeverFill() async throws {
    let r=try Rig();var q=try r.quote();q.quality = .delayed
    try await r.engine.ingest(q,now:1000,context:r.context)
    let id=try await r.engine.submit(r.buy(),time:1000,context:r.context)
    #expect(await r.engine.snapshot().orders[id]?.filled == .zero)
    q=try r.quote(time:1005);try await r.engine.ingest(q,now:1100,context:r.context)
    #expect(await r.engine.snapshot().fills.isEmpty)
}
@Test func stopLimitGapDoesNotGuaranteeFill() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    let stop=OrderRequest(instrumentID:"TEST",side:.buy,kind:.stopLimit,quantity:try a("1"),price:try a("105"),trigger:try a("103"))
    let id=try await r.engine.submit(stop,time:1000,context:r.context)
    try await r.engine.ingest(r.quote(price:"110",time:1005),now:1005,context:r.context)
    let s=await r.engine.snapshot();#expect(s.orders[id]?.triggered == true);#expect(s.orders[id]?.filled == .zero)
}
@Test func ocoAtomicAndReduceOnly() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _=try await r.engine.submit(r.buy(quantity:"10"),time:1000,context:r.context)
    var take=OrderRequest(instrumentID:"TEST",side:.sell,kind:.limit,quantity:try a("10"),price:try a("110"))
    var stop=OrderRequest(instrumentID:"TEST",side:.sell,kind:.stopMarket,quantity:try a("10"),trigger:try a("90"))
    take.reduceOnly=true;stop.reduceOnly=true
    try await r.engine.submitOCO(take,stop,time:1000,context:r.context)
    try await r.engine.ingest(r.quote(price:"111",time:1005),now:1005,context:r.context)
    let s=await r.engine.snapshot();#expect(s.positions["TEST"]?.quantity == .zero)
    #expect(s.orders.values.filter{$0.request.groupID != nil && $0.status == .cancelled}.count == 1)
}
@Test func bracketFollowsActualFills() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(quantity:"4"),now:1000,context:r.context)
    var main=try r.buy(quantity:"10",price:"100");main.bracketProfit=try a("110");main.bracketStop=try a("90")
    _=try await r.engine.submit(main,time:1000,context:r.context)
    let s=await r.engine.snapshot();let children=s.orders.values.filter{$0.request.parentID != nil}
    #expect(children.count == 2);#expect(children.allSatisfy{$0.request.quantity == (try? a("4"))})
}
@Test func moneyFlowIsNotProfitAndFXIsIncomplete() async throws {
    let r=try Rig();try await r.engine.cashFlow(currency:"TWD",amount:a("50000"),time:1000,eventID:"deposit",context:r.context)
    try await r.engine.cashFlow(currency:"TWD",amount:a("50000"),time:1000,eventID:"deposit",context:r.context)
    var s=await r.engine.snapshot();#expect(try Analytics.valuation(s).tradingPnL == .zero)
    try await r.engine.cashFlow(currency:"USDT",amount:a("10"),time:1000,context:r.context)
    s=await r.engine.snapshot();#expect(try !Analytics.valuation(s).complete)
    let points=[EquityPoint(time:1,value:try a("100000"),flow:.zero),EquityPoint(time:2,value:try a("150000"),flow:try a("50000"))]
    #expect(Analytics.timeWeighted(points).last! == 1)
}
@Test func derivativeNotionalIsNotAnAssetAndLiquidationKeepsDeficit() async throws {
    let r=try Rig(capital:"1000",derivative:true)
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    var order=try r.buy(quantity:"50");order.leverage=10
    _=try await r.engine.submit(order,time:1000,context:r.context)
    let v=try Analytics.valuation(await r.engine.snapshot());#expect(v.total == (try a("1000")))
    try await r.engine.ingest(r.quote(price:"1",time:1005),now:1005,context:r.context)
    let s=await r.engine.snapshot();#expect(s.cash["TWD"]! < .zero);#expect(s.positions["TEST"]?.quantity == .zero)
}
@Test func deterministicCatalogAndTimePaths() throws {
    let catalog=try Simulation.catalog();#expect(catalog.filter{$0.asset != .index}.count == 120);#expect(catalog.filter{$0.asset == .index}.count == 5)
    let i=catalog.first(where:{$0.asset == .crypto})!,s=SimulationState()
    let expected=try Simulation.price(i,at:s.time+300,state:s)
    _=try Simulation.candles(i,state:s,interval:60,count:20)
    #expect(try Simulation.price(i,at:s.time+300,state:s) == expected)
    let candles=try Simulation.candles(i,state:s,interval:60,count:2)
    #expect(candles.last?.time == s.time);#expect(candles.last?.open == candles.last?.close);#expect(candles.last?.complete == false)
}
@Test func offlineRejectsNetworkAndReplayCheckpoint() async throws {
    let r=try Rig(mode:.offline)
    await #expect(throws:TradeError.self) { try await r.engine.ingest(r.quote(),now:1000,context:r.context) }
    let start=await r.engine.snapshot().simulation!.time
    _=try await r.engine.advance(to:start+30,context:r.context)
    let checkpoint=try r.repo.load()!
    let reopened=try TradingEngine(context:r.context,repository:r.repo,initial:checkpoint)
    _=try await reopened.advance(to:start+60,context:r.context)
    _=try await r.engine.advance(to:start+60,context:r.context)
    #expect(try AccountRepository.encode(await reopened.snapshot()) == AccountRepository.encode(await r.engine.snapshot()))
}
@Test func backupRoundTripEncryptionTamperingAndWrongMode() throws {
    let r=try Rig(),s=try r.repo.load()!
    let plain=try BackupService.export(s,password:nil,time:1000)
    #expect(try BackupService.validate(plain,expectedMode:.online,password:nil).cash == s.cash)
    let data=try BackupService.export(s,password:"test-password",time:1000)
    #expect(try BackupService.validate(data,expectedMode:.online,password:"test-password").cash == s.cash)
    #expect(throws:TradeError.self) { try BackupService.validate(data,expectedMode:.online,password:"wrong-password") }
    #expect(throws:TradeError.self) { try BackupService.validate(data,expectedMode:.offline,password:"test-password") }
    var e=try JSONDecoder().decode(BackupEnvelope.self,from:plain);e.payload.append(0)
    #expect(throws:TradeError.self) { try BackupService.validate(JSONEncoder().encode(e),expectedMode:.online,password:nil) }
    #expect(BackupService.digest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
@Test func brokenDatabaseAndLedgerNeverReset() throws {
    let r=try Rig();var s=try r.repo.load()!
    s.ledger.append(LedgerEntry(eventID:"bad",accountID:s.accountID,time:1000,currency:"TWD",account:"cash",amount:.one))
    #expect(throws:TradeError.self) { try r.repo.save(s) }
    #expect(try r.repo.load()?.cash["TWD"] == a("100000"))
}
@Test func pendingModeOnlyAtColdStart() throws {
    let r=try Rig();var settings=AppSettings();settings.activeMode = .online;settings.pendingMode = .offline
    try settings.save(root:r.root)
    let loaded=try AppSettings.load(root:r.root)
    #expect(loaded.activeMode == .online);#expect(loaded.pendingMode == .offline)
}
@Test func networkWhitelistAndCSVInjection() throws {
    #expect(NetworkPolicy.permits(URL(string:"https://api.exchange.coinbase.com/products/BTC-USD/ticker")!,method:"GET",mode:.online))
    for path in ["https://api.exchange.coinbase.com/orders","https://api.exchange.coinbase.com/accounts","https://evil.com/products/BTC-USD/ticker"] {
        #expect(!NetworkPolicy.permits(URL(string:path)!,method:"GET",mode:.online))
    }
    #expect(!NetworkPolicy.permits(URL(string:"https://api.exchange.coinbase.com/products")!,method:"POST",mode:.online))
    #expect(!NetworkPolicy.permits(URL(string:"https://api.exchange.coinbase.com/products")!,method:"GET",mode:.offline))
    #expect(throws:TradeError.self) { try ReadOnlyTransport(mode:.offline) }
    #expect(Analytics.csvCell("=IMPORTDATA(\"x\")").hasPrefix("\"'="))
}
@Test func indicatorsWarmupAndFormulaVectors() throws {
    let values=[1.0,2,3,4,5]
    #expect(Indicators.ma(values,period:3) == [nil,nil,2,3,4])
    #expect(Indicators.ema(values,period:3) == [nil,nil,2,3,4])
    #expect(Indicators.rsi(values,period:3).last! == 100)
    let b=Indicators.bollinger(values,period:3)
    let expected: Double = 4.0+2.0*sqrt(2.0/3.0)
    let difference: Double = abs(b.upper.last!!-expected)
    #expect(difference < 1e-10)
    #expect(Analytics.maximumDrawdown([1,1.2,0.9,1.3])! > 0.249999)
}
private struct FixtureTransport: MarketTransport {
    let ticker: String
    let book: String
    func get(_ url: URL, headers: [String:String]) async throws -> Data { Data((url.path.hasSuffix("book") ? book:ticker).utf8) }
}
@Test func coinbaseParserUsesExactDecimalsAndSourceTime() async throws {
    let i=try Providers.catalog().first!
    let p=MarketDataProvider(id:.coinbase,credentials:ProviderCredentials(),transport:FixtureTransport(ticker:#"{"price":"100.12345678","time":"2026-10-27T00:00:00Z"}"#,book:#"{"sequence":123,"bids":[["100.12","2",1]],"asks":[["100.13","3",1]]}"#))
    let q=try await p.quote(i,now:1_793_059_200)
    #expect(q.last == (try a("100.12345678")));#expect(q.sequence == 123);#expect(q.bids.count == 1)
    let j=try JSONValue.parse(Data("{\"price\":0.123456789012}".utf8));#expect(try j["price"].amount() == a("0.123456789012"))
}

@Test func splitVectorDAndDividendIdempotency() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _=try await r.engine.submit(r.buy(),time:1000,context:r.context)
    let split=CorporateAction(id:"split",instrumentID:"TEST",kind:.split,time:1005,ratio:try a("2"),source:"合成測試")
    try await r.engine.corporateAction(split,context:r.context)
    try await r.engine.corporateAction(split,context:r.context)
    var s=await r.engine.snapshot()
    #expect(s.positions["TEST"]?.quantity == (try a("200")))
    #expect(s.positions["TEST"]?.average == (try a("50")))
    #expect(try s.positions["TEST"]!.quantity*s.positions["TEST"]!.average == a("10000"))
    let dividend=CorporateAction(id:"div",instrumentID:"TEST",kind:.dividend,time:1010,cashPerUnit:try a("1"),paymentTime:1020,source:"合成測試")
    try await r.engine.corporateAction(dividend,context:r.context)
    #expect(await r.engine.snapshot().cash["TWD"] == (try a("90000")))
    try await r.engine.processDueEvents(time:1020,context:r.context)
    try await r.engine.processDueEvents(time:1020,context:r.context)
    s=await r.engine.snapshot();#expect(s.cash["TWD"] == (try a("90200")))
}
@Test func businessDaySettlementAndNoDoubleAssets() async throws {
    let r=try Rig();var rules=r.instrument.rules;rules.settlementBusinessDays=2
    try await r.engine.updateRules(instrumentID:"TEST",rules:rules,context:r.context)
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _=try await r.engine.submit(r.buy(),time:1000,context:r.context)
    var s=await r.engine.snapshot()
    #expect(s.cash["TWD"] == (try a("100000")))
    #expect(try TradingEngine.available(s,currency:"TWD") == a("90000"))
    #expect(try Analytics.valuation(s).total == a("100000"))
    try await r.engine.processDueEvents(time:1_000_000,context:r.context)
    s=await r.engine.snapshot();#expect(s.cash["TWD"] == (try a("90000")))
    #expect(try Analytics.valuation(s).total == a("100000"))
    let f=ISO8601DateFormatter();let friday=Int64(f.date(from:"2026-10-23T14:00:00Z")!.timeIntervalSince1970)
    rules.timeZone="America/New_York";rules.holidays=["2026-10-26"]
    let due=try MarketCalendar.settlementDate(tradeTime:friday,businessDays:1,rules:rules)
    #expect(f.string(from:Date(timeIntervalSince1970:TimeInterval(due))) == "2026-10-27T14:00:00Z")
}
@Test func fundingReplayAndMarginAdjustment() async throws {
    let r=try Rig(derivative:true);try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    var order=try r.buy(quantity:"10");order.leverage=10
    _=try await r.engine.submit(order,time:1000,context:r.context)
    try await r.engine.adjustMargin(instrumentID:"TEST",amount:a("50"),time:1001,context:r.context)
    #expect(await r.engine.snapshot().positions["TEST"]?.margin == (try a("150")))
    for _ in 0..<2 {try await r.engine.applyCarry(instrumentID:"TEST",rate:a("0.001"),mark:a("100"),time:1005,eventID:"funding-1",kind:"funding",source:"模擬費率",context:r.context)}
    let s=await r.engine.snapshot();#expect(s.cash["TWD"] == (try a("99999")));#expect(s.lifecycle?.carry.count == 1)
    #expect(try AccountRepository.validate(s,mode:.online) == ())
}
@Test func fundingConsumesOnlyTheRequiredIsolatedMarginAndPreservesDeficit()async throws{
    let r=try Rig(capital:"110",derivative:true)
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _=try await r.engine.submit(r.buy(quantity:"1"),time:1000,context:r.context)
    try await r.engine.applyCarry(instrumentID:"TEST",rate:a("0.2"),mark:a("100"),time:1005,eventID:"fee-a",kind:"funding",source:"synthetic",context:r.context)
    var s=await r.engine.snapshot()
    #expect(try s.cash["TWD"]==a("90"));#expect(try s.positions["TEST"]?.margin==a("90"))
    #expect(try TradingEngine.available(s,currency:"TWD") == .zero)
    try await r.engine.applyCarry(instrumentID:"TEST",rate:a("1"),mark:a("100"),time:1005,eventID:"fee-b",kind:"funding",source:"synthetic",context:r.context)
    s=await r.engine.snapshot();#expect(s.positions["TEST"]?.quantity == .zero);#expect(try s.cash["TWD"]==a("-10"))
}
@Test func crossMarginDoesNotSubtractAnotherCurrencyIsolatedCollateral()async throws{
    let r=try Rig(capital:"100",derivative:true);var s=await r.engine.snapshot(),usd=r.instrument
    usd.id="USDTEST";usd.currency="USD";s.instruments.append(usd)
    try await r.engine.restore(s,context:r.context)
    try await r.engine.cashFlow(currency:"USD",amount:a("1500"),time:1000,context:r.context)
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    var first=try r.buy(quantity:"1");first.leverage=10;first.marginMode = .cross
    _=try await r.engine.submit(first,time:1000,context:r.context)
    var q=try r.quote();q.instrumentID="USDTEST";try await r.engine.ingest(q,now:1000,context:r.context)
    _=try await r.engine.submit(OrderRequest(instrumentID:"USDTEST",side:.buy,kind:.market,quantity:a("10")),time:1000,context:r.context)
    try await r.engine.ingest(r.quote(time:1005),now:1005,context:r.context)
    s=await r.engine.snapshot();#expect(s.positions["TEST"]?.quantity == .one);#expect(try s.positions["USDTEST"]?.margin==a("1000"))
    #expect(!s.events.contains{$0.kind=="liquidation"})
}
@Test func bracketPartialExitRemainsProtected() async throws {
    let r=try Rig();try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    var main=try r.buy(quantity:"10");main.bracketProfit=try a("110");main.bracketStop=try a("90")
    _=try await r.engine.submit(main,time:1000,context:r.context)
    try await r.engine.ingest(r.quote(price:"111",quantity:"4",time:1005),now:1005,context:r.context)
    let s=await r.engine.snapshot(),children=s.orders.values.filter{$0.status.open && $0.request.parentID != nil}
    #expect(s.positions["TEST"]?.quantity == (try a("6")))
    #expect(children.count == 2);#expect(children.allSatisfy{$0.request.quantity == (try? a("6"))})
}
@Test func cashProjectionTamperingRejected() throws {
    let r=try Rig();var s=try r.repo.load()!;s.cash["TWD"]=try a("999999")
    #expect(throws:TradeError.self){try r.repo.save(s)}
}
@Test func corporateSplitDoesNotRewriteOfflineHistory() async throws {
    let r=try Rig(mode:.offline);try await r.engine.initializeQuotes(context:r.context)
    let old=await r.engine.snapshot(),sim=old.simulation!,before=try Simulation.price(r.instrument,at:sim.time-5,state:sim)
    try await r.engine.corporateAction(CorporateAction(instrumentID:r.instrument.id,kind:.split,time:sim.time,ratio:a("2"),source:"模擬事件"),context:r.context)
    let changed=await r.engine.snapshot().simulation!
    #expect(try Simulation.price(r.instrument,at:sim.time-5,state:changed) == before)
    let current=try Simulation.price(r.instrument,at:sim.time,state:changed)
    let original=try Simulation.price(r.instrument,at:sim.time,state:sim)
    #expect(abs(current.displayDouble*2-original.displayDouble) <= 0.02)
}

@Test func dualAccountBackupAndCSVNumbers() throws {
    let r=try Rig();let online=try r.repo.load()!
    let offline=try TradingEngine.initial(mode:.offline,capital:a("50000"),time:1000)
    let data=try BackupService.exportBoth([online,offline],password:nil,time:1000)
    #expect(try BackupService.importAccount(data,expectedMode:.online,password:nil).cash["TWD"] == a("100000"))
    #expect(try BackupService.importAccount(data,expectedMode:.offline,password:nil).cash["TWD"] == a("50000"))
    #expect(Analytics.csvCell("-123.45") == "\"-123.45\"")
    #expect(Analytics.csvCell("-1+CMD()") == "\"'-1+CMD()\"")
}

@Test func sourceSpecificDepthGapRecovery() throws {
    var book=OrderBookTracker()
    try book.snapshot(bids:[Level(a("99"),a("10"))],asks:[Level(a("101"),a("10"))],sequence:10)
    #expect(book.valid)
    #expect(throws:TradeError.self){try book.delta(bids:[],asks:[],sequence:12,previousSequence:nil,contiguous:true)}
    #expect(!book.valid)
    try book.snapshot(bids:[Level(a("99"),a("10"))],asks:[Level(a("101"),a("10"))],sequence:100)
    try book.delta(bids:[Level(a("99"),a("5"))],asks:[],sequence:125,previousSequence:100,contiguous:false)
    #expect(book.bids.first?.quantity == (try a("5")))
    #expect(throws:TradeError.self){try book.delta(bids:[],asks:[],sequence:130,previousSequence:124,contiguous:false)}
    #expect(!book.valid)
    #expect(!NetworkPolicy.permitsWebSocket(URL(string:"wss://ws-feed.exchange.coinbase.com")!,mode:.offline))
}
@Test func simulationControlOnlyAffectsFuture() async throws {
    let r=try Rig(mode:.offline),before=await r.engine.snapshot(),sim=before.simulation!
    let price=try Simulation.price(r.instrument,at:sim.time,state:sim)
    try await r.engine.configureSimulation(speed:100,paused:false,scenario:"恐慌",volatility:5,liquidity:0.1,context:r.context)
    let after=await r.engine.snapshot().simulation!
    #expect(try Simulation.price(r.instrument,at:sim.time,state:after) == price)
}

@Test func partialFillReleasesAlreadyPaidMinimumFeeReservation() async throws {
    let r=try Rig(minimum:"10");try await r.engine.ingest(r.quote(quantity:"40"),now:1000,context:r.context)
    let id=try await r.engine.submit(r.buy(quantity:"100",price:"100"),time:1000,context:r.context)
    let s=await r.engine.snapshot()
    #expect(s.orders[id]?.reserved == (try a("6000")))
    #expect(try TradingEngine.available(s,currency:"TWD") == a("89990"))
}
@Test func futureSettlementResetsBasisAndExpires() async throws {
    let r=try Rig(capital:"1000",derivative:true)
    var initial=await r.engine.snapshot();initial.instruments[0].asset = .future
    try await r.engine.restore(initial,context:r.context)
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    var order=try r.buy(quantity:"2");order.leverage=10
    _=try await r.engine.submit(order,time:1000,context:r.context)
    try await r.engine.settleFuture(instrumentID:"TEST",price:a("110"),time:1005,eventID:"daily",final:false,context:r.context)
    try await r.engine.settleFuture(instrumentID:"TEST",price:a("110"),time:1005,eventID:"daily",final:false,context:r.context)
    try await r.engine.ingest(r.quote(price:"110",time:1005),now:1005,context:r.context)
    #expect(try Analytics.valuation(await r.engine.snapshot()).total == a("1020"))
    try await r.engine.settleFuture(instrumentID:"TEST",price:a("120"),time:1010,eventID:"expiry",final:true,context:r.context)
    #expect(await r.engine.snapshot().cash["TWD"] == (try a("1040")))
    await #expect(throws:TradeError.self){try await r.engine.submit(r.buy(quantity:"1"),time:1010,context:r.context)}
}
@Test func reducedPositionCannotReverseOnSecondExit() async throws {
    let r=try Rig(derivative:true);try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    _=try await r.engine.submit(r.buy(quantity:"10"),time:1000,context:r.context)
    var exit=OrderRequest(instrumentID:"TEST",side:.sell,kind:.limit,quantity:try a("8"),price:try a("110"));exit.reduceOnly=true
    _=try await r.engine.submit(exit,time:1000,context:r.context)
    exit.requestID=UUID().uuidString;_=try await r.engine.submit(exit,time:1000,context:r.context)
    try await r.engine.ingest(r.quote(price:"111",time:1005),now:1005,context:r.context)
    #expect(await r.engine.snapshot().positions["TEST"]?.quantity == .zero)
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["CHAI_STRESS"]=="1"))
func stressHistory100000() async throws {
    let r=try Rig(capital:"1000000");var s=try r.repo.load()!
    let quantity=try a("1"),price=try a("100")
    for n in 0..<100000 {
        let id="stress-\(n)",side: Side=n%2==0 ? .buy:.sell,time=Int64(1000+n)
        var request=OrderRequest(instrumentID:"TEST",side:side,kind:.limit,quantity:quantity,price:price);request.requestID=id
        s.orders[id]=Order(id:id,accountID:s.accountID,request:request,status:.filled,filled:quantity,cumulativeNotional:price,referencePrice:price,createdAt:time,updatedAt:time,ruleVersion:r.instrument.rules.version)
        let fill=Fill(id:"fill-\(id)",accountID:s.accountID,orderID:id,instrumentID:"TEST",side:side,quantity:quantity,price:price,fee:.zero,tax:.zero,time:time,quoteTime:time,source:"synthetic-stress-fixture",grade:.E1,estimatedExecution:false,liquidityEventID:"liquidity-\(n)",ruleVersion:r.instrument.rules.version,realized:.zero)
        s.equity.append(EquityPoint(time:time,value:s.cash["TWD"],flow:.zero))
        s.fills.append(fill);s.post(event:fill.id,currency:"TWD",debit:"cash",credit:"spot-clearing",amount:side == .buy ? price.negated:price,time:time);s.audit("fill","合成壓力資料",time:time,id:fill.id)
    }
    let clock=ContinuousClock(),start=clock.now
    try r.repo.save(s)
    let saved=clock.now
    s=try r.repo.load()!
    let read=clock.now
    #expect(s.fills.count<=100);#expect(s.orders.count<=200);#expect(s.ledger.count<=100);#expect(s.events.count<=100);#expect(s.equity.count<=1000)
    #expect((s.history?.fills ?? 0)+s.fills.count==100000)
    var queries:[Double]=[]
    func seconds(_ start:ContinuousClock.Instant,_ end:ContinuousClock.Instant)->Double{let c=start.duration(to:end).components;return Double(c.seconds)+Double(c.attoseconds)/1e18}
    for _ in 0..<30{let t=clock.now;let page=try r.repo.fillPage(limit:100);#expect(page.count==100);queries.append(seconds(t,clock.now))}
    let paged=clock.now
    let full=try r.repo.fullSnapshot()!
    let fullRead=clock.now
    #expect(try r.repo.equityPage(limit:100).count==100)
    #expect(abs((Analytics.equityMetrics(s).unit ?? 0)-1)<1e-12)
    #expect(Analytics.equityMetrics(s).drawdown==0)
    #expect(full.fills.count==100000);#expect(full.orders.count==100000);#expect(full.ledger.count==200002);#expect(full.cash==s.cash);#expect(full.equity.count==100001)
    let csv=try r.repo.csv(kind:"fills",time:200000)
    let exported=clock.now
    #expect(csv.filter{$0==10}.count==100000)
    let reportStart=clock.now
    let performance=try r.repo.performance()
    let reportSeconds=seconds(reportStart,clock.now)
    #expect(performance.currencies["TWD"]?.count==100000)
    #expect(performance.cycles["TWD"]?.closed==50000)
    #expect(performance.cycles["TWD"]?.flat==50000)
    #expect(reportSeconds<=3,"Full 100,000-row analytics report budget: 3 seconds")
    let rangeReport=try r.repo.performance(from:50001,until:60001)
    #expect(rangeReport.currencies["TWD"]?.count==10000)
    #expect(rangeReport.cycles["TWD"]?.closed==5000)
    let orders=try r.repo.orderPage(limit:100,search:"TEST");#expect(orders.count==100)
    let ctx=AccountContext(mode:.online),engine=try TradingEngine(context:ctx,repository:r.repo,initial:s)
    // The oldest id must remain idempotent after leaving the hot window and after restart.
    let old=try #require(full.orders["stress-0"])
    #expect(try await engine.submit(old.request,time:200000,context:ctx)==old.id)
    try await engine.ingest(r.quote(time:200000),now:200000,context:ctx)
    let concurrentSnapshot=Task{try await engine.fullSnapshot(context:ctx)}
    var writes:[Double]=[]
    for n in 0..<30{
        let t=clock.now
        var request=try r.buy(quantity:"1",id:"new-\(n)")
        request.timeInForce = .GTC
        _=try await engine.submit(request,time:200000,context:ctx)
        writes.append(seconds(t,clock.now))
    }
    let concurrentFull=try await concurrentSnapshot.value
    #expect((100000...100030).contains(concurrentFull.fills.count))
    try AccountRepository.validate(concurrentFull,mode:.online)
    let restart=try AccountRepository(root:r.root,mode:.online)
    let reopened=try restart.load()!
     #expect(reopened.orders.values.filter{$0.id.hasPrefix("new-") && $0.status == .filled}.count==30)
    #expect(try restart.fullSnapshot()?.fills.count==100030)
    #expect(try Analytics.fillTotals(reopened)["TWD"]?.count==100030)
    #expect(try Analytics.fillTotals(full)["TWD"]?.count==100000)
    #expect(Analytics.fillsCSV(full,time:200000)==String(decoding:csv,as:UTF8.self))
    let backup=try BackupService.export(full,password:nil,time:200000)
    let restored=try BackupService.validate(backup,expectedMode:.online,password:nil)
    #expect(restored.fills.count==100000);#expect(restored.orders.count==100000);#expect(restored.ledger.count==200002)
    #expect(restored.equity.count==100001)
    #expect(restored.cash==full.cash);#expect(restored.netFlows==full.netFlows)
    func p95(_ values:[Double])->Double{values.sorted()[Int(ceil(Double(values.count)*0.95))-1]}
    let cold=seconds(saved,read),query=p95(queries),write=p95(writes),report=seconds(fullRead,exported)
    #expect(cold<=3,"Original cold-load target: 3 seconds")
    #expect(query<=0.3,"Original page-interaction target: 300 ms p95")
    #expect(write<=0.15,"Original local order-feedback target: 150 ms p95")
    #expect(report<=3,"Full 100,000-row report budget: 3 seconds")
    let metrics:[String:Any]=["fills":100000,"bulkImportSeconds":seconds(start,saved),"hotLoadSeconds":cold,"fullIntegrityLoadSeconds":seconds(paged,fullRead),"csv100000Seconds":report,"analytics100000Seconds":reportSeconds,"page100P95Seconds":query,"orderWriteP95Seconds":write,"samplesPerP95":30,"equityPoints":100001,"hotEquityPoints":s.equity.count,"hotFills":s.fills.count,"hotOrders":s.orders.count,"platform":ProcessInfo.processInfo.operatingSystemVersionString,"passed":cold<=3 && query<=0.3 && write<=0.15 && report<=3 && reportSeconds<=3 && s.equity.count<=1000,"note":"Synthetic Release storage/report benchmark; simulator UI and signed iPhone acceptance remain separate"]
    let out=URL(fileURLWithPath:ProcessInfo.processInfo.environment["CHAI_REPORT_DIR"] ?? "/app/.reports")
    try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("stress-100000.json"))
    print("STRESS_METRICS",metrics)

}

private struct PathFixtures: MarketTransport {
    let paths: [String:String]
    func get(_ url: URL,headers: [String:String]) async throws -> Data {
        guard NetworkPolicy.permits(url,method:"GET",mode:.online),let json=paths[url.path] else{throw TradeError.unavailable("Unexpected fixture request path")}
        return Data(json.utf8)
    }
}
@Test(arguments:[ProviderID.fugle,.fugleFutures,.alpaca,.twelveData,.binance])
func allProviderQuoteSchemas(provider: ProviderID) async throws {
    var rules=RulePack(tick:try a("0.01"),quantityStep:try a("1"));rules.multiplier = .one
    let symbol: String,asset: AssetClass,paths: [String:String]
    switch provider {
    case .fugle,.fugleFutures:
        symbol=provider == .fugle ? "2330":"TXF202610";asset=provider == .fugle ? .taiwanStock:.future
        let family=provider == .fugle ? "stock":"futopt"
        paths=["/marketdata/v1.0/\(family)/intraday/quote/\(symbol)":#"{"lastPrice":100.01,"lastUpdated":1793059200000000,"bids":[{"price":100,"size":10}],"asks":[{"price":100.02,"size":12}]}"#]
    case .alpaca:
        symbol="AAPL";asset = .usStock
        paths=["/v2/stocks/AAPL/snapshot":#"{"latestTrade":{"t":"2026-10-27T00:00:00Z","p":100.01},"latestQuote":{"t":"2026-10-27T00:00:00Z","bp":100,"bs":10,"ap":100.02,"as":12}}"#]
    case .twelveData:
        symbol="EUR/USD";asset = .forex
        paths=["/quote":#"{"close":"1.12345","timestamp":1793059200,"status":"ok"}"#]
    case .binance:
        symbol="BTCUSDT";asset = .perpetual
        paths=["/fapi/v1/premiumIndex":#"{"markPrice":"100","indexPrice":"99","time":1793059200000}"#,"/fapi/v1/depth":#"{"lastUpdateId":123,"E":1793059200000,"bids":[["100","10"]],"asks":[["102","12"]]}"#,"/fapi/v1/ticker/24hr":#"{"lastPrice":"101"}"#]
    case .coinbase:return
    }
    let i=Instrument(id:"\(provider.rawValue):\(symbol)",symbol:symbol,name:"合成 fixture",asset:asset,currency:"USD",rules:rules,initialPrice:.zero,provider:provider)
    let p=MarketDataProvider(id:provider,credentials:ProviderCredentials(key:"SYNTHETIC_FIXTURE_KEY",secret:"SYNTHETIC_FIXTURE_SECRET"),transport:PathFixtures(paths:paths))
    let q=try await p.quote(i,now:1793059200)
    #expect(q.time==1793059200);#expect(q.quality == .realtime)
    if provider == .twelveData{#expect(q.grade == .E3);#expect(q.bids.isEmpty)}
    else{#expect(q.bids.count==1);#expect(q.asks.count==1)}
    if provider == .binance{#expect(q.last == (try a("101")));#expect(q.mark == (try a("100")))}
}

@Test func arithmeticCannotCreateAnUnrestorableDecimalOrZeroLotRatio() throws {
    let intermediate=try a("0.000000000001")*a("0.1")
    #expect(try JSONDecoder().decode(Amount.self,from:JSONEncoder().encode(intermediate)) == intermediate)
    #expect(throws:TradeError.self){try a("0.000000000001")/Amount.max}
    #expect(try !a("0.01").isMultiple(of:Amount.max))
    #expect(try Amount.max.isMultiple(of:a("0.000000000001")))
    let value=try a("0.00000001")*a("0.0001")
    #expect(try JSONDecoder().decode(Amount.self,from:JSONEncoder().encode(value)) == value)
}

@Test func backupRejectsInvalidCatalogBeforeReplacement() throws {
    let r=try Rig();var s=try r.repo.load()!;s.instruments=[]
    #expect(throws:TradeError.self){try r.repo.save(s)}
    #expect(try r.repo.load()?.instruments.count==1)
}

@Test func foreignCurrencyCapitalFlowIsNotPerformanceProfit() async throws {
    let r=try Rig()
    try await r.engine.setFX(FXRate(currency:"USD",base:"TWD",rate:a("30"),time:1000,source:"synthetic fixture"),context:r.context)
    try await r.engine.cashFlow(currency:"USD",amount:a("100"),time:1005,context:r.context)
    let s=await r.engine.snapshot()
    #expect(s.equity.last?.flow == (try a("3000")))
    #expect(Analytics.timeWeighted(s.equity).last! == 1)
}

@Test func postOnlyWithoutQuoteCannotTakeLiquidityAfterFirstSnapshot() async throws {
    let r=try Rig();var request=try r.buy(quantity:"1",price:"100");request.postOnly=true
    let id=try await r.engine.submit(request,time:1000,context:r.context)
    try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    let s=await r.engine.snapshot()
    #expect(s.orders[id]?.status == .cancelled);#expect(s.fills.isEmpty)
    #expect(try TradingEngine.available(s,currency:"TWD") == a("100000"))
}

@Test func sameTimestampTradeFeesRemainInTheEquityCurve()async throws{
    let r=try Rig(fee:"10");try await r.engine.ingest(r.quote(),now:1000,context:r.context)
    let request=try r.buy(quantity:"1",id:"equity-fee")
    _=try await r.engine.submit(request,time:1000,context:r.context)
    _=try await r.engine.submit(request,time:1000,context:r.context)
    let s=await r.engine.snapshot()
    #expect(s.equity.count==2);#expect(try s.equity.last?.value==a("99990"))
    #expect(abs((Analytics.timeWeighted(s).last.flatMap{$0} ?? 0)-0.9999)<1e-12)
}
