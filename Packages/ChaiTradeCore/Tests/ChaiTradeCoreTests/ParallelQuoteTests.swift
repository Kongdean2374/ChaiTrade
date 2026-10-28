import Foundation
import Testing
@testable import ChaiTradeCore

private actor ConcurrentCoinbaseReads:MarketTransport{
    private(set) var endpoints=Set<String>()
    func get(_ url:URL,headers:[String:String])async throws->Data{
        endpoints.insert(url.lastPathComponent)
        // A sequential adapter cannot complete this barrier. Cancellation remains
        // cooperative so the timeout reports a failure instead of leaking a task.
        while endpoints.count<3{try await Task.sleep(for:.milliseconds(5))}
        let body:String=switch url.lastPathComponent{
        case "ticker":"{\"price\":\"100\",\"time\":\"1970-01-01T00:16:40Z\"}"
        case "book":"{\"sequence\":1000,\"bids\":[[\"99\",\"10\",1]],\"asks\":[[\"100\",\"10\",1]]}"
        default:"{\"open\":\"99\",\"high\":\"101\",\"low\":\"98\",\"volume\":\"1000\"}"
        }
        return Data(body.utf8)
    }
}
@Test func coinbaseIndependentReadsStartTogetherWithoutExtendingFreshness()async throws{
    let transport=ConcurrentCoinbaseReads(),provider=MarketDataProvider(id:.coinbase,credentials:ProviderCredentials(),transport:transport)
    let instrument=try #require(try Providers.catalog().first{$0.provider == .coinbase})
    let quote=try await withThrowingTaskGroup(of:Quote.self){group in
        group.addTask{try await provider.quote(instrument,now:1000,includeSummary:true)}
        group.addTask{try await Task.sleep(for:.seconds(2));throw TradeError.unavailable("Independent quote requests were serialized")}
        defer{group.cancelAll()};return try #require(try await group.next())
    }
    #expect(await transport.endpoints==["ticker","book","stats"])
    #expect(quote.grade == .E1 && quote.quality == .realtime && quote.valid)
    let reference=try Amount(99)
    #expect(quote.maximumAge==30 && quote.time==1000 && quote.summary?.reference==reference)
}
