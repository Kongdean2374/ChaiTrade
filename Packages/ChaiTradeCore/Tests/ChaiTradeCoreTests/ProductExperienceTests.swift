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

@Test func taiwanBoardsUseIndependentBooksUnitsAndEffectiveDatedSessions()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.offline)
    var state=try TradingEngine.initial(mode:.offline,capital:Amount("100000000"),time:1000)
    let instrument=try #require(state.instruments.first{$0.symbol=="2330"});state.instruments=[instrument];state.simulation!.newsFrom=nil;state.simulation!.newsAccountingFrom=nil
    let engine=try TradingEngine(context:ctx,repository:AccountRepository(root:root,mode:.offline),initial:state)
    try await engine.initializeQuotes(context:ctx)
    var snapshot=await engine.snapshot()
    let regular=try #require(snapshot.quotes[instrument.id]),odd=try #require(snapshot.quotes[instrument.quoteKey(board:.oddLot)])
    #expect(regular.board == .regular && odd.board == .oddLot)
    #expect(try regular.asks[0].quantity.isMultiple(of:(try Amount(1000))))
    #expect(odd.asks[0].quantity < (try Amount(1000)))
    var request=OrderRequest(instrumentID:instrument.id,side:.buy,kind:.limit,quantity:(try Amount(10)),price:odd.asks[0].price);request.board = .oddLot;request.timeInForce = .DAY
    _=try await engine.submit(request,time:state.simulation!.time,context:ctx)
    snapshot=await engine.snapshot();#expect(snapshot.positions[instrument.id]?.quantity==(try Amount(10)))
    let regularRequest=OrderRequest(instrumentID:instrument.id,side:.buy,kind:.market,quantity:(try Amount(1000)))
    _=try await engine.submit(regularRequest,time:state.simulation!.time,context:ctx)
    snapshot=await engine.snapshot();#expect(snapshot.positions[instrument.id]?.quantity==(try Amount(1010)))
    #expect(snapshot.fills.filter{$0.orderID==regularRequest.requestID}.allSatisfy{(try? $0.quantity.isMultiple(of:(try Amount(1000))))==true})
    #expect(snapshot.fills.filter{$0.orderID==request.requestID}.allSatisfy{$0.liquidityEventID.contains("oddLot")})
    request.requestID=UUID().uuidString;request.quantity=(try Amount(1000))
    await #expect(throws:TradeError.self){try await engine.submit(request,time:state.simulation!.time,context:ctx)}
    request.quantity=(try Amount(10));request.kind = .market
    await #expect(throws:TradeError.self){try await engine.submit(request,time:state.simulation!.time,context:ctx)}
    request.kind = .limit;request.timeInForce = .GTC
    await #expect(throws:TradeError.self){try await engine.submit(request,time:state.simulation!.time,context:ctx)}
    let parser=ISO8601DateFormatter()
    let before=Int64(parser.date(from:"2026-10-27T01:05:00Z")!.timeIntervalSince1970)
    let after=Int64(parser.date(from:"2026-12-07T01:05:00Z")!.timeIntervalSince1970)
    #expect(instrument.boardIsOpen(.regular,at:before));#expect(!instrument.boardIsOpen(.oddLot,at:before));#expect(instrument.boardIsOpen(.oddLot,at:after))
}

@Test func quoteRecoveryCannotInvalidateFreshRestOrResetConsumedLiquidity()async throws{
    let ctx=AccountContext(mode:.online),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var state=try TradingEngine.initial(mode:.online,capital:(try Amount(10000)),time:1000)
    let instrument=Instrument(id:"TEST",symbol:"TEST",name:"合成驗證商品",asset:.crypto,currency:"TWD",rules:try RulePack(tick:Amount("0.01"),quantityStep:.one),initialPrice:(try Amount(100)));state.instruments=[instrument]
    let engine=try TradingEngine(context:ctx,repository:AccountRepository(root:root,mode:.online),initial:state)
    let quote=Quote(instrumentID:instrument.id,source:"REST",time:1000,sequence:10,last:(try Amount(100)),bids:[Level((try Amount(99)),(try Amount(2)))],asks:[Level((try Amount(100)),(try Amount(2)))])
    try await engine.ingest(quote,now:1000,context:ctx)
    try await engine.markMonitoringGap(instrumentID:instrument.id,time:1000,expectedSourcePrefix:"WS",context:ctx)
    #expect(await engine.snapshot().quotes[instrument.id]?.valid==true)
    _=try await engine.submit(OrderRequest(instrumentID:instrument.id,side:.buy,kind:.market,quantity:(try Amount(2))),time:1000,context:ctx)
    try await engine.markMonitoringGap(instrumentID:instrument.id,time:1000,context:ctx)
    try await engine.ingest(quote,now:1000,context:ctx)
    #expect(await engine.snapshot().quotes[instrument.id]?.valid==true)
    _=try await engine.submit(OrderRequest(instrumentID:instrument.id,side:.buy,kind:.market,quantity:(try Amount(2))),time:1000,context:ctx)
    #expect(await engine.snapshot().positions[instrument.id]?.quantity==(try Amount(2)))
}

