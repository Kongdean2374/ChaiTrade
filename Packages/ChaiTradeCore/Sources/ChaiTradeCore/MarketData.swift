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
            return path == "/products" || path == "/time" || path.range(of: #"^/products/[A-Z0-9-]+/(ticker|book|candles|trades)$"#, options: .regularExpression) != nil
        case "api.fugle.tw":
            return path.range(of: #"^/marketdata/v1\.0/(stock|futopt)/(intraday/(quote|candles|trades|volumes)|historical/candles)/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil || path.range(of:#"^/marketdata/v1\.0/(stock|futopt)/intraday/tickers$"#,options:.regularExpression) != nil
        case "data.alpaca.markets":
            return path.range(of: #"^/v2/stocks/[A-Z.]+/(snapshot|bars|quotes/latest|trades/latest)$"#, options: .regularExpression) != nil
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
        var request = URLRequest(url: url); request.httpMethod = "GET"
        request.setValue("ChaiTrade/1.0 market-data-only", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { let failure=error as NSError;throw TradeError.unavailable("裝置離線、TLS 或行情連線失敗（\(failure.domain) \(failure.code)）；停止新成交，可重試") }
        guard let http = response as? HTTPURLResponse else { throw TradeError.unavailable("來源回應格式不合法") }
        switch http.statusCode {
        case 200..<300: guard data.count <= 8_000_000 else { throw TradeError.unavailable("行情回應過大") }; return data
        case 401: throw TradeError.unavailable("行情認證失敗：請更新此來源的 Keychain 金鑰")
        case 403: throw TradeError.unavailable("來源拒絕存取：請確認行情權限、所在地或服務條款")
        case 429: throw TradeError.unavailable("行情限速，請於 \(http.value(forHTTPHeaderField: "Retry-After") ?? "60") 秒後重試")
        case 300..<400: throw TradeError.unavailable("已拒絕來源重新導向，避免憑證流向其他主機")
        case 500..<600: throw TradeError.unavailable("行情來源維護或服務異常，稍後重試")
        default: throw TradeError.unavailable("行情請求失敗（HTTP \(http.statusCode)）；請確認商品及方案")
        }
    }
}
public struct MarketDataProvider: Sendable {
    public let id: ProviderID
    private let credentials: ProviderCredentials
    private let transport: any MarketTransport
    public init(id: ProviderID, credentials: ProviderCredentials, transport: any MarketTransport) { self.id = id; self.credentials = credentials; self.transport = transport }
    private func fetch(path: String, query: [String:String] = [:], requiresCredentials: Bool = true) async throws -> JSONValue {
        if requiresCredentials && id.needsKey && credentials.key.isEmpty { throw TradeError.unavailable("\(id.label) 尚未配置行情金鑰，請至設定加入自己的合法權限") }
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
        if json["status"].string == "error" || json["error"].string != nil { throw TradeError.unavailable("來源回報權限、商品或方案錯誤；不以假資料替代") }
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
    public func quote(_ instrument: Instrument, now: Int64) async throws -> Quote {
        guard instrument.provider == id else { throw TradeError.invalid("來源與商品 ID 不符，禁止合併不同市場") }
        let symbol = instrument.symbol
        guard symbol.range(of: #"^[A-Za-z0-9/._-]{1,32}$"#, options: .regularExpression) != nil else { throw TradeError.invalid("商品代碼不合法") }
        var q: Quote
        switch id {
        case .coinbase:
            let ticker = try await fetch(path: "/products/\(symbol)/ticker")
            let book = try await fetch(path: "/products/\(symbol)/book", query: ["level":"2"])
            let time = try Self.timestamp(ticker["time"])
            let bids = try book["bids"].array.prefix(50).map { try Level($0[0].amount(), $0[1].amount()) }
            let asks = try book["asks"].array.prefix(50).map { try Level($0[0].amount(), $0[1].amount()) }
            q = Quote(instrumentID: instrument.id, source: id.label, time: time, sequence: book["sequence"].integer ?? time, last: try ticker["price"].amount(), bids: bids, asks: asks, coverage: "Coinbase 單一交易所；REST 快照估算", receivedAt: now)
        case .fugle,.fugleFutures:
            let family = id == .fugle ? "stock" : "futopt"
            let j = try await fetch(path: "/marketdata/v1.0/\(family)/intraday/quote/\(symbol)")
            let time = try Self.timestamp(j["lastUpdated"])
            let bids = try j["bids"].array.map { try Level($0["price"].amount(), $0["size"].amount()) }
            let asks = try j["asks"].array.map { try Level($0["price"].amount(), $0["size"].amount()) }
            q = Quote(instrumentID: instrument.id, source: id.label, time: time, sequence: j["lastUpdated"].integer ?? time, last: try j["lastPrice"].amount(), bids: bids, asks: asks, grade: bids.isEmpty || asks.isEmpty ? .E3 : .E1, coverage: "依 Fugle 使用者行情授權及交易盤", receivedAt: now)
        case .alpaca:
            let j = try await fetch(path: "/v2/stocks/\(symbol)/snapshot", query: ["feed":"iex"])
            let trade = j["latestTrade"], book = j["latestQuote"]
            let time = try Self.timestamp(trade["t"])
            let bids = try [Level(book["bp"].amount(), book["bs"].amount())]
            let asks = try [Level(book["ap"].amount(), book["as"].amount())]
            q = Quote(instrumentID: instrument.id, source: id.label, time: min(time, try Self.timestamp(book["t"])), sequence: time, last: try trade["p"].amount(), bids: bids, asks: asks, grade: .E2, coverage: "IEX 單一市場；不是全美綜合報價", receivedAt: now)
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
        }
        if now - q.time > q.maximumAge { q.quality = .stale }
        if q.bids.isEmpty || q.asks.isEmpty { q.grade = .E3 }
        return q
    }
    public func products() async throws -> [Instrument] {
        let json: JSONValue,rows: [JSONValue]
        switch id {
        case .coinbase: json=try await fetch(path:"/products");rows=json.array
        case .binance: json=try await fetch(path:"/fapi/v1/exchangeInfo");rows=json["symbols"].array.filter{$0["contractType"].string=="PERPETUAL" && $0["status"].string=="TRADING"}
        case .fugle:json=try await fetch(path:"/marketdata/v1.0/stock/intraday/tickers",query:["type":"EQUITY","exchange":"TWSE","market":"TSE"]);rows=json["data"].array
        case .fugleFutures:json=try await fetch(path:"/marketdata/v1.0/futopt/intraday/tickers",query:["type":"FUTURE","exchange":"TAIFEX"]);rows=json["data"].array
        case .twelveData:json=try await fetch(path:"/forex_pairs",requiresCredentials:false);rows=json["data"].array
        case .alpaca:throw TradeError.unavailable("Alpaca 資產目錄屬於另一個 API 邊界；請以美股代碼手動加入，行情仍只讀取 data.alpaca.markets")
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
            var instrument=Instrument(id:"\(id.rawValue):\(symbol)",symbol:symbol,name:name,asset:asset,currency:currency,rules:rules,initialPrice:.zero,provider:id)
            if asset == .future{instrument.requiresRuleConfirmation=true}
            result.append(instrument)
        }
        guard !result.isEmpty else{throw TradeError.unavailable("來源未提供可用商品，請核對權限與資料格式")}
        return result
    }
    public func candles(_ instrument: Instrument, interval: Int64, now: Int64) async throws -> [Candle] {
        let symbol = instrument.symbol
        let j: JSONValue
        switch id {
        case .coinbase:
            guard [60,300,900,3600,21600,86400].contains(interval) else { throw TradeError.unavailable("此來源不提供該週期；請選擇 1／5／15 分、1／6 小時或日線") }
            j = try await fetch(path: "/products/\(symbol)/candles", query: ["granularity":String(interval)])
            return try j.array.map { row in Candle(time: row[0].integer ?? 0, open: try row[3].amount().displayDouble, high: try row[2].amount().displayDouble, low: try row[1].amount().displayDouble, close: try row[4].amount().displayDouble, volume: try row[5].amount().displayDouble, complete: (row[0].integer ?? 0) + interval <= now) }.sorted { $0.time < $1.time }
        case .fugle,.fugleFutures:
            guard [60,300,900,1800,3600].contains(interval) else { throw TradeError.unavailable("Fugle 此介面僅供日內分鐘圖") }
            let family = id == .fugle ? "stock" : "futopt"
            j = try await fetch(path: "/marketdata/v1.0/\(family)/intraday/candles/\(symbol)", query: ["timeframe":String(interval/60)])
        case .alpaca:
            let tf = interval < 3600 ? "\(interval/60)Min" : interval < 86400 ? "\(interval/3600)Hour" : "1Day"
            j = try await fetch(path: "/v2/stocks/\(symbol)/bars", query: ["timeframe":tf,"feed":"iex","limit":"1000"])
            return try j["bars"].array.map { Candle(time: try Self.timestamp($0["t"]), open: try $0["o"].amount().displayDouble, high: try $0["h"].amount().displayDouble, low: try $0["l"].amount().displayDouble, close: try $0["c"].amount().displayDouble, volume: try $0["v"].amount().displayDouble) }
        case .twelveData:
            let tf = interval < 3600 ? "\(interval/60)min" : interval < 86400 ? "\(interval/3600)h" : "1day"
            j = try await fetch(path: "/time_series", query: ["symbol":symbol,"interval":tf,"outputsize":"300","timezone":"UTC"])
            return try j["values"].array.map { row in
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .gmt; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                guard let text = row["datetime"].string, let date = f.date(from:text) else { throw TradeError.unavailable("歷史時間格式變更") }
                return Candle(time: Int64(date.timeIntervalSince1970), open: try row["open"].amount().displayDouble, high: try row["high"].amount().displayDouble, low: try row["low"].amount().displayDouble, close: try row["close"].amount().displayDouble, volume: nil)
            }.sorted { $0.time < $1.time }
        case .binance:
            let tf = interval < 3600 ? "\(interval/60)m" : interval < 86400 ? "\(interval/3600)h" : "1d"
            j = try await fetch(path: "/fapi/v1/klines", query: ["symbol":symbol,"interval":tf,"limit":"300"])
            return try j.array.map { Candle(time: ($0[0].integer ?? 0)/1000, open: try $0[1].amount().displayDouble, high: try $0[2].amount().displayDouble, low: try $0[3].amount().displayDouble, close: try $0[4].amount().displayDouble, volume: try $0[5].amount().displayDouble) }
        }
        return try j["data"].array.map { Candle(time: try Self.timestamp($0["date"]), open: try $0["open"].amount().displayDouble, high: try $0["high"].amount().displayDouble, low: try $0["low"].amount().displayDouble, close: try $0["close"].amount().displayDouble, volume: try $0["volume"].amount().displayDouble) }.sorted { $0.time < $1.time }
    }
}
public enum Providers {
    public static func catalog() throws -> [Instrument] {
        let items: [(ProviderID,String,String,AssetClass,String)] = [(.coinbase,"BTC-USD","Bitcoin",.crypto,"USD"),(.coinbase,"ETH-USD","Ethereum",.crypto,"USD"),(.fugle,"2330","台積電",.taiwanStock,"TWD"),(.fugle,"0050","元大台灣50",.etf,"TWD"),(.alpaca,"AAPL","Apple",.usStock,"USD"),(.alpaca,"SPY","SPDR S&P 500 ETF",.etf,"USD"),(.twelveData,"EUR/USD","歐元／美元自訂模擬合約",.forex,"USD"),(.binance,"BTCUSDT","BTC USDT 線性永續",.perpetual,"USDT")]
        return try items.map { provider,symbol,name,asset,currency in
            var rule = try RulePack(tick: Amount(asset == .forex ? "0.00001":"0.01"), quantityStep: Amount(asset == .crypto || asset == .forex || asset == .perpetual ? "0.001":"1"))
            rule.source = "未核驗市場規則；自訂模擬；交易前需核對合約規格"
            if asset == .usStock || provider == .alpaca { rule.timeZone = "America/New_York"; rule.weekdaysOnly = true; rule.openMinute = 570; rule.closeMinute = 960 }
            if provider == .fugle { rule.timeZone = "Asia/Taipei"; rule.weekdaysOnly = true; rule.openMinute = 540; rule.closeMinute = 810 }
            if provider == .fugleFutures { rule.multiplier = try Amount(200) }
            return Instrument(id:"\(provider.rawValue):\(symbol)",symbol:symbol,name:name,asset:asset,currency:currency,rules:rule,initialPrice:.zero,provider:provider)
        }
    }
}
