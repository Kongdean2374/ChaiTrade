import Foundation
import Testing
@testable import ChaiTradeCore

@Test func realIdentityCatalogIsOfflineCompleteAndNeverMergesVenues()throws{
    let offline=try Simulation.catalog(),online=try Providers.catalog()
    #expect(offline.count==125);#expect(Set(offline.map(\.id)).count==125)
    #expect(offline.filter{$0.asset != .index}.count==120)
    #expect(offline.filter{$0.asset == .taiwanStock}.count==30)
    #expect(offline.filter{$0.asset == .usStock}.count==30)
    #expect(offline.filter{$0.asset == .etf}.count==20)
    #expect(offline.filter{$0.asset == .crypto}.count==20)
    #expect(offline.allSatisfy{$0.provider==nil && $0.identity != nil && !$0.name.contains("島嶼") && !$0.symbol.contains("CRYPTO0")})
    for (symbol,name) in [("2330","台積電"),("0050","元大台灣50"),("BTC-USD","Bitcoin 比特幣"),("ETH-USD","Ethereum 以太幣")]{
        #expect(offline.contains{$0.symbol==symbol && $0.name==name})
        #expect(online.contains{$0.symbol==symbol && $0.name==name})
    }
    let stock=try #require(offline.first{$0.symbol=="2330"}),etf=try #require(offline.first{$0.symbol=="0050"})
    for (price,tick) in [("9.99","0.01"),("10","0.05"),("50","0.1"),("100","0.5"),("500","1"),("1000","5")]{#expect(try stock.rules.tick(at:Amount(price))==Amount(tick))}
    #expect(try etf.rules.tick(at:Amount("49.99"))==Amount("0.01"));#expect(try etf.rules.tick(at:Amount("50"))==Amount("0.05"))
    #expect(stock.identity?.boardLot==1000)
    #expect(online.filter{$0.asset == .crypto}.allSatisfy{$0.currency=="USD" && $0.provider == .coinbase})
    #expect(online.allSatisfy{$0.rules.carrySchedule==nil})
}
@Test func legacyCatalogMigrationKeepsOwnedIdentityCashHistoryAndPrice()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.offline)
    var legacy=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:1000)
    legacy.instruments=try Simulation.legacyCatalog();legacy.simulation=SimulationState();legacy.productPreferences=nil
    let repo=try AccountRepository(root:root,mode:.offline),engine=try TradingEngine(context:ctx,repository:repo,initial:legacy)
    try await engine.initializeQuotes(context:ctx)
    let old=legacy.instruments[0]
    let request=OrderRequest(instrumentID:old.id,side:.buy,kind:.market,quantity:.one)
    _=try await engine.submit(request,time:legacy.simulation!.time,context:ctx)
    try await engine.toggleWatch(old.id,context:ctx)
    try await engine.recordJournal(JournalEntry(id:"migration-note",text:"Synthetic migration journal",tags:"",time:1000),context:ctx)
    let before=try await engine.fullSnapshot(context:ctx),price=try Simulation.price(old,at:legacy.simulation!.time-3600,state:legacy.simulation!)
    try await engine.prepareProductExperience(context:ctx)
    let after=try await engine.fullSnapshot(context:ctx)
    #expect(after.cash==before.cash);#expect(after.fills.map(\.id)==before.fills.map(\.id));#expect(after.watchlist==before.watchlist)
    #expect(after.journals.map(\.id)==before.journals.map(\.id));#expect(after.positions[old.id]?.quantity==before.positions[old.id]?.quantity)
    let preserved=try #require(after.instruments.first{$0.id==old.id})
    #expect(preserved.name==old.name);#expect(preserved.rules==old.rules);#expect(preserved.initialPrice==old.initialPrice)
    #expect(preserved.identity?.legacy==true);#expect(after.instruments.contains{$0.id=="SIM:TWSE:2330" && $0.id != old.id})
    #expect(try Simulation.price(preserved,at:legacy.simulation!.time-3600,state:after.simulation!)==price)
    try await engine.prepareProductExperience(context:ctx)
    #expect(await engine.snapshot().instruments.count==250)
    let restored=try AccountRepository(root:root,mode:.offline).load()!
    #expect(restored.positions[old.id]?.quantity==before.positions[old.id]?.quantity)
    #expect(restored.instruments.count==250)
}
@Test func marketBrowsingPersistsIndependentlyWithoutMovingMoney()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.online)
    let initial=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    let repo=try AccountRepository(root:root,mode:.online),engine=try TradingEngine(context:ctx,repository:repo,initial:initial)
    var stocks=MarketBrowsingState();stocks.search="2330";stocks.category="台股";stocks.sort = .name;stocks.selectedID="fugle:2330";stocks.scrollID=stocks.selectedID;stocks.recent=[stocks.selectedID!]
    var crypto=MarketBrowsingState();crypto.search="ETH";crypto.category="現貨";crypto.sort = .volume;crypto.selectedID="coinbase:ETH-USD";crypto.recent=[crypto.selectedID!]
    try await engine.saveMarketBrowsing(stocks,market:.stocks,activate:true,context:ctx)
    try await engine.saveMarketBrowsing(crypto,market:.crypto,activate:true,context:ctx)
    let saved=try repo.load()!
    #expect(saved.cash==initial.cash);#expect(saved.orders.isEmpty && saved.fills.isEmpty)
    #expect(saved.productPreferences?.markets["stocks"]==stocks)
    #expect(saved.productPreferences?.markets["crypto"]==crypto)
    #expect(saved.productPreferences?.activeMarket == .crypto)
    await #expect(throws:TradeError.self){try await engine.saveMarketBrowsing(crypto,market:.stocks,activate:true,context:ctx)}
    await #expect(throws:TradeError.self){try await engine.saveMarketBrowsing(stocks,market:.stocks,context:AccountContext(mode:.online))}
}
@Test func simulationNewsIsDiverseDeterministicCausalAndNeverLeaksFuture()throws{
    let state=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:1000),sim=state.simulation!
    let stories=SimulationNews.stories(state:sim,from:sim.time-7*86400,limit:80)
    #expect(stories.count>=40);#expect(Set(stories.map(\.kind)).count>=6)
    #expect(stories.allSatisfy{$0.publishedAt<=sim.time && $0.origin == .simulated && $0.label=="模擬情境，非真實新聞" && !$0.instrumentIDs.isEmpty})
    let replay=try JSONDecoder().decode(SimulationState.self,from:AccountRepository.encode(sim))
    #expect(try AccountRepository.encode(stories)==AccountRepository.encode(SimulationNews.stories(state:replay,from:sim.time-7*86400,limit:80)))
    let shock=try #require(stories.first{abs($0.logPriceImpact ?? 0)>0.001 && $0.kind != "halt"})
    let instrument=try #require(state.instruments.first{shock.instrumentIDs.contains($0.id)})
    var during=sim;during.time=shock.publishedAt+600
    var noNews=during;noNews.newsFrom=nil;noNews.newsUniverse=nil
    let changed=try Simulation.price(instrument,at:during.time,state:during),reference=try Simulation.price(instrument,at:during.time,state:noNews)
    #expect(changed != reference)
    let quote=try Simulation.quote(instrument,state:during)
    #expect(quote.causalEventIDs?.contains(shock.id)==true)
    #expect(Simulation.stepVolume(instrument,at:during.time,state:during) != Simulation.stepVolume(instrument,at:during.time,state:noNews))
    let early=SimulationNews.stories(state:during,from:during.time-86400,through:during.time+86400)
    #expect(early.allSatisfy{$0.publishedAt<=during.time})
    let candle=try #require(Simulation.candles(instrument,state:during,interval:60,count:1).last)
    var high = -Double.infinity,low=Double.infinity,volume=0.0
    for time in stride(from:candle.time,through:during.time,by:5) where instrument.rules.isOpen(at:time){let price=try Simulation.price(instrument,at:time,state:during).displayDouble;high=max(high,price);low=min(low,price);volume += Simulation.stepVolume(instrument,at:time,state:during)}
    #expect(candle.high==high);#expect(candle.low==low);#expect(abs((candle.volume ?? 0)-volume)<1e-8)
}

