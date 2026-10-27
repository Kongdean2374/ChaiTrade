import Foundation
import Testing
@testable import ChaiTradeCore

private func newsFixture(title:String,link:String,summary:String="",date:String="Tue, 27 Oct 2026 10:35:00 GMT")->Data{
    Data("<rss><channel><item><title>\(title)</title><link>\(link)</link><description><![CDATA[\(summary)]]></description><pubDate>\(date)</pubDate></item></channel></rss>".utf8)
}
private actor PartialNewsTransport:MarketTransport{
    var requests:[URL]=[]
    func get(_ url:URL,headers:[String:String])async throws->Data{
        requests.append(url)
        if url==PublicNewsSource.twse.url{throw MarketDataFailure(.rateLimited,retryAfter:60)}
        if url==PublicNewsSource.cryptoSlate.url{return newsFixture(title:"Bitcoin market discussion",link:"https://cryptoslate.com/synthetic-protocol-only/",summary:"Synthetic protocol fixture; no real event.")}
        throw MarketDataFailure(.unauthorized)
    }
}
@Test func publisherFeedsKeepMarketsDatesLinksAndAvoidAmbiguousTickerAssociations()throws{
    let instruments=try InstrumentCatalog.builtIn(mode:.online),now:Int64=1_793_148_000
    let twse=try PublicNewsFeed.parse(newsFixture(title:"合成測試 2330 台積電",link:"/rwd/zh/news/newsDetail/synthetic-only"),source:.twse,now:now,instruments:instruments)
    #expect(twse.count==1 && twse[0].url?.absoluteString=="https://www.twse.com.tw/rwd/zh/news/newsDetail/synthetic-only")
    #expect(twse[0].source==PublicNewsSource.twse.label && twse[0].markets==[.stocks] && twse[0].origin == .real)
    #expect(twse[0].instrumentIDs==["fugle:2330"])
    #expect(MarketNewsSelection.filter(twse,instruments:instruments,market:.stocks,category:"美股",watchlist:[],favoritesOnly:false,now:now,origin:.real).isEmpty)
    #expect(MarketNewsSelection.filter(twse,instruments:instruments,market:.crypto,category:"現貨",watchlist:[],favoritesOnly:false,now:now,origin:.real).isEmpty)
    let crypto=try PublicNewsFeed.parse(newsFixture(title:"Does this affect Bitcoin?",link:"https://cryptoslate.com/synthetic-only/",summary:"ETH here means Exponential Time Hypothesis, not a currency."),source:.cryptoSlate,now:now,instruments:instruments)
    #expect(crypto.count==1 && crypto[0].instrumentIDs.contains("coinbase:BTC-USD"))
    #expect(!crypto[0].instrumentIDs.contains("coinbase:ETH-USD"))
    let ambiguous=try PublicNewsFeed.parse(newsFixture(title:"ETH means a mathematical hypothesis",link:"https://cryptoslate.com/synthetic-ambiguous/"),source:.cryptoSlate,now:now,instruments:instruments)
    #expect(ambiguous[0].instrumentIDs.isEmpty)
    for link in ["https://evil.example/article","https://cryptoslate.com@evil.example/article","javascript:alert(1)","//evil.example/article"]{
        #expect(try PublicNewsFeed.parse(newsFixture(title:"Synthetic",link:link),source:.cryptoSlate,now:now).isEmpty)
    }
    #expect(try PublicNewsFeed.parse(newsFixture(title:"Future",link:"https://cryptoslate.com/future/",date:"Tue, 27 Oct 2099 10:35:00 GMT"),source:.cryptoSlate,now:now).isEmpty)
    #expect(throws:TradeError.self){try PublicNewsFeed.parse(Data("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///secret'>]><rss/>".utf8),source:.cryptoSlate,now:now)}
}
@Test func feedFailuresRemainIndependentAndOfflineNeverSendsARequest()async throws{
    let transport=PartialNewsTransport()
    await #expect(throws:TradeError.self){try await PublicNewsFeed.fetchAll(mode:.offline,transport:transport,now:1_793_148_000)}
    #expect(await transport.requests.isEmpty)
    let results=try await PublicNewsFeed.fetchAll(mode:.online,transport:transport,now:1_793_148_000)
    #expect(results.count==3)
    #expect(results.first{$0.source == .twse}?.issue?.contains(MarketIssueKind.rateLimited.label)==true)
    #expect(results.first{$0.source == .federalReserve}?.issue != nil)
    #expect(results.first{$0.source == .cryptoSlate}?.stories.count==1)
    #expect(await transport.requests.count==3)
    for source in PublicNewsSource.allCases{#expect(NetworkPolicy.permits(source.url,method:"GET",mode:.online));#expect(!NetworkPolicy.permits(source.url,method:"POST",mode:.online));#expect(!NetworkPolicy.permits(source.url,method:"GET",mode:.offline))}
    for path in ["https://cryptoslate.com/private/","https://cryptoslate.com/feed/?redirect=evil","https://www.twse.com.tw/rwd/zh/news/feed?type=other"]{#expect(!NetworkPolicy.permits(URL(string:path)!,method:"GET",mode:.online))}
}
@Test(.enabled(if:ProcessInfo.processInfo.environment["CHAI_LIVE"]=="1"),arguments:[PublicNewsSource.twse,.cryptoSlate])
func livePublisherRSSProvidesActualPublishedHeadlinesAndOriginalLinks(source:PublicNewsSource)async throws{
    let now=Int64(Date().timeIntervalSince1970),stories=try await PublicNewsFeed.fetch(source:source,mode:.online,transport:ReadOnlyTransport(mode:.online),now:now,instruments:InstrumentCatalog.builtIn(mode:.online))
    try #require(!stories.isEmpty)
    #expect(stories.allSatisfy{$0.origin == .real && $0.publishedAt<=now && $0.url?.scheme=="https" && $0.source==source.label && !$0.title.isEmpty})
    print("LIVE_PUBLIC_NEWS_SOURCE_HTTP_SUCCESS",source.rawValue,"published stories",stories.count,"publisher RSS only; no article bodies, images, generation service or fixture")
}
