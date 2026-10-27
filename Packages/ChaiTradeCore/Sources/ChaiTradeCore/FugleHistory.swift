import Foundation

/// Canonical account identity never changes when a source uses a short contract alias.
enum FugleContract {
    static func monthFromSourceDate(_ date: String, symbol: String) -> String? {
        guard date.count >= 10 else { return nil }
        let month = String(date.prefix(7)).replacingOccurrences(of: "-", with: "")
        guard validMonth(month), aliasMatches(symbol, month: month) else { return nil }
        return month
    }
    static func validMonth(_ value: String) -> Bool {
        value.range(of: #"^20[0-9]{2}(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
    }
    static func aliasMatches(_ alias: String, month: String) -> Bool {
        guard validMonth(month), alias.range(of: #"^[A-Z]{3}[A-L][0-9]$"#, options: .regularExpression) != nil,
              let number = Int(month.suffix(2)) else { return false }
        let code = Array("ABCDEFGHIJKL")[number - 1]
        return alias.suffix(2) == String(code) + month.prefix(4).suffix(1)
    }
    static func resolve(_ instrument: Instrument) throws -> (product: String, month: String) {
        guard instrument.asset == .future else { throw MarketDataFailure(.unsupported) }
        let source = instrument.sourceSymbol ?? instrument.symbol
        if instrument.symbol.range(of: #"^[A-Z]{2,3}20[0-9]{2}(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil {
            let canonicalRoot=String(instrument.symbol.dropLast(6)), month=String(instrument.symbol.suffix(6))
            let product=["TE":"EXF","TF":"FXF"][canonicalRoot] ?? canonicalRoot
            guard product.count==3,aliasMatches(source, month: month), String(source.prefix(3))==product else { throw MarketDataFailure(.invalidData) }
            return (product, month)
        }
        if let month = instrument.sourceContractMonth, validMonth(month), aliasMatches(source, month: month) {
            return (String(source.prefix(3)), month)
        }
        throw TradeError.unavailable("歷史期貨需要明確契約年月；請更新商品目錄。不能用近月連續合約替代既有契約，也不猜測一位數年份")
    }
}

struct FugleCandlePage: Sendable {
    var candles: [Candle]
    var nextBefore: Int64
}

public struct MarketHistoryResult: Sendable {
    public var candles: [Candle]
    public var limitation: String?
    public init(candles: [Candle], limitation: String? = nil) { self.candles=candles; self.limitation=limitation }
}
extension MarketDataProvider {
    /// Keeps real intraday bars visible when only the separately licensed history
    /// endpoint is denied. Quota/network/data errors never trigger extra fallback reads.
    public func chartHistory(_ instrument: Instrument, interval: Int64, count: Int = 160, now: Int64,
                             before: Int64? = nil, board: TradingBoard? = nil) async throws -> MarketHistoryResult {
        do { return MarketHistoryResult(candles: try await history(instrument,interval:interval,count:count,now:now,before:before,board:board)) }
        catch let failure as MarketDataFailure where (id == .fugle || id == .fugleFutures) &&
            before == nil && interval < 86400 && [.unauthorized,.unsupported].contains(failure.kind) {
            let native: Int64 = interval == 14400 ? 3600 : interval
            let raw = try await fugleCurrentCandles(instrument,interval:native,now:now,board:board)
            let bars = CandleCalendar.aggregate(raw,interval:interval,zone:instrument.rules.timeZone,now:now)
            guard !bars.isEmpty else { throw failure }
            let reason = failure.kind == .unauthorized ? "歷史行情沒有權限" : "歷史服務不支援此商品"
            return MarketHistoryResult(candles:Array(bars.suffix(count)),
                limitation:reason+"；目前只顯示來源當日日內資料。請在行情連線確認歷史資料方案；不補造更早 K 線")
        }
    }
    func fugleCurrentCandles(_ instrument: Instrument, interval: Int64, now: Int64, board: TradingBoard?) async throws -> [Candle] {
        guard [60,180,300,600,900,1800,3600].contains(interval), id != .fugleFutures || interval != 180 else { throw MarketDataFailure(.unsupported) }
        let family = id == .fugle ? "stock" : "futopt", symbol = instrument.sourceSymbol ?? instrument.symbol
        let sessions = id == .fugleFutures ? ["afterhours","regular"] : ["regular"]
        var data: [[Candle]] = []
        for session in sessions {
            try Task.checkCancellation()
            var query = ["timeframe":String(interval/60)]
            if id == .fugleFutures { query["session"]=session }
            if id == .fugle && board == .oddLot { query["type"]="oddlot" }
            if let json = try await fugleResponse(path:"/marketdata/v1.0/\(family)/intraday/candles/\(symbol)",query:query) {
                data.append(try fugleDecode(json,instrument:instrument,interval:interval,now:now,historical:false,session:session,contract:nil,board:board).filter{$0.time<=now})
            } else { data.append([]) }
        }
        return id == .fugleFutures ? try Self.fugleMergeSessions(night:data[0],regular:data[1],daily:false) : data[0]
    }
    private static func fugleCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }
    private static func fugleDate(_ time: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")!
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(time)))
    }
    /// After-hours historical queries use the following trading date; returned timestamps
    /// remain untouched. The exact before/now filter below also covers holiday gaps.
    private static func fugleNightQueryEnd(_ time: Int64, rules: RulePack) -> Int64 {
        let calendar = fugleCalendar(), date = Date(timeIntervalSince1970: TimeInterval(time))
        guard calendar.component(.hour, from: date) >= 15 else { return time }
        var next = calendar.date(byAdding: .day, value: 1, to: date)!
        for _ in 0..<14 {
            let weekday = calendar.component(.weekday, from: next)
            if weekday != 1 && weekday != 7 && !rules.holidays.contains(fugleDate(Int64(next.timeIntervalSince1970))) { break }
            next = calendar.date(byAdding: .day, value: 1, to: next)!
        }
        return Int64(next.timeIntervalSince1970)
    }
    private func fugleResponse(path: String, query: [String: String]) async throws -> JSONValue? {
        do { return try await fetch(path: path, query: query) }
        catch let failure as MarketDataFailure where failure.kind == .unsupported {
            // Fugle documents 404 for an empty historical interval. Permission, key,
            // throttling and network errors must propagate without being called empty.
            return nil
        }
    }
    private func fugleDecode(_ json: JSONValue, instrument: Instrument, interval: Int64,
                             now: Int64, historical: Bool, session: String?, contract: (product: String, month: String)?, board: TradingBoard?) throws -> [Candle] {
        let symbol = instrument.sourceSymbol ?? instrument.symbol
        guard case .array = json["data"] else { throw MarketDataFailure(.invalidData) }
        guard json["timeframe"].string == (interval >= 86400 ? "D" : String(interval / 60)) else { throw MarketDataFailure(.invalidData) }
        if historical, let contract {
            guard json["product"].string == contract.product, json["contractMonth"].string == contract.month,
                  json["session"].string?.lowercased() == session else { throw MarketDataFailure(.invalidData) }
        } else {
            guard json["symbol"].string == symbol else { throw MarketDataFailure(.invalidData) }
            if id == .fugleFutures, let reported = json["session"].string,
               reported.lowercased() != session { throw MarketDataFailure(.invalidData) }
        }
        let factor: Amount = id == .fugle && interval < 86400 && board != .oddLot &&
            [.taiwanStock, .etf].contains(instrument.asset) && json["market"].string != "ESB" ? try Amount(instrument.identity?.boardLot ?? 1000) : .one
        var result: [Candle] = []
        for row in json["data"].array {
            try Task.checkCancellation()
            if let contract, historical, row["contractMonth"].string != contract.month { throw MarketDataFailure(.invalidData) }
            let volume = try row["volume"].amount() * factor
            let keys = ["open", "high", "low", "close"]
            let missing = keys.contains { if case .null = row[$0] { return true }; return false }
            if missing {
                // Documented no-trade futures bars have null prices and zero volume.
                // They are gaps, never synthesized candles.
                guard id == .fugleFutures, volume == .zero else { throw MarketDataFailure(.invalidData) }
                continue
            }
            let open = try row["open"].amount().displayDouble, high = try row["high"].amount().displayDouble
            let low = try row["low"].amount().displayDouble, close = try row["close"].amount().displayDouble
            let time = try Self.candleTime(row["date"], zone: instrument.rules.timeZone)
            guard [open, high, low, close, volume.displayDouble].allSatisfy({ $0.isFinite }),
                  open > 0, close > 0, low > 0, high >= max(open, close), low <= min(open, close), volume >= .zero else {
                throw MarketDataFailure(.invalidData)
            }
            result.append(Candle(time: time, open: open, high: high, low: low, close: close,
                                 volume: volume.displayDouble, complete: time + interval <= now))
        }
        return result.sorted { $0.time < $1.time }
    }
    private static func fugleMergeSessions(night: [Candle], regular: [Candle], daily: Bool) throws -> [Candle] {
        var result: [Int64: Candle] = [:]
        for candle in night { result[candle.time] = candle }
        for candle in regular {
            if let previous = result[candle.time] {
                guard daily else { throw MarketDataFailure(.invalidData) }
                // Both are actual source day bars for the same trading date:
                // after-hours opens first, regular session closes last.
                result[candle.time] = Candle(time: candle.time, open: previous.open,
                    high: max(previous.high, candle.high), low: min(previous.low, candle.low), close: candle.close,
                    volume: (previous.volume ?? 0) + (candle.volume ?? 0), complete: previous.complete && candle.complete)
            } else { result[candle.time] = candle }
        }
        return result.values.sorted { $0.time < $1.time }
    }
    func fugleCandlePage(_ instrument: Instrument, interval: Int64, now: Int64,
                         before: Int64?, board: TradingBoard?) async throws -> FugleCandlePage {
        let daily = interval >= 86400
        guard daily || [60, 180, 300, 600, 900, 1800, 3600].contains(interval),
              id != .fugleFutures || interval != 180 else { throw MarketDataFailure(.unsupported) }
        let end = min(before ?? now, now)
        let calendar = Self.fugleCalendar()
        let endDay = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(end)))
        let days = daily ? 299 : max(7, min(90, Int(interval / 60) * 7))
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDay)!
        let start = Int64(startDate.timeIntervalSince1970)
        if id == .fugle, board == .oddLot {
            guard !daily, before == nil else { throw TradeError.unavailable("來源未提供零股歷史 K 線；僅能查看當日零股分鐘資料，不以整股冒充") }
            let json = try await fetch(path: "/marketdata/v1.0/stock/intraday/candles/\(instrument.sourceSymbol ?? instrument.symbol)",
                                       query: ["timeframe": String(interval / 60), "type": "oddlot"])
            let rows = try fugleDecode(json, instrument: instrument, interval: interval, now: now, historical: false, session: nil, contract: nil, board: board)
            return FugleCandlePage(candles: rows.filter { $0.time <= end }, nextBefore: Int64(endDay.timeIntervalSince1970) - 1)
        }
        let contract = id == .fugleFutures ? try FugleContract.resolve(instrument) : nil
        let symbol = instrument.sourceSymbol ?? instrument.symbol, family = id == .fugle ? "stock" : "futopt"
        let product = contract?.product ?? symbol
        let sessions = id == .fugleFutures ? ["afterhours", "regular"] : ["regular"]
        var sessionRows: [[Candle]] = []
        for session in sessions {
            try Task.checkCancellation()
            let queryEnd = id == .fugleFutures && session == "afterhours" && !daily ? Self.fugleNightQueryEnd(end, rules: instrument.rules) : end
            var query = ["timeframe": daily ? "D" : String(interval / 60), "from": Self.fugleDate(start), "to": Self.fugleDate(queryEnd), "sort": "asc"]
            if let contract { query["contractMonth"] = contract.month; query["session"] = session }
            var rows: [Int64: Candle] = [:]
            if let json = try await fugleResponse(path: "/marketdata/v1.0/\(family)/historical/candles/\(product)", query: query) {
                for candle in try fugleDecode(json, instrument: instrument, interval: interval, now: now, historical: true, session: session, contract: contract, board: board) {
                    rows[candle.time] = candle
                }
            }
            if before == nil && !daily {
                var liveQuery = ["timeframe": String(interval / 60)]
                if id == .fugleFutures { liveQuery["session"] = session }
                if let json = try await fugleResponse(path: "/marketdata/v1.0/\(family)/intraday/candles/\(symbol)", query: liveQuery) {
                    for candle in try fugleDecode(json, instrument: instrument, interval: interval, now: now, historical: false, session: session, contract: contract, board: board) {
                        // Intraday supersedes the historical snapshot at the same timestamp.
                        rows[candle.time] = candle
                    }
                }
            }
            sessionRows.append(rows.values.filter { $0.time <= end }.sorted { $0.time < $1.time })
        }
        let rows = id == .fugleFutures ? try Self.fugleMergeSessions(night: sessionRows[0], regular: sessionRows[1], daily: daily) : sessionRows[0]
        return FugleCandlePage(candles: rows, nextBefore: start - 1)
    }
    func fugleHistory(_ instrument: Instrument, interval: Int64, count: Int, now: Int64,
                      before: Int64?, board: TradingBoard?) async throws -> [Candle] {
        let native: Int64 = interval >= 86400 ? 86400 : interval == 14400 ? 3600 : interval
        let earliest = try Self.candleTime(.string(native < 86400 ? (id == .fugle ? "2023-05-23" : "2017-06-01") : "2010-01-01"), zone: "Asia/Taipei")
        var cursor = before, all: [Int64: Candle] = [:], result: [Candle] = []
        for _ in 0..<20 {
            try Task.checkCancellation()
            let page = try await fugleCandlePage(instrument, interval: native, now: now, before: cursor, board: board)
            for candle in page.candles where all[candle.time] == nil { all[candle.time] = candle }
            result = CandleCalendar.aggregate(Array(all.values), interval: interval, zone: instrument.rules.timeZone, now: now)
            if result.count >= count || page.nextBefore < earliest || (id == .fugle && board == .oddLot) { break }
            if let cursor, page.nextBefore >= cursor { throw MarketDataFailure(.invalidData) }
            cursor = page.nextBefore
        }
        guard !result.isEmpty else { throw TradeError.unavailable("此區間沒有來源 K 線；請改選交易日或確認歷史行情權限。不補造無成交的價格") }
        return Array(result.filter { $0.time <= min(before ?? now, now) }.suffix(count))
    }
}
