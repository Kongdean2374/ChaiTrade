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
