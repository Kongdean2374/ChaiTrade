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