@Test func visibleQuoteRequestsAreBoundedDeduplicatedAndDiscardOldMarketAndEpoch()async throws{
    let scheduler=VisibleQuoteScheduler(),a=AccountContext(mode:.online),b=AccountContext(mode:.offline)
    await scheduler.demand(context:a,visible:["BTC","ETH"],selected:"BTC",protected:["HELD"])
    let first=await scheduler.next(context:a,now:1000,limit:3)
    #expect(Set(first.map(\.instrumentID))==["BTC","ETH","HELD"])
    #expect(await scheduler.next(context:a,now:1000).isEmpty)
    let btc=try #require(first.first{$0.instrumentID=="BTC"}),eth=try #require(first.first{$0.instrumentID=="ETH"})
    await scheduler.demand(context:a,visible:["ETH"],selected:"ETH",protected:[])
    #expect(await scheduler.complete(btc,now:1001)==false)
    #expect(await scheduler.complete(eth,now:1001)==true)
    #expect(await scheduler.next(context:a,now:1009).isEmpty)
    let retry=try #require(await scheduler.next(context:a,now:1011).first)
    #expect(await scheduler.complete(retry,now:1011,failure:MarketDataFailure(.rateLimited,retryAfter:60)))
    #expect(await scheduler.next(context:a,now:1070).isEmpty)
    let pending=try #require(await scheduler.next(context:a,now:1071).first)
    await scheduler.demand(context:b,visible:["SIM:ETH"],selected:"SIM:ETH",protected:[])
    #expect(await scheduler.complete(pending,now:1072)==false)
    #expect(await scheduler.next(context:a,now:1072).isEmpty)
    let replacement=await scheduler.next(context:b,now:1072);#expect(replacement.count==1)
    #expect(replacement.first?.instrumentID=="SIM:ETH")
}
@Test func everyHTTPFailureKeepsItsUserActionAndRetryAfter()throws{
    #expect(HTTPMarketFailure.classify(status:401,retryAfter:nil).kind == .unauthorized)
    #expect(HTTPMarketFailure.classify(status:403,retryAfter:nil).kind == .unauthorized)
    #expect(HTTPMarketFailure.classify(status:404,retryAfter:nil).kind == .unsupported)
    #expect(HTTPMarketFailure.classify(status:503,retryAfter:nil).kind == .maintenance)
    #expect(HTTPMarketFailure.classify(status:429,retryAfter:"120").retryAfter==120)
    let now=Date(timeIntervalSince1970:1000),f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone = .gmt;f.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
    #expect(HTTPMarketFailure.classify(status:429,retryAfter:f.string(from:now.addingTimeInterval(90)),now:now).retryAfter==90)
    for kind in [MarketIssueKind.missingKey,.unauthorized,.unsupported,.rateLimited,.connectionFailed,.closed,.delayed,.stale]{#expect(!kind.nextStep.isEmpty)}
}
