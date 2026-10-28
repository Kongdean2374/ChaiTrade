import Testing
@testable import ChaiTradeCore

@Test func manualRefreshCannotEraseSourceRetryAfter()async throws{
    let scheduler=VisibleQuoteScheduler(),context=AccountContext(mode:.online)
    await scheduler.demand(context:context,visible:["coinbase:BTC-USD"],selected:"coinbase:BTC-USD",protected:[])
    let lease=try #require(await scheduler.next(context:context,now:1000).first)
    #expect(await scheduler.complete(lease,now:1000,failure:MarketDataFailure(.rateLimited,retryAfter:60)))
    for _ in 0..<8{await scheduler.retry(["coinbase:BTC-USD"])}
    #expect(await scheduler.next(context:context,now:1001).isEmpty,"Manual retry erased an explicit source cooldown")
    #expect(await scheduler.next(context:context,now:1059).isEmpty)
    #expect(await scheduler.next(context:context,now:1060).count==1)
}

@Test func manualRefreshCoalescesFlightsDebouncesTapsAndKeepsAccountEpoch()async throws{
    let scheduler=VisibleQuoteScheduler(),context=AccountContext(mode:.online)
    await scheduler.demand(context:context,visible:["BTC","ETH"],selected:"BTC",protected:[])
    let first=await scheduler.next(context:context,now:1000,limit:2)
    #expect(await scheduler.manualRefresh(["BTC","ETH"],context:context,now:1001).isEmpty)
    for lease in first{#expect(await scheduler.complete(lease,now:1002))}
    for _ in 0..<8{#expect(await scheduler.manualRefresh(["BTC","ETH"],context:context,now:1003).isEmpty)}
    #expect(await scheduler.next(context:context,now:1003).isEmpty)
    #expect(await scheduler.manualRefresh(["BTC","ETH"],context:context,now:1006)==["BTC","ETH"])
    #expect(await scheduler.next(context:context,now:1006,limit:2).count==2)
    #expect(await scheduler.manualRefresh(["BTC"],context:AccountContext(mode:.online),now:1012).isEmpty)
}

@Test func sourceCooldownSurvivesLeavingAndReturningToTheSameMarket()async throws{
    let scheduler=VisibleQuoteScheduler(),context=AccountContext(mode:.online)
    await scheduler.demand(context:context,visible:["BTC"],selected:"BTC",protected:[])
    let lease=try #require(await scheduler.next(context:context,now:1000).first)
    _=await scheduler.complete(lease,now:1000,failure:MarketDataFailure(.rateLimited,retryAfter:60))
    await scheduler.cancel(context:context)
    await scheduler.demand(context:context,visible:["ETH"],selected:"ETH",protected:[])
    await scheduler.demand(context:context,visible:["BTC"],selected:"BTC",protected:[])
    await scheduler.retry(["BTC"])
    #expect(await scheduler.manualRefresh(["BTC"],context:context,now:1020).isEmpty)
    #expect(await scheduler.next(context:context,now:1059).isEmpty)
    #expect(await scheduler.next(context:context,now:1060).count==1)
}

@Test func currentAndVisibleQuotesAreScheduledBeforeBackgroundHoldings()async throws{
    let scheduler=VisibleQuoteScheduler(),context=AccountContext(mode:.online)
    let background=Set((0..<80).map{"A-held-"+String($0)})
    await scheduler.demand(context:context,visible:["VISIBLE"],selected:"CURRENT:ODD",protected:background)
    #expect(await scheduler.next(context:context,now:1000,limit:2).map(\.instrumentID)==["CURRENT:ODD","VISIBLE"],"A large portfolio starved the active market screen")
}

@Test func firstVisibleBatchFollowsScreenOrderWithoutStarvingOtherRowsOrBypassingCooldown()async throws{
    let scheduler=VisibleQuoteScheduler(),context=AccountContext(mode:.online)
    let visible:Set<String>=["AAVE","ADA","ALGO","ATOM","AVAX","BTC","ETH","SOL"]
    await scheduler.demand(context:context,visible:visible,selected:nil,protected:["HELD"],priority:["BTC","ETH","SOL","BTC","NOT-VISIBLE"])
    let first=await scheduler.next(context:context,now:1000,limit:3)
    #expect(first.map(\.instrumentID)==["BTC","ETH","SOL"])
    for lease in first{#expect(await scheduler.complete(lease,now:1000))}
    // Even when the first rows become due again, rows never attempted must win.
    let second=await scheduler.next(context:context,now:1011,limit:3)
    #expect(second.map(\.instrumentID)==["AAVE","ADA","ALGO"])
    for lease in second{#expect(await scheduler.complete(lease,now:1011))}
    let third=await scheduler.next(context:context,now:1012,limit:3)
    #expect(third.map(\.instrumentID)==["ATOM","AVAX","BTC"])
    for lease in third{#expect(await scheduler.complete(lease,now:1012,failure:lease.instrumentID=="BTC" ? MarketDataFailure(.rateLimited,retryAfter:60):nil))}
    // Changing screen order and manual refresh cannot erase a source retry floor.
    await scheduler.demand(context:context,visible:visible,selected:nil,protected:[],priority:["BTC","ETH"])
    _=await scheduler.manualRefresh(visible,context:context,now:1013)
    let retry=await scheduler.next(context:context,now:1013,limit:8)
    #expect(!retry.contains{$0.instrumentID=="BTC"})
    await scheduler.cancel(context:context)
    #expect(await scheduler.next(context:context,now:1072).isEmpty)
    await scheduler.demand(context:AccountContext(mode:.offline),visible:["SIM:BTC"],selected:nil,protected:[],priority:["BTC"])
    #expect(await scheduler.next(context:context,now:1072).isEmpty)
}