@Test func officialNewsParserRejectsWrongHostFutureAndOfflineTransportUse()async throws{
    let xml="""
    <?xml version="1.0"?><rss><channel>
    <item><title>Official synthetic parser fixture</title><link>https://www.federalreserve.gov/newsevents/test.htm</link><description><![CDATA[<p>Publisher summary only.</p>]]></description><pubDate>Tue, 27 Oct 2026 12:00:00 GMT</pubDate></item>
    <item><title>Wrong host</title><link>https://example.com/test</link><pubDate>Tue, 27 Oct 2026 12:00:00 GMT</pubDate></item>
    <item><title>Future</title><link>https://www.federalreserve.gov/future.htm</link><pubDate>Tue, 27 Oct 2026 14:00:00 GMT</pubDate></item>
    </channel></rss>
    """
    let date=Int64(ISO8601DateFormatter().date(from:"2026-10-27T13:00:00Z")!.timeIntervalSince1970)
    let stories=try PublicNewsFeed.parseFederalReserve(Data(xml.utf8),now:date)
    #expect(stories.count==1);#expect(stories[0].summary=="Publisher summary only.");#expect(stories[0].origin == .real)
    actor NeverTransport:MarketTransport{var called=false;func get(_ url:URL,headers:[String:String])async throws->Data{called=true;return Data()}}
    let transport=NeverTransport()
    await #expect(throws:TradeError.self){try await PublicNewsFeed.fetch(mode:.offline,transport:transport,now:date)}
    #expect(await transport.called==false)
}

