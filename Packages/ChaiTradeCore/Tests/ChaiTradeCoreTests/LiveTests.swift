import Foundation
import Testing
@testable import ChaiTradeCore

@Test(.enabled(if:ProcessInfo.processInfo.environment["CHAI_LIVE"]=="1"))
func liveCoinbaseReadOnlyAdapter() async throws {
    let provider=try MarketDataProvider(id:.coinbase,credentials:ProviderCredentials(),transport:ReadOnlyTransport(mode:.online))
    let instrument=try Providers.catalog().first!
    let time=Int64(Date().timeIntervalSince1970)
    let quote=try await provider.quote(instrument,now:time)
    #expect(quote.instrumentID==instrument.id)
    #expect(quote.last > .zero)
    #expect(!quote.bids.isEmpty && !quote.asks.isEmpty)
    #expect(quote.grade == .E1)
    let candles=try await provider.candles(instrument,interval:60,now:time)
    #expect(!candles.isEmpty)
    #expect(candles.map(\.time)==candles.map(\.time).sorted())
    print("LIVE_COINBASE_ADAPTER_HTTP_SUCCESS: ticker, level2 snapshot, candles. Market values not retained.")
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["CHAI_LIVE"]=="1"))
func liveVisibleBTCETHContinuousQuotesChartsRecoveryAndLocalExecution()async throws{
    let transport=try ReadOnlyTransport(mode:.online),provider=MarketDataProvider(id:.coinbase,credentials:ProviderCredentials(),transport:transport)
    let catalog=try Providers.catalog(),btc=try #require(catalog.first{$0.symbol=="BTC-USD"}),eth=try #require(catalog.first{$0.symbol=="ETH-USD"})
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.online)
    var initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount("100000"),time:Int64(Date().timeIntervalSince1970));initial.instruments=[btc,eth]
    let engine=try TradingEngine(context:context,repository:AccountRepository(root:root,mode:.online),initial:initial,wallClock:{Int64(Date().timeIntervalSince1970)})
    var sequences:[String:Int64]=[:],timestamps:[String:Int64]=[:]
    for round in 0..<3{
        for instrument in [btc,eth]{
            print("LIVE_PRODUCT_STAGE quote",instrument.symbol,round)
            let requestedAt=Int64(Date().timeIntervalSince1970),quote=try await provider.quote(instrument,now:requestedAt,includeSummary:true)
            let now=Int64(Date().timeIntervalSince1970)
            print("LIVE_QUOTE_TIMING_SECONDS",instrument.symbol,"request",requestedAt,"receipt",quote.receivedAt,"checked",now,"source",quote.time)
            print("LIVE_QUOTE_QUALITY",instrument.symbol,quote.quality.rawValue,quote.grade.rawValue,"valid",quote.valid,"issue",quote.sourceIssue?.rawValue ?? "none","ageSeconds",now-quote.time,"maximumAge",quote.maximumAge)
            try #require(quote.valid && quote.quality == .realtime && quote.grade == .E1)
            try #require(quote.time<=now+5 && now-quote.time<=quote.maximumAge)
            try #require(quote.receivedAt>=requestedAt && abs(now-quote.receivedAt)<=1)
            #expect(!quote.bids.isEmpty && !quote.asks.isEmpty && quote.bids[0].price<quote.asks[0].price)
            #expect(quote.summary?.reference != nil && quote.summary?.volume != nil)
            if let previous=sequences[instrument.id]{#expect(quote.sequence>=previous)}
            sequences[instrument.id]=quote.sequence;timestamps[instrument.id]=quote.time
            try await engine.ingest(quote,now:now,context:context)
        }
        if round==0{try await engine.markMonitoringGap(instrumentID:btc.id,time:Int64(Date().timeIntervalSince1970),context:context);#expect(await engine.snapshot().quotes[btc.id]?.valid==false)}
        if round<2{try await Task.sleep(for:.seconds(1))}
    }
    let latest=await engine.snapshot();#expect(latest.quotes.count==2);#expect(latest.quotes[btc.id]?.valid==true)
    for instrument in [btc,eth]{print("LIVE_PRODUCT_STAGE history",instrument.symbol);let candles=try await provider.history(instrument,interval:60,count:40,now:Int64(Date().timeIntervalSince1970));#expect(candles.count>=30);#expect(candles.allSatisfy{$0.high>=max($0.open,$0.close) && $0.low<=min($0.open,$0.close) && $0.volume != nil});#expect(candles.map(\.time)==candles.map(\.time).sorted())}
    // Refresh after chart reads: an earlier successful quote must not grant indefinite execution.
    let requestedAt=Int64(Date().timeIntervalSince1970),quote=try await provider.quote(btc,now:requestedAt,includeSummary:true)
    let now=Int64(Date().timeIntervalSince1970);try await engine.ingest(quote,now:now,context:context)
    var request=OrderRequest(instrumentID:btc.id,side:.buy,kind:.market,quantity:try Amount("0.0001"));request.requestID="live-local-intent-only"
    _=try await engine.submit(request,time:now,context:context);_=try await engine.submit(request,time:now,context:context)
    let filled=await engine.snapshot();#expect(filled.orders.count==1);#expect(filled.positions[btc.id]?.quantity==request.quantity)
    #expect(try sum(filled.fills.map(\.quantity))==request.quantity)
    #expect((filled.cash["USD"] ?? .zero)<(initial.cash["USD"] ?? .zero))
    print("LIVE_PRODUCT_STAGE official_news")
    let news=try await PublicNewsFeed.fetch(mode:.online,transport:transport,now:Int64(Date().timeIntervalSince1970));#expect(!news.isEmpty);#expect(news.allSatisfy{$0.origin == .real && $0.url?.scheme=="https"})
    print("LIVE_PRODUCT_E2E_HTTP_SUCCESS: BTC + ETH three quote/stat rounds, timestamps, two real K-line histories, local gap recovery, one idempotent local intent and official RSS. No external trade endpoint or fixture used.")
}
