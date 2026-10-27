import Foundation

public enum TaiwanSecurityClassification: String, Codable, Sendable {
    case stock, etf, bondETF, index, other, unknown
    public var assetClass: AssetClass? {
        switch self { case .stock: .taiwanStock; case .etf,.bondETF: .etf; case .index: .index; case .other,.unknown: nil }
    }
    static func sourceCode(_ code: String, type: String) -> Self {
        if type == "INDEX" { return .index }
        switch code {
        case "01","04","05","07","19": return .stock
        case "24","25","26","27","28","29","30","31","45","46": return .etf
        case "32","33","47": return .bondETF
        case "00": return .unknown
        default: return .other
        }
    }
}
/// Identity metadata does not grant real-time quotes, execution or verified fee rules.
public struct FugleSecurityMetadata: Codable, Equatable, Sendable {
    public let symbol: String
    public let name: String
    public let exchange: String
    public let market: String
    public let securityType: String
    public let classification: TaiwanSecurityClassification
    public let currency: String
    public let boardLot: Int
    public let sourceDate: String
    public let checkedAt: Int64
    public let securityStatus: String?
    public let matchingInterval: Int?
    public let isDisposition: Bool?
    public let canDayTrade: Bool?
    public let referencePrice: Amount?
    public let limitUpPrice: Amount?
    public let limitDownPrice: Amount?
    public var isSuspended: Bool { securityStatus == "SUSPENDED" || securityStatus == "TERMINATED" }
    public var restriction: String? {
        if isSuspended { return "來源標示暫停或終止交易；僅供查看" }
        if market == "ESB" { return "興櫃為議價市場，目前僅供行情與基本資料瀏覽" }
        if classification.assetClass == nil { return "此證券類型尚不支援本機交易；不當成普通股票或 ETF" }
        if isDisposition == true || (matchingInterval ?? 0) > 0 { return "來源標示處置或分盤撮合，須核對相應市場規則" }
        return nil
    }
    /// Only resolves a new catalog candidate. The engine separately decides whether
    /// an existing account identity may change; this never rewrites held instruments.
    public func resolvedCandidate(_ source: Instrument) throws -> Instrument {
        guard source.provider == .fugle,(source.sourceSymbol ?? source.symbol) == symbol,
              let asset = classification.assetClass else { throw MarketDataFailure(.unsupported) }
        if let existing=source.identity?.exchange,["TWSE","TPEx"].contains(existing),existing != exchange { throw MarketDataFailure(.invalidData) }
        var result=source
        result.name=name;result.asset=asset;result.currency=currency;result.halted=restriction != nil
        result.identity=InstrumentIdentity(exchange:exchange,market:.stocks,baseAsset:symbol,unit:asset == .index ? "點":"股",boardLot:boardLot,sector:source.identity?.sector ?? "綜合")
        result.identity?.segment=market
        // Metadata contains no tick schedule, broker fee or tax authority. It must
        // not silently certify the temporary catalog's trading rules.
        result.requiresRuleConfirmation=asset != .index
        result.rules.source="Fugle 基本資料已核對身份、幣別及交易單位；交易級距、費稅與特殊規則仍需確認"
        return result
    }
}

extension MarketDataProvider {
    public func securityMetadata(_ instrument: Instrument, now: Int64) async throws -> FugleSecurityMetadata {
        guard id == .fugle,instrument.provider == .fugle,now>=0,now<=32_503_680_000 else { throw MarketDataFailure(.unsupported) }
        let symbol=instrument.sourceSymbol ?? instrument.symbol
        guard symbol.range(of:#"^[A-Za-z0-9._-]{1,32}$"#,options:.regularExpression) != nil else { throw MarketDataFailure(.invalidData) }
        let json=try await fetch(path:"/marketdata/v1.0/stock/intraday/ticker/\(symbol)")
        guard json["symbol"].string == symbol,
              let name=json["name"].string,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count<=1024,
              let exchange=json["exchange"].string,["TWSE","TPEx"].contains(exchange),
              let market=json["market"].string,["TSE","OTC","ESB","TIB"].contains(market),
              exchange == (["TSE","TIB"].contains(market) ? "TWSE":"TPEx"),
              let currency=json["tradingCurrency"].string,currency.range(of:#"^[A-Z]{3,8}$"#,options:.regularExpression) != nil,
              let lot=json["boardLot"].integer,lot>0,lot<=1_000_000,
              let date=json["date"].string,date.count==10 else { throw MarketDataFailure(.invalidData) }
        if let expected=instrument.identity?.exchange,["TWSE","TPEx"].contains(expected),expected != exchange { throw MarketDataFailure(.invalidData) }
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(identifier:"Asia/Taipei")!;formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
        guard let parsed=formatter.date(from:date),formatter.string(from:parsed)==date,
              Int64(parsed.timeIntervalSince1970)<=now+5 else { throw MarketDataFailure(.invalidData) }
        let type=json["type"].string ?? ""
        guard type == "EQUITY" || type == "INDEX" else { throw MarketDataFailure(.unsupported) }
        let securityType=json["securityType"].string ?? (type == "INDEX" ? "INDEX":"")
        guard type == "INDEX" || securityType.range(of:#"^[0-9]{2}$"#,options:.regularExpression) != nil else { throw MarketDataFailure(.invalidData) }
        let status=json["securityStatus"].string
        guard status == nil || ["NORMAL","TERMINATED","SUSPENDED"].contains(status!) else { throw MarketDataFailure(.invalidData) }
        let interval=json["matchingInterval"].integer
        guard interval == nil || (0...86400).contains(interval!) else { throw MarketDataFailure(.invalidData) }
        func boolean(_ key:String)throws->Bool?{
            switch json[key] { case .bool(let value): return value; case .null: return nil; default: throw MarketDataFailure(.invalidData) }
        }
        func positive(_ key:String)throws->Amount?{
            if case .null=json[key]{return nil}
            let value=try json[key].amount();guard value > .zero else{throw MarketDataFailure(.invalidData)};return value
        }
        let reference=try positive("referencePrice"),up=try positive("limitUpPrice"),down=try positive("limitDownPrice")
        if let up,let down,up<down {throw MarketDataFailure(.invalidData)}
        return FugleSecurityMetadata(symbol:symbol,name:name,exchange:exchange,market:market,securityType:securityType,
            classification:TaiwanSecurityClassification.sourceCode(securityType,type:type),currency:currency,boardLot:Int(lot),
            sourceDate:date,checkedAt:now,securityStatus:status,matchingInterval:interval.map(Int.init),
            isDisposition:try boolean("isDisposition"),canDayTrade:try boolean("canDayTrade"),
            referencePrice:reference,limitUpPrice:up,limitDownPrice:down)
    }
}
