import Foundation
import Testing
@testable import ChaiTradeCore

private func fugleTime(_ text: String) -> Int64 {
    Int64(ISO8601DateFormatter().date(from: text)!.timeIntervalSince1970)
}
private actor FugleHistoryTransport: MarketTransport {
    enum Scenario: Sendable { case stocks, emptyFirstPage, futures, wrongContract, missingPrice, limited }
    let scenario: Scenario
    private var requests: [URL] = []
    init(_ scenario: Scenario) { self.scenario = scenario }
    func urls() -> [URL] { requests }
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        requests.append(url)
        if scenario == .limited { throw MarketDataFailure(.rateLimited, retryAfter: 17) }
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let historical = url.path.contains("/historical/"), future = url.path.contains("/futopt/")
        let frame = query["timeframe"] ?? "1", daily = frame == "D", session = query["session"] ?? "regular"
        var result: [String: Any] = ["symbol": future ? "TXFK6" : "2330", "market": "TSE", "timeframe": frame]
        if future && historical {
            result["product"] = "TXF"; result["contractMonth"] = scenario == .wrongContract ? "202612" : "202611"
            result["session"] = session.uppercased()
        }
        func row(_ date: String, _ close: Int, volume: Int = 7) -> [String: Any] {
            ["date": date, "open": close, "high": close + 1, "low": close - 1, "close": close, "volume": volume, "contractMonth": "202611"]
        }
        var data: [[String: Any]]
        if scenario == .emptyFirstPage {
            data = requests.count == 1 ? [] : [row((query["from"] ?? "2026-10-12") + "T09:00:00+08:00", 99)]
        } else if future && daily {
            data = [["date": "2026-10-26", "open": session == "afterhours" ? 90 : 96,
                     "high": session == "afterhours" ? 100 : 110, "low": session == "afterhours" ? 80 : 94,
                     "close": session == "afterhours" ? 95 : 105, "volume": session == "afterhours" ? 2 : 3,
                     "contractMonth": "202611"]]
            if session == "afterhours" {
                data.append(["date": "2026-10-25", "open": NSNull(), "high": NSNull(), "low": NSNull(), "close": NSNull(), "volume": 0, "contractMonth": "202611"])
            }
        } else if future {
            result["session"] = session.uppercased()
            data = [row(session == "afterhours" ? "2026-10-26T16:00:00+08:00" : "2026-10-27T09:00:00+08:00", historical ? 100 : 101)]
        } else if daily {
            data = [row("2026-10-26", 99)]
        } else if historical {
            data = [row("2026-10-26T13:30:00+08:00", 99), row("2026-10-27T09:30:00+08:00", 100),
                    row("2026-10-27T09:32:00+08:00", 200)]
        } else {
            data = [row("2026-10-27T09:30:00+08:00", 101), row("2026-10-27T09:31:00+08:00", 102)]
        }
        if scenario == .missingPrice, !data.isEmpty { data[0]["open"] = NSNull() }
        result["data"] = data
        return try JSONSerialization.data(withJSONObject: result)
    }
}
private func fugleProvider(_ transport: FugleHistoryTransport, future: Bool = false) -> MarketDataProvider {
    MarketDataProvider(id: future ? .fugleFutures : .fugle, credentials: ProviderCredentials(key: "synthetic-fixture-not-a-key"), transport: transport)
}