@Test(arguments:["dividend","split"])
func simulationCorporateNewsPostsOnceAcrossCheckpointRestartAndSharesItsID(kind:String)async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.offline)
    var initial=try TradingEngine.initial(mode:.offline,capital:Amount("100000000"),time:1000)
    let base=initial.simulation!,bucket=base.time/SimulationNews.period
    let story=try #require((bucket...bucket+200).compactMap{SimulationNews.story(bucket:$0,state:base)}.first{$0.kind==kind})
    let id=try #require(story.instrumentIDs.first),index=try #require(initial.instruments.firstIndex{$0.id==id})
    var instrument=initial.instruments[index];instrument.rules.weekdaysOnly=false;instrument.rules.holidays=[];instrument.rules.openMinute=0;instrument.rules.closeMinute=1440;instrument.rules.settlementBusinessDays=0
    // Restrict this isolated accounting fixture to the affected identity; the immutable event universe remains intact.
    initial.instruments=[instrument];initial.simulation!.time=story.publishedAt-5;initial.simulation!.newsAccountingFrom=story.publishedAt
    let repo=try AccountRepository(root:root,mode:.offline),engine=try TradingEngine(context:context,repository:repo,initial:initial)
    try await engine.initializeQuotes(context:context)
    let snapshot=await engine.snapshot(),board:TradingBoard?=instrument.usesTaiwanBoards ? .oddLot:nil
    let q=try #require(snapshot.quotes[instrument.quoteKey(board:board)])
    var request=OrderRequest(instrumentID:id,side:.buy,kind:.limit,quantity:try Amount(10),price:q.asks[0].price);request.board=board;request.timeInForce = .DAY
    _=try await engine.submit(request,time:initial.simulation!.time,context:context)
    let owned=await engine.snapshot();#expect(owned.positions[id]?.quantity == (try Amount(10)))
    _=try await engine.advance(to:story.publishedAt,context:context)
    let acted=await engine.snapshot(),action=try #require(acted.lifecycle?.actions.first{$0.id==story.id})
    #expect(action.source.contains(story.id));#expect(acted.events.contains{$0.id=="published-"+story.id})
    if kind=="split"{
        #expect(acted.positions[id]?.quantity == (try Amount(20)))
        #expect(try acted.positions[id]!.average*Amount(2)==owned.positions[id]!.average)
        let expected=try Simulation.price(instrument,at:story.publishedAt,state:acted.simulation!)
        #expect(acted.quotes[id]?.last==expected)
        #expect(acted.quotes[id]?.causalEventIDs?.contains(story.id)==true)
    }else{
        #expect(acted.lifecycle?.settlements.first{$0.id=="dividend-"+story.id}?.receivable == (try Amount("2.5")))
        let until=try #require(story.endsAt)
        var time=acted.simulation!.time
        while time<until{time=try await engine.advance(to:until,context:context)}
        let paid=await engine.snapshot();#expect(paid.lifecycle?.settlements.first{$0.id=="dividend-"+story.id}?.completedAt != nil)
        #expect(paid.cash[instrument.currency] == (try (owned.cash[instrument.currency] ?? .zero)+Amount("2.5")))
    }
    let before=try await engine.fullSnapshot(context:context),nextContext=AccountContext(mode:.offline)
    let restarted=try TradingEngine(context:nextContext,repository:AccountRepository(root:root,mode:.offline),initial:repo.load()!)
    _=try await restarted.advance(to:before.simulation!.time,context:nextContext)
    let after=try await restarted.fullSnapshot(context:nextContext)
    #expect(after.cash==before.cash);#expect(after.lifecycle?.actions.filter{$0.id==story.id}.count==1)
    #expect(after.ledger.filter{$0.eventID==story.id}.count==before.ledger.filter{$0.eventID==story.id}.count)
}

@Test func legacyOnlineUnitsNeverChangeUntilExplicitFlatUpgrade()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.online)
    var initial=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    var old=try #require(initial.instruments.first{$0.symbol=="2330"})
    old.identity=nil;old.rules=RulePack(tick:try Amount("0.01"),quantityStep:.one);old.rules.version="legacy-owned-rule"
    initial.instruments=[old];initial.productPreferences=nil
    let repository=try AccountRepository(root:root,mode:.online),engine=try TradingEngine(context:context,repository:repository,initial:initial)
    let quote=Quote(instrumentID:old.id,source:"synthetic-legacy-account",time:1000,sequence:1,last:try Amount("100"),bids:[Level(try Amount("99"),try Amount("10000"))],asks:[Level(try Amount("100"),try Amount("10000"))])
    try await engine.ingest(quote,now:1000,context:context)
    let request=OrderRequest(instrumentID:old.id,side:.buy,kind:.limit,quantity:.one,price:try Amount("99"))
    _=try await engine.submit(request,time:1000,context:context)
    try await engine.prepareProductExperience(context:context)
    let migrated=await engine.snapshot(),identity=try #require(migrated.instruments.first{$0.id==old.id})
    #expect(identity.rules==old.rules);#expect(identity.identity?.catalogVersion==0);#expect(!identity.usesTaiwanBoards)
    #expect(migrated.orders[request.requestID]?.request.quantity == .one)
    await #expect(throws:TradeError.self){try await engine.adoptCatalogRules(instrumentID:old.id,context:context)}
    try await engine.cancel(id:request.requestID,time:1001,context:context)
    let before=await engine.snapshot()
    try await engine.adoptCatalogRules(instrumentID:old.id,context:context)
    let upgraded=await engine.snapshot(),product=try #require(upgraded.instruments.first{$0.id==old.id})
    #expect(product.usesTaiwanBoards);#expect(product.identity?.catalogVersion==1)
    #expect(try product.rules.tick(at:Amount("1000"))==Amount("5"))
    #expect(upgraded.cash==before.cash);#expect(upgraded.orders[request.requestID]?.status == .cancelled)
    #expect(upgraded.quotes[old.id]==nil);#expect(upgraded.fills.map(\.id)==before.fills.map(\.id))
}
