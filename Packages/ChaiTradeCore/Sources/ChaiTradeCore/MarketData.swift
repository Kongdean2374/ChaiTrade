import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case coinbase, fugle, fugleFutures, alpaca, twelveData, binance
    public var label: String {
        switch self { case .coinbase: "Coinbase Exchange"; case .fugle: "Fugle 台股"; case .fugleFutures: "Fugle 期貨"; case .alpaca: "Alpaca（IEX）"; case .twelveData: "Twelve Data"; case .binance: "Binance 公開永續行情" }
    }
    public var needsKey: Bool { ![.coinbase,.binance].contains(self) }
}
public struct ProviderCredentials: Sendable {
    public var key: String
    public var secret: String
    public init(key: String = "", secret: String = "") { self.key = key; self.secret = secret }
}
public enum JSONValue: Decodable, Sendable {
    case object([String:JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String:JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .number(try c.decode(Decimal.self)) }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    public subscript(_ index: Int) -> JSONValue { let a = array; return a.indices.contains(index) ? a[index] : .null }
    public var array: [JSONValue] { if case .array(let a) = self { a } else { [] } }
    public var string: String? {
        switch self { case .string(let s): s; case .number(let n): NSDecimalNumber(decimal: n).stringValue; default: nil }
    }
    public var integer: Int64? { string.flatMap(Int64.init) }
    public func amount() throws -> Amount {
        guard let text = string else { throw TradeError.unavailable("來源缺少必要價格／數量欄位") }
        return try Amount(text)
    }
    public static func parse(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: data) }
}
public enum NetworkPolicy {
    public static func permits(_ url: URL, method: String, mode: Mode) -> Bool {
        guard mode == .online, method == "GET", url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        let path = url.path
        switch url.host {
        case "api.exchange.coinbase.com":
            return path == "/products" || path == "/time" || path.range(of: #"^/products/[A-Z0-9-]+/(ticker|book|candles|trades|stats)$"#, options: .regularExpression) != nil
        case "api.fugle.tw":
            return path.range(of: #"^/marketdata/v1\.0/(stock|futopt)/(intraday/(ticker|quote|candles|trades|volumes)|historical/candles)/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil || path.range(of:#"^/marketdata/v1\.0/(stock|futopt)/intraday/tickers$"#,options:.regularExpression) != nil
        case "www.nasdaqtrader.com":return ["/dynamic/SymDir/nasdaqlisted.txt","/dynamic/SymDir/otherlisted.txt"].contains(path)
        case "www.federalreserve.gov":return ["/feeds/press_all.xml","/feeds/press_monetary.xml"].contains(path)
        case "data.alpaca.markets":
            return path == "/v1beta1/news" || path.range(of: #"^/v2/stocks/[A-Z.]+/(snapshot|bars|quotes/latest|trades/latest)$"#, options: .regularExpression) != nil
        case "api.twelvedata.com": return ["/quote","/time_series","/exchange_rate","/forex_pairs"].contains(path)
        case "fapi.binance.com": return ["/fapi/v1/depth","/fapi/v1/premiumIndex","/fapi/v1/ticker/24hr","/fapi/v1/klines","/fapi/v1/exchangeInfo"].contains(path)
        default: return false
        }
    }
}
public protocol MarketTransport: Sendable {
    func get(_ url: URL, headers: [String:String]) async throws -> Data
}
final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct ReadOnlyTransport: MarketTransport {
    private let session: URLSession
    public init(mode: Mode) throws {
        guard mode == .online else { throw TradeError.invalid("離線模式禁止建立網路服務") }
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }
    public func get(_ url: URL, headers: [String:String]) async throws -> Data {
        guard NetworkPolicy.permits(url, method: "GET", mode: .online) else { throw TradeError.invalid("網路白名單拒絕：僅可讀取市場行情") }
        try await HTTPRequestBudget.shared.wait(host:url.host ?? "")
        var request = URLRequest(url: url); request.httpMethod = "GET"
        request.setValue("ChaiTrade/1.0 market-data-only", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError{throw CancellationError()} catch {throw MarketDataFailure(.connectionFailed)}
        guard let http = response as? HTTPURLResponse else { throw TradeError.unavailable("來源回應格式不合法") }
        switch http.statusCode {
        case 200..<300: guard data.count <= 8_000_000 else { throw TradeError.unavailable("行情回應過大") }; return data
        default:
            if ProcessInfo.processInfo.environment["CHAI_LIVE"]=="1"{print("LIVE_HTTP_FAILURE",url.host ?? "",url.path,http.statusCode)}
            let failure=HTTPMarketFailure.classify(status:http.statusCode,retryAfter:http.value(forHTTPHeaderField:"Retry-After"))
            if failure.kind == .rateLimited{await HTTPRequestBudget.shared.throttle(host:url.host ?? "",seconds:failure.retryAfter ?? 60)}
            throw failure
        }
    }
}
public struct MarketDataProvider: Sendable {
    public let id: ProviderID
    private let credentials: ProviderCredentials
    private let transport: any MarketTransport
    public init(id: ProviderID, credentials: ProviderCredentials, transport: any MarketTransport) { self.id = id; self.credentials = credentials; self.transport = transport }
    func fetch(path: String, query: [String:String] = [:], requiresCredentials: Bool = true) async throws -> JSONValue {
        if requiresCredentials && id.needsKey && credentials.key.isEmpty { throw MarketDataFailure(.missingKey) }
        let host: String
        switch id { case .coinbase: host = "api.exchange.coinbase.com"; case .fugle,.fugleFutures: host = "api.fugle.tw"; case .alpaca: host = "data.alpaca.markets"; case .twelveData: host = "api.twelvedata.com"; case .binance: host = "fapi.binance.com" }
        var components = URLComponents(); components.scheme = "https"; components.host = host; components.path = path
        var query = query, headers: [String:String] = [:]
        if id == .fugle || id == .fugleFutures { headers["X-API-KEY"] = credentials.key }
        if id == .alpaca { headers["APCA-API-KEY-ID"] = credentials.key; headers["APCA-API-SECRET-KEY"] = credentials.secret }
        if id == .twelveData { query["apikey"] = credentials.key }
        components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url, NetworkPolicy.permits(url, method: "GET", mode: .online) else { throw TradeError.invalid("來源路徑不符合行情白名單") }
        let json = try JSONValue.parse(await transport.get(url, headers: headers))
        if json["status"].string == "error" || json["error"].string != nil {throw HTTPMarketFailure.classify(status:Int(json["code"].integer ?? 403),retryAfter:nil)}
        return json
    }
    private static func timestamp(_ value: JSONValue) throws -> Int64 {
        if let integer = value.integer { return integer > 10_000_000_000 ? integer / (integer > 100_000_000_000_000 ? 1_000_000 : 1000) : integer }
        if let string = value.string {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: string) { return Int64(d.timeIntervalSince1970) }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: string) { return Int64(d.timeIntervalSince1970) }
        }
        throw TradeError.unavailable("來源缺少可驗證的行情時間，暫停成交")
    }
    public func quote(_ instrument: Instrument, now: Int64,includeSummary:Bool=false,board:TradingBoard?=nil) async throws -> Quote {
        guard instrument.provider == id else { throw TradeError.invalid("來源與商品 ID 不符，禁止合併不同市場") }
        let symbol = instrument.sourceSymbol ?? instrument.symbol
        guard symbol.range(of: #"^[A-Za-z0-9/._-]{1,32}$"#, options: .regularExpression) != nil else { throw TradeError.invalid("商品代碼不合法") }
        let requestClock=QuoteRequestClock(wall:now,uptime:ProcessInfo.processInfo.systemUptime)
        var q: Quote
        switch id {
        case .coinbase:
            let ticker = try await fetch(path: "/products/\(symbol)/ticker")
            let book = try await fetch(path: "/products/\(symbol)/book", query: ["level":"2"])
            let time = try Self.timestamp(ticker["time"])
            let bids = try book["bids"].array.prefix(50).map { try Level($0[0].amount(), $0[1].amount()) }
            let asks = try book["asks"].array.prefix(50).map { try Level($0[0].amount(), $0[1].amount()) }
            q = Quote(instrumentID: instrument.id, source: id.label, time: time, sequence: book["sequence"].integer ?? time, last: try ticker["price"].amount(), bids: bids, asks: asks, coverage: "Coinbase 單一交易所；REST 快照估算", receivedAt: now)
            if includeSummary{
                do{let stats=try await fetch(path:"/products/\(symbol)/stats");q.summary=QuoteSummary(open:try? stats["open"].amount(),high:try? stats["high"].amount(),low:try? stats["low"].amount(),reference:try? stats["open"].amount(),volume:try? stats["volume"].amount(),window:"24小時")}
                catch is CancellationError{throw CancellationError()}catch{q.summary=QuoteSummary(window:"24小時統計暫時無法讀取，可重試")}
            }
        case .fugle,.fugleFutures:
            let family = id == .fugle ? "stock" : "futopt"
            let j = try await fetch(path: "/marketdata/v1.0/\(family)/intraday/quote/\(symbol)",query:id == .fugle && board == .oddLot ? ["type":"oddlot"]:[:])
            let time = try Self.timestamp(j["lastUpdated"])
            if let reported=j["symbol"].string,reported != symbol{throw MarketDataFailure(.unsupported)}
            // Regular TWSE/TPEx lots are normalized to account shares. Odd-lot/ESB and futures stay in native units.
            let factor:Amount = id == .fugle && [.taiwanStock,.etf].contains(instrument.asset) && board != .oddLot && j["market"].string != "ESB" ? try Amount(instrument.identity?.boardLot ?? 1000):.one
            let bids = try j["bids"].array.map { try Level($0["price"].amount(), $0["size"].amount()*factor) }
            let asks = try j["asks"].array.map { try Level($0["price"].amount(), $0["size"].amount()*factor) }
            q = Quote(instrumentID: instrument.id, source: id.label, time: time, sequence: j["lastUpdated"].integer ?? time, last: try j["lastPrice"].amount(), bids: bids, asks: asks, grade: bids.isEmpty || asks.isEmpty ? .E3 : .E1, coverage: instrument.asset.derivative ? "依 Fugle 期貨授權與實際合約；數量單位為口":"依 Fugle 股票授權及交易盤；數量以股保存，整股張數已換算", receivedAt: now)
            q.board=id == .fugle ? (board ?? .regular):nil
            q.summary=QuoteSummary(open:try? j["openPrice"].amount(),high:try? j["highPrice"].amount(),low:try? j["lowPrice"].amount(),reference:(try? j["referencePrice"].amount()) ?? (try? j["previousClose"].amount()),volume:instrument.asset == .index ? nil:(try? j["total"]["tradeVolume"].amount()*factor),turnover:try? j["total"]["tradeValue"].amount(),window:"當日")
            if case .bool(true)=j["isTrial"]{q.valid=false;q.quality = .unavailable;q.sourceIssue = .auction}
            if case .bool(true)=j["isDelayedOpen"]{q.valid=false;q.sourceIssue = .auction}
            if case .bool(true)=j["isDelayedClose"]{q.valid=false;q.sourceIssue = .auction}
            if case .bool(true)=j["isClose"]{q.quality = .historical;q.sourceIssue = .closed;q.summary?.marketStatus="有效收盤參考資料，非即時可成交報價"}
            if case .bool(true)=j["tradingHalt"]["isHalted"]{q.valid=false;q.sourceIssue = .halted}
            if case .bool(true)=j["isDelayed"]{q.quality = .delayed}
        case .alpaca:
            let j = try await fetch(path: "/v2/stocks/\(symbol)/snapshot", query: ["feed":"iex"])
            let trade = j["latestTrade"], book = j["latestQuote"]
            let time = try Self.timestamp(trade["t"])
            let bids = try [Level(book["bp"].amount(), book["bs"].amount())]
            let asks = try [Level(book["ap"].amount(), book["as"].amount())]
            q = Quote(instrumentID: instrument.id, source: id.label, time: min(time, try Self.timestamp(book["t"])), sequence: time, last: try trade["p"].amount(), bids: bids, asks: asks, grade: .E2, coverage: "IEX 單一市場；不是全美綜合報價", receivedAt: now)
            q.summary=QuoteSummary(open:try? j["dailyBar"]["o"].amount(),high:try? j["dailyBar"]["h"].amount(),low:try? j["dailyBar"]["l"].amount(),reference:try? j["prevDailyBar"]["c"].amount(),volume:try? j["dailyBar"]["v"].amount(),window:"IEX當日")
        case .twelveData:
            let j = try await fetch(path: "/quote", query: ["symbol":symbol])
            let time = try Self.timestamp(j["timestamp"])
            q = Quote(instrumentID: instrument.id, source: id.label, time: time, sequence: time, last: try j["close"].amount(), bids: [], asks: [], grade: .E3, coverage: "外匯參考價；自訂模擬契約；不含可成交深度", receivedAt: now)
        case .binance:
            let mark = try await fetch(path: "/fapi/v1/premiumIndex", query: ["symbol":symbol])
            let book = try await fetch(path: "/fapi/v1/depth", query: ["symbol":symbol,"limit":"20"])
            let ticker = try await fetch(path: "/fapi/v1/ticker/24hr",query:["symbol":symbol])
            let time = try Self.timestamp(mark["time"])
            q = Quote(instrumentID: instrument.id, source: id.label, time: min(time,book["E"].integer.map{$0/1000} ?? time), sequence: book["lastUpdateId"].integer ?? time, last: try ticker["lastPrice"].amount(), bids: try book["bids"].array.map { try Level($0[0].amount(),$0[1].amount()) }, asks: try book["asks"].array.map { try Level($0[0].amount(),$0[1].amount()) }, coverage: "USDⓈ-M 線性永續；僅公開資料", receivedAt: now)
            q.mark = try mark["markPrice"].amount()
            q.fundingRate=try? mark["lastFundingRate"].amount();q.nextFundingTime=mark["nextFundingTime"].integer.map{$0/1000}
            q.summary=QuoteSummary(open:try? ticker["openPrice"].amount(),high:try? ticker["highPrice"].amount(),low:try? ticker["lowPrice"].amount(),reference:try? ticker["openPrice"].amount(),volume:try? ticker["volume"].amount(),turnover:try? ticker["quoteVolume"].amount(),window:"24小時")
        }
        guard q.last > .zero else{throw TradeError.unavailable("來源未提供有效成交價格；保留最後已知值，不用零代替未知行情")}
        if q.bids.contains(where:{$0.price <= .zero || $0.quantity < .zero}) || q.asks.contains(where:{$0.price <= .zero || $0.quantity < .zero}) || (q.bids.first != nil && q.asks.first != nil && q.bids[0].price>=q.asks[0].price){q.valid=false;q.sourceIssue = .invalidData}
        let received=try requestClock.receivedAt(uptime:ProcessInfo.processInfo.systemUptime)
        q.receivedAt=received
        if received - q.time > q.maximumAge,q.quality == .realtime { q.quality = .stale }
        if q.time > received + 5 { q.valid=false;q.sourceIssue = .invalidData }

        if q.bids.isEmpty || q.asks.isEmpty { q.grade = .E3 }
        return q
    }
    public func news(symbols:[String],now:Int64)async throws->[MarketNewsStory]{
        guard id == .alpaca else{throw MarketDataFailure(.unsupported)}
        let cleaned=Array(Set(symbols)).filter{$0.range(of:#"^[A-Z.]{1,16}$"#,options:.regularExpression) != nil}.sorted()
        let data=try await fetch(path:"/v1beta1/news",query:["symbols":cleaned.prefix(50).joined(separator:","),"limit":"50","include_content":"false","sort":"desc"])
        return try data["news"].array.compactMap{row in
            guard let title=row["headline"].string,let link=row["url"].string,let url=URL(string:link),url.scheme=="https",let identity=row["id"].string else{return nil}
            let time=try Self.timestamp(row["created_at"])
            guard time<=now else{return nil}
            let ids=row["symbols"].array.compactMap(\.string).map{"alpaca:"+$0}
            return MarketNewsStory(id:"alpaca-news-"+identity,title:title,summary:String((row["summary"].string ?? "請查看來源原文。").prefix(4000)),publishedAt:time,source:row["source"].string ?? "Alpaca 授權新聞",origin:.real,url:url,markets:[.stocks],instrumentIDs:ids,sector:nil,kind:"companyNews",endsAt:nil,logPriceImpact:nil,volumeMultiplier:nil,liquidityMultiplier:nil)
        }.sorted{$0.publishedAt>$1.publishedAt}
    }
    public func products(stockMarket:String="TSE") async throws -> [Instrument] {
        if id == .fugle,!["TSE","OTC","ESB","TIB"].contains(stockMarket){throw MarketDataFailure(.unsupported)}
        let json: JSONValue,rows: [JSONValue]
        switch id {
        case .coinbase: json=try await fetch(path:"/products");rows=json.array
        case .binance: json=try await fetch(path:"/fapi/v1/exchangeInfo");rows=json["symbols"].array.filter{$0["contractType"].string=="PERPETUAL" && $0["status"].string=="TRADING"}
        case .fugle:
            let exchange=["OTC","ESB"].contains(stockMarket) ? "TPEx":"TWSE"
            json=try await fetch(path:"/marketdata/v1.0/stock/intraday/tickers",query:["type":"EQUITY","exchange":exchange,"market":stockMarket])
            if let reported=json["exchange"].string,reported != exchange{throw MarketDataFailure(.invalidData)}
            rows=json["data"].array
        case .fugleFutures:json=try await fetch(path:"/marketdata/v1.0/futopt/intraday/tickers",query:["type":"FUTURE","exchange":"TAIFEX"]);rows=json["data"].array
        case .twelveData:json=try await fetch(path:"/forex_pairs",requiresCredentials:false);rows=json["data"].array
        case .alpaca:throw TradeError.unavailable("Alpaca 資產目錄屬於另一個 API 邊界；請從公開 Nasdaq Trader 商品搜尋挑選，行情仍只讀取 data.alpaca.markets")
        }
        var result:[Instrument]=[]
        for row in rows.prefix(2000) {
            guard let symbol=(id == .coinbase ? row["id"].string:row["symbol"].string),symbol.range(of:#"^[A-Za-z0-9/._-]{1,32}$"#,options:.regularExpression) != nil else{continue}
            var rules=RulePack(tick:try Amount("0.01"),quantityStep:try Amount("1"))
            let asset: AssetClass,currency: String,name: String
            switch id {
            case .coinbase:
                rules.tick=try row["quote_increment"].amount();rules.quantityStep=try row["base_increment"].amount()
                asset = .crypto;currency=row["quote_currency"].string ?? symbol.components(separatedBy:"-").last!;name=row["display_name"].string ?? symbol
            case .binance:
                let filters=row["filters"].array
                guard let pf=filters.first(where:{$0["filterType"].string=="PRICE_FILTER"}),let lot=filters.first(where:{$0["filterType"].string=="LOT_SIZE"}) else{continue}
                rules.tick=try pf["tickSize"].amount();rules.quantityStep=try lot["stepSize"].amount()
                if let minimum=filters.first(where:{$0["filterType"].string=="MIN_NOTIONAL"}){rules.minimumNotional=try minimum["notional"].amount()}
                asset = .perpetual;currency=row["quoteAsset"].string ?? "USDT";name=symbol
            case .fugle:asset = .taiwanStock;currency="TWD";name=row["name"].string ?? symbol;rules.timeZone="Asia/Taipei";rules.weekdaysOnly=true;rules.openMinute=540;rules.closeMinute=810
            case .fugleFutures:
                asset = .future;currency="TWD";name=row["name"].string ?? symbol
                // The source's contract identifier is preserved. Multiplier must be verified before opening positions.
                rules.maxLeverage=1
            case .twelveData:asset = .forex;currency=symbol.components(separatedBy:"/").last ?? "USD";name="\(symbol) 自訂模擬合約";rules.tick=try Amount("0.00001");rules.quantityStep=try Amount("0.001")
            case .alpaca:continue
            }
            rules.source="\(id.label) 商品目錄；精度依可用欄位，其餘為未核驗的自訂模擬規則"
            let stockExchange=["OTC","ESB"].contains(stockMarket) ? "TPEx":"TWSE"
            let identifier=id == .fugle && stockExchange != "TWSE" ? "\(id.rawValue):\(stockExchange):\(symbol)":"\(id.rawValue):\(symbol)"
            var instrument=Instrument(id:identifier,symbol:symbol,name:name,asset:asset,currency:currency,rules:rules,initialPrice:.zero,provider:id)
            instrument.identity=InstrumentIdentity(exchange:id == .coinbase ? "Coinbase Exchange":id == .fugle ? (row["exchange"].string ?? stockExchange):id == .binance ? "Binance USDⓈ-M":id == .fugleFutures ? "TAIFEX":"參考匯率",market:[.crypto,.perpetual].contains(asset) ? .crypto:[.forex,.future].contains(asset) ? .other:.stocks,baseAsset:row["base_currency"].string ?? row["baseAsset"].string ?? symbol,unit:asset == .crypto || asset == .perpetual ? (row["base_currency"].string ?? row["baseAsset"].string ?? symbol):asset == .future ? "口":"股",boardLot:id == .fugle ? 1000:1)
            if id == .coinbase {if case .bool(true)=row["trading_disabled"]{instrument.halted=true};if let status=row["status"].string,status != "online"{instrument.halted=true}}
            if id == .fugle{instrument.requiresRuleConfirmation=true;instrument.identity?.segment=stockMarket}
            if asset == .future {
                instrument.requiresRuleConfirmation=true
                // Preserve the imported source symbol/ID. Only a full source settlement date
                // disambiguates the one-digit contract year; never infer it from today's date.
                if let date=row["settlementDate"].string ?? row["endDate"].string {
                    instrument.sourceContractMonth=FugleContract.monthFromSourceDate(date,symbol:symbol)
                }
            }
            result.append(instrument)
        }
        guard !result.isEmpty else{throw TradeError.unavailable("來源未提供可用商品，請核對權限與資料格式")}
        return result
    }
    static func iso(_ time:Int64)->String{ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:TimeInterval(time)))}
    static func candleTime(_ value:JSONValue,zone:String)throws->Int64{
        if let text=value.string,text.count==10{let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(identifier:zone);f.dateFormat="yyyy-MM-dd";if let date=f.date(from:text){return Int64(date.timeIntervalSince1970)}}
        return try timestamp(value)
    }
    /// Bounded read-only paging, then upward aggregation. Never expands daily bars into minutes.
    public func history(_ instrument:Instrument,interval:Int64,count:Int=160,now:Int64,before:Int64?=nil,board:TradingBoard?=nil)async throws->[Candle]{
        guard count>0,count<=1000,interval>=60 else{throw TradeError.invalid("歷史範圍超過上限")}
        if id == .fugle || id == .fugleFutures { return try await fugleHistory(instrument,interval:interval,count:count,now:now,before:before,board:board) }
        let native:Int64
        if interval>=86400{native=86400}
        else if id == .coinbase{native=[86400,21600,3600,900,300,60].first{interval % $0==0} ?? 60}
        else if interval==14400 && (id == .fugle || id == .fugleFutures){native=3600}
        else{native=interval}
        var cursor=before,all:[Int64:Candle]=[:],result:[Candle]=[]
        for _ in 0..<20{
            let page=try await candles(instrument,interval:native,now:now,before:cursor,board:board).filter{$0.time<=(cursor ?? now)}
            guard let oldest=page.map(\.time).min() else{break}
            for c in page{all[c.time]=c}
            result=CandleCalendar.aggregate(Array(all.values),interval:interval,zone:instrument.rules.timeZone,now:now)
            if result.count>=count,oldest <= result.suffix(count).first!.time{break}
            if cursor != nil && oldest>=cursor!{break}
            if (id == .fugle || id == .fugleFutures) && native<86400{break}
            cursor=oldest-1
            // Coinbase's public limit is three requests per second; sequential reads leave headroom.
            if id == .coinbase{try await Task.sleep(for:.milliseconds(400))}
        }
        let end=before ?? now
        return Array(result.filter{$0.time<=end}.suffix(count))
    }
    public func candles(_ instrument: Instrument, interval: Int64, now: Int64,before:Int64?=nil,board:TradingBoard?=nil) async throws -> [Candle] {
        let symbol = instrument.sourceSymbol ?? instrument.symbol
        if id == .fugle,board == .oddLot,interval>=86400{throw TradeError.unavailable("來源未提供零股日K，請切回整股查看日線；不以整股資料冒充零股")}
        let j: JSONValue
        switch id {
        case .coinbase:
            guard [60,300,900,3600,21600,86400].contains(interval) else { throw TradeError.unavailable("此來源不提供該週期；請選擇 1／5／15 分、1／6 小時或日線") }
            j = try await fetch(path: "/products/\(symbol)/candles", query: ["granularity":String(interval),"start":Self.iso((before ?? now)-299*interval),"end":Self.iso(before ?? now)])
            return try j.array.map { row in Candle(time: row[0].integer ?? 0, open: try row[3].amount().displayDouble, high: try row[2].amount().displayDouble, low: try row[1].amount().displayDouble, close: try row[4].amount().displayDouble, volume: try row[5].amount().displayDouble, complete: (row[0].integer ?? 0) + interval <= now) }.sorted { $0.time < $1.time }
        case .fugle,.fugleFutures:
            if before == nil && interval < 86400 { return try await fugleCurrentCandles(instrument,interval:interval,now:now,board:board) }
            return try await fugleCandlePage(instrument,interval:interval,now:now,before:before,board:board).candles
        case .alpaca:
            let tf = interval < 3600 ? "\(interval/60)Min" : interval < 86400 ? "\(interval/3600)Hour" : "1Day"
            j = try await fetch(path: "/v2/stocks/\(symbol)/bars", query: ["timeframe":tf,"feed":"iex","limit":"1000","sort":"desc","start":Self.iso((before ?? now)-2000*interval),"end":Self.iso(before ?? now)])
            return try j["bars"].array.map { Candle(time: try Self.timestamp($0["t"]), open: try $0["o"].amount().displayDouble, high: try $0["h"].amount().displayDouble, low: try $0["l"].amount().displayDouble, close: try $0["c"].amount().displayDouble, volume: try $0["v"].amount().displayDouble) }
        case .twelveData:
            let tf = interval < 3600 ? "\(interval/60)min" : interval < 86400 ? "\(interval/3600)h" : "1day"
            j = try await fetch(path: "/time_series", query: ["symbol":symbol,"interval":tf,"outputsize":"300","timezone":"UTC","end_date":Self.iso(before ?? now).replacingOccurrences(of:"T",with:" ").replacingOccurrences(of:"Z",with:"")])
            return try j["values"].array.map { row in
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .gmt; f.dateFormat = row["datetime"].string?.count==10 ? "yyyy-MM-dd":"yyyy-MM-dd HH:mm:ss"
                guard let text = row["datetime"].string, let date = f.date(from:text) else { throw TradeError.unavailable("歷史時間格式變更") }
                return Candle(time: Int64(date.timeIntervalSince1970), open: try row["open"].amount().displayDouble, high: try row["high"].amount().displayDouble, low: try row["low"].amount().displayDouble, close: try row["close"].amount().displayDouble, volume: nil)
            }.sorted { $0.time < $1.time }
        case .binance:
            let tf = interval < 3600 ? "\(interval/60)m" : interval < 86400 ? "\(interval/3600)h" : "1d"
            j = try await fetch(path: "/fapi/v1/klines", query: ["symbol":symbol,"interval":tf,"limit":"300","endTime":String((before ?? now)*1000)])
            return try j.array.map { Candle(time: ($0[0].integer ?? 0)/1000, open: try $0[1].amount().displayDouble, high: try $0[2].amount().displayDouble, low: try $0[3].amount().displayDouble, close: try $0[4].amount().displayDouble, volume: try $0[5].amount().displayDouble) }
        }

    }
}
public enum Providers {
    public static func catalog() throws -> [Instrument] {let all=try InstrumentCatalog.builtIn(mode:.online);return all.filter{$0.asset == .crypto}+all.filter{$0.asset != .crypto}}
}