@Test func fugleHistoricalMinutesMergeCurrentBarsWithoutFutureLeakAndKeepTaipeiDates() async throws {
    let stock = try #require(InstrumentCatalog.builtIn(mode: .online).first { $0.symbol == "2330" })
    let transport = FugleHistoryTransport(.stocks), now = fugleTime("2026-10-27T09:31:30+08:00")
    let bars = try await fugleProvider(transport).history(stock, interval: 60, count: 3, now: now)
    #expect(bars.count == 3)
    #expect(bars.map(\.close) == [99, 101, 102])
    #expect(bars.allSatisfy { $0.volume == 7000 && $0.time <= now })
    #expect(bars.last?.complete == false)
    let requests = await transport.urls()
    #expect(requests.count == 2)
    #expect(requests[0].path == "/marketdata/v1.0/stock/historical/candles/2330")
    #expect(requests[1].path.contains("/intraday/"))
    let before = fugleTime("2026-10-27T00:30:00+08:00"), second = FugleHistoryTransport(.stocks)
    let older = try await fugleProvider(second).history(stock, interval: 60, count: 1, now: now, before: before)
    #expect(older.map(\.close) == [99])
    let olderRequests = await second.urls()
    #expect(olderRequests.count == 1)
    #expect(URLComponents(url: olderRequests[0], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "to" }?.value == "2026-10-27")
}
@Test func fugleEmptyHistoricalWindowContinuesWithBoundedDates() async throws {
    let stock = try #require(InstrumentCatalog.builtIn(mode: .online).first { $0.symbol == "2330" })
    let transport = FugleHistoryTransport(.emptyFirstPage)
    let bars = try await fugleProvider(transport).history(stock, interval: 60, count: 1, now: fugleTime("2026-10-27T12:00:00+08:00"), before: fugleTime("2026-10-27T11:00:00+08:00"))
    #expect(bars.count == 1)
    let urls = await transport.urls()
    #expect(urls.count == 2)
    let to = urls.map { URLComponents(url: $0, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "to" }!.value! }
    #expect(to == ["2026-10-27", "2026-10-19"])
}
@Test func fugleFuturesUseExactMonthProductBothSessionsAndActualDailyAggregation() async throws {
    let future = try #require(InstrumentCatalog.builtIn(mode: .online).first { $0.symbol == "TXF202611" })
    let transport = FugleHistoryTransport(.futures)
    let bars = try await fugleProvider(transport, future: true).history(future, interval: 86400, count: 1, now: fugleTime("2026-10-27T12:00:00+08:00"))
    let bar = try #require(bars.first)
    #expect(bar.open == 90 && bar.high == 110 && bar.low == 80 && bar.close == 105 && bar.volume == 5)
    let requests = await transport.urls()
    #expect(requests.count == 2)
    for request in requests {
        #expect(request.path == "/marketdata/v1.0/futopt/historical/candles/TXF")
        let query = URLComponents(url: request, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.first { $0.name == "contractMonth" }?.value == "202611")
        #expect(query.first { $0.name == "timeframe" }?.value == "D")
    }
    let minuteTransport = FugleHistoryTransport(.futures)
    let minutes = try await fugleProvider(minuteTransport, future: true).history(future, interval: 60, count: 2, now: fugleTime("2026-10-27T09:31:30+08:00"))
    #expect(minutes.count == 2 && minutes.allSatisfy { $0.close == 101 && $0.volume == 7 })
}
@Test func fugleWrongContractMissingPricesAndRateLimitCannotLookLikeValidHistory() async throws {
    let future = try #require(InstrumentCatalog.builtIn(mode: .online).first { $0.symbol == "TXF202611" })
    do {
        _ = try await fugleProvider(FugleHistoryTransport(.wrongContract), future: true).candles(future, interval: 86400, now: fugleTime("2026-10-27T12:00:00+08:00"))
        Issue.record("wrong contract must be rejected")
    } catch let failure as MarketDataFailure { #expect(failure.kind == .invalidData) }
    let stock = try #require(InstrumentCatalog.builtIn(mode: .online).first { $0.symbol == "2330" })
    do {
        _ = try await fugleProvider(FugleHistoryTransport(.missingPrice)).candles(stock, interval: 60, now: fugleTime("2026-10-27T12:00:00+08:00"))
        Issue.record("missing price with real volume must be rejected")
    } catch let failure as MarketDataFailure { #expect(failure.kind == .invalidData) }
    let limited = FugleHistoryTransport(.limited)
    do {
        _ = try await fugleProvider(limited).history(stock, interval: 60, count: 1, now: fugleTime("2026-10-27T12:00:00+08:00"))
        Issue.record("429 must propagate")
    } catch let failure as MarketDataFailure { #expect(failure.kind == .rateLimited && failure.retryAfter == 17) }
    #expect(await limited.urls().count == 1)
}
@Test func fugleShortYearAliasesRequireFullSourceIdentityAndNeverRollOwnedContract() throws {
    #expect(FugleContract.monthFromSourceDate("2026-11-18", symbol: "TXFK6") == "202611")
    #expect(FugleContract.monthFromSourceDate("2036-11-18", symbol: "TXFK6") == "203611")
    #expect(FugleContract.monthFromSourceDate("2026-12-16", symbol: "TXFK6") == nil)
    #expect(FugleContract.monthFromSourceDate("2026-11-18", symbol: "MX1K6") == nil)
    var future = try #require(InstrumentCatalog.builtIn(mode: .online).first { $0.symbol == "TXF202611" })
    let oldID = future.id
    #expect(try FugleContract.resolve(future).month == "202611")
    future.sourceSymbol = "TXFL6"
    #expect(throws: (any Error).self) { try FugleContract.resolve(future) }
    #expect(future.id == oldID && future.symbol == "TXF202611")
    future.symbol = "TXFK6"; future.sourceSymbol = nil
    #expect(throws: (any Error).self) { try FugleContract.resolve(future) }
    future.sourceContractMonth = "202611"
    #expect(try FugleContract.resolve(future).product == "TXF")
    #expect(try FugleContract.resolve(future).month == "202611")
}
