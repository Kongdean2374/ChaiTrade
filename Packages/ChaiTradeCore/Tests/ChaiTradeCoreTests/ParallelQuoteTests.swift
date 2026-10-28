import Foundation
import Testing
@testable import ChaiTradeCore

private actor ConcurrentCoinbaseReads:MarketTransport{
    private(set) var endpoints=Set<String>()
    func get(_ url:URL,headers:[String:String])async throws->Data{
        endpoints.insert(url.lastPathComponent)
        // A sequential adapter cannot complete this barrier. Cancellation remains
        // cooperative so the suite watchdog can report a deadlock without leaking a task.
        while endpoints.count<3{try await Task.sleep(for:.milliseconds(5))}
        let body:String=switch url.lastPathComponent{
        case "ticker":"{\"price\":\"100\",\"time\":\"1970-01-01T00:16:40Z\"}"
        case "book":"{\"sequence\":1000,\"bids\":[[\"99\",\"10\",1]],\"asks\":[[\"100\",\"10\",1]]}"
        default:"{\"open\":\"99\",\"high\":\"101\",\"low\":\"98\",\"volume\":\"1000\"}"
        }
        return Data(body.utf8)
    }
}
@Test(.timeLimit(.minutes(1))) func coinbaseIndependentReadsStartTogetherWithoutExtendingFreshness()async throws{
    let transport=ConcurrentCoinbaseReads(),provider=MarketDataProvider(id:.coinbase,credentials:ProviderCredentials(),transport:transport)
    let instrument=try #require(try Providers.catalog().first{$0.provider == .coinbase})
    let quote=try await provider.quote(instrument,now:1000,includeSummary:true)
    #expect(await transport.endpoints==["ticker","book","stats"])
    #expect(quote.grade == .E1 && quote.valid)
    // Busy CI may suspend the whole test. The adapter must still classify an aged
    // fixture as stale rather than extending freshness to make this test pass.
    #expect(quote.quality == (quote.receivedAt-quote.time>quote.maximumAge ? .stale:.realtime))
    let reference=try Amount(99)
    #expect(quote.maximumAge==30 && quote.time==1000 && quote.summary?.reference==reference)
}
