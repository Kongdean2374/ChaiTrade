import Foundation
import Testing
@testable import ChaiTradeCore

@Test func newsSectionsSeparateSpotContractsStockClassesOriginAndFuture()throws{
    let account=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:0),sim=account.simulation!
    let stories=SimulationNews.stories(state:sim,from:sim.time-60*86400,limit:500)
    func selected(_ market:MarketDomain,_ category:String,_ watch:Set<String>=[],_ favorite:Bool=false,_ origin:NewsOrigin = .simulated)->[MarketNewsStory]{MarketNewsSelection.filter(stories,instruments:account.instruments,market:market,category:category,watchlist:watch,favoritesOnly:favorite,now:sim.time,origin:origin)}
    let spot=selected(.crypto,"現貨"),contracts=selected(.crypto,"合約"),taiwan=selected(.stocks,"台股"),us=selected(.stocks,"美股"),etfs=selected(.stocks,"ETF")
    #expect(!spot.isEmpty && !contracts.isEmpty && !taiwan.isEmpty && !us.isEmpty && !etfs.isEmpty)
    for (items,asset) in [(spot,AssetClass.crypto),(contracts,.perpetual),(taiwan,.taiwanStock),(us,.usStock),(etfs,.etf)]{
        let eligible=Set(account.instruments.filter{$0.asset==asset}.map(\.id))
        #expect(items.allSatisfy{!Set($0.instrumentIDs).isDisjoint(with:eligible) && $0.origin == .simulated && $0.publishedAt<=sim.time})
    }
    let first=try #require(spot.first),cryptoIDs=Set(account.instruments.filter{$0.asset == .crypto}.map(\.id)),id=try #require(first.instrumentIDs.first{cryptoIDs.contains($0)})
    #expect(selected(.crypto,"現貨",[id],true).allSatisfy{$0.instrumentIDs.contains(id)})
    #expect(selected(.crypto,"現貨",[],false,.real).isEmpty)
    let stockID=try #require(account.instruments.first{$0.symbol=="2330"}?.id)
    #expect(selected(.crypto,"現貨",[stockID],true).isEmpty)
    var future=first;future.id="synthetic-future-not-real-news";future.publishedAt=sim.time+60
    #expect(MarketNewsSelection.filter([future],instruments:account.instruments,market:.crypto,category:"現貨",watchlist:[],favoritesOnly:false,now:sim.time,origin:.simulated).isEmpty)
}
@Test func warmedNewsCacheCannotIgnoreAFutureEnableBoundaryInAnotherAccount()throws{
    let state=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:0),original=state.simulation!,bucket=original.time/SimulationNews.period-1
    let cached=try #require(SimulationNews.story(bucket:bucket,state:original))
    #expect(cached.publishedAt<original.time)
    var later=original;later.newsFrom=original.time+60
    #expect(SimulationNews.story(bucket:bucket,state:later)==nil)
    let instrument=try #require(state.instruments.first{cached.instrumentIDs.contains($0.id)})
    #expect(SimulationNews.active(instrument,at:cached.publishedAt+5,state:later).isEmpty)
    #expect(SimulationNews.story(bucket:bucket,state:original)==cached)
}
@Test func tamperedNewsWorldIsRejectedBeforeReplacingTheExistingAccount()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),repository=try AccountRepository(root:root,mode:.offline)
    let account=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:0)
    _=try repository.save(account)
    var tampered=account;tampered.simulation!.newsUniverse![0].name="synthetic tampered identity"
    #expect(throws:TradeError.self){try repository.save(tampered,replacing:true)}
    let preserved=try #require(try repository.load())
    #expect(preserved.cash==account.cash);#expect(preserved.simulation!.newsWorldID==account.simulation!.newsWorldID)
    #expect(preserved.simulation!.newsUniverse==account.simulation!.newsUniverse)
}
