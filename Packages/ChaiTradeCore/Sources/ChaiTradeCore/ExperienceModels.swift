import Foundation

/// Browsing a market never changes the account, its currency balances or epoch.
public enum MarketDomain:String,Codable,CaseIterable,Sendable {
    case stocks,crypto,other
    public var label:String { switch self {case .stocks:"股票";case .crypto:"加密貨幣";case .other:"其他市場"} }
    public func contains(_ instrument:Instrument)->Bool {
        switch self {
        case .stocks:return [.taiwanStock,.usStock,.etf].contains(instrument.asset) || (instrument.asset == .index && instrument.identity?.market == .stocks)
        case .crypto:return [.crypto,.perpetual].contains(instrument.asset)
        case .other:return [.forex,.future].contains(instrument.asset) || (instrument.asset == .index && instrument.identity?.market != .stocks)
        }
    }
}
public enum MarketSort:String,Codable,CaseIterable,Sendable {
    case familiar,name,gainers,losers,volume
    public var label:String { switch self {case .familiar:"常見商品";case .name:"名稱／代碼";case .gainers:"漲幅";case .losers:"跌幅";case .volume:"成交量"} }
}
public struct InstrumentIdentity:Codable,Equatable,Sendable {
    public var exchange:String
    public var market:MarketDomain
    public var baseAsset:String
    public var unit:String
    public var boardLot:Int
    public var sector:String
    public var catalogVersion:Int=1
    public var legacy:Bool=false
    public init(exchange:String,market:MarketDomain,baseAsset:String,unit:String,boardLot:Int=1,sector:String="綜合") {
        self.exchange=exchange;self.market=market;self.baseAsset=baseAsset;self.unit=unit;self.boardLot=boardLot;self.sector=sector
    }
}
public struct MarketBrowsingState:Codable,Sendable,Equatable {
    public var search=""
    public var category="全部"
    public var sort=MarketSort.familiar
    public var favoritesOnly=false
    public var groupID:String?
    public var scrollID:String?
    public var selectedID:String?
    public var recent:[String]=[]
    public var newsFavoritesOnly=false
    public init(){}
}
public struct WatchGroup:Codable,Identifiable,Sendable,Equatable {
    public var id:String
    public var name:String
    public var market:MarketDomain
    public var instrumentIDs:[String]
    public init(id:String=UUID().uuidString,name:String,market:MarketDomain,instrumentIDs:[String]=[]) {
        self.id=id;self.name=name;self.market=market;self.instrumentIDs=instrumentIDs
    }
}
public struct ProductPreferences:Codable,Sendable {
    public var version=1
    public var activeMarket=MarketDomain.stocks
    public var markets:[String:MarketBrowsingState]=[:]
    public var groups:[WatchGroup]=[]
    public var catalogMigrated=false
    public init(){}
}
public enum TradingBoard:String,Codable,CaseIterable,Sendable {
    case regular,oddLot
    public var label:String {self == .regular ? "整股（張）":"盤中零股（股）"}
}
public struct PriceTickBand:Codable,Equatable,Sendable {
    public var below:Amount?
    public var tick:Amount
    public init(below:Amount?,tick:Amount){self.below=below;self.tick=tick}
}
public struct QuoteSummary:Codable,Equatable,Sendable {
    public var open:Amount?
    public var high:Amount?
    public var low:Amount?
    public var reference:Amount?
    public var volume:Amount?
    public var turnover:Amount?
    public var window:String
    public var marketStatus:String?
    public init(open:Amount?=nil,high:Amount?=nil,low:Amount?=nil,reference:Amount?=nil,volume:Amount?=nil,turnover:Amount?=nil,window:String,marketStatus:String?=nil){self.open=open;self.high=high;self.low=low;self.reference=reference;self.volume=volume;self.turnover=turnover;self.window=window;self.marketStatus=marketStatus}
}
public enum MarketIssueKind:String,Codable,Sendable {
    case loading,missingKey,unauthorized,unsupported,rateLimited,connectionFailed,maintenance,closed,delayed,stale,referenceOnly,halted,regionRestricted,ready
    public var label:String {
        switch self {case .loading:"行情載入中";case .missingKey:"尚未設定行情金鑰";case .unauthorized:"沒有此行情權限";case .unsupported:"來源不支援此商品";case .rateLimited:"已達來源請求限制";case .connectionFailed:"行情連線失敗";case .maintenance:"行情服務維護中";case .closed:"市場休市";case .delayed:"延遲行情";case .stale:"行情已過期";case .referenceOnly:"僅提供參考價";case .halted:"暫停交易";case .regionRestricted:"來源有地區限制";case .ready:"行情已更新"}
    }
    public var nextStep:String {
        switch self {case .loading:"正在依可見商品與來源配額安排更新。";case .missingKey:"前往行情連線，加入自己的合法行情權限。";case .unauthorized:"檢查來源方案與商品授權；既有帳務與撤單仍可使用。";case .unsupported:"更新商品目錄或選擇此來源支援的商品。";case .rateLimited:"等候來源指定時間後自動重試，可減少同時追蹤商品。";case .connectionFailed:"確認網路後重試；最後已知價格僅供查看。";case .maintenance:"來源恢復後將重新取得快照。";case .closed:"可瀏覽有效收盤資料；等待對應交易時段再送出新委託。";case .delayed:"目前資料不供即時撮合，請確認即時行情授權。";case .stale:"重新取得有效報價後才恢復成交。";case .referenceOnly:"沒有可靠可成交買賣盤；可瀏覽價格，估算模型須在交易偏好另行明確啟用。";case .halted:"商品目前暫停撮合；委託、部位與撤單保留。";case .regionRestricted:"此來源目前不提供所在環境服務；請選擇當地合法可用來源。";case .ready:"所有委託僅在本機模擬。"}
    }
}
public struct MarketDataFailure:Error,LocalizedError,Sendable {
    public let kind:MarketIssueKind
    public let retryAfter:Int64?
    public init(_ kind:MarketIssueKind,retryAfter:Int64?=nil){self.kind=kind;self.retryAfter=retryAfter}
    public var errorDescription:String? {kind.label+"。"+kind.nextStep}
}
public extension Instrument {
    var market:MarketDomain {identity?.market ?? ([.crypto,.perpetual].contains(asset) ? .crypto:[.forex,.future,.index].contains(asset) ? .other:.stocks)}
    var isTaiwanEquity:Bool {identity?.exchange == "TWSE" || identity?.exchange == "TPEx"}
    var buyLabel:String {asset.derivative ? "開多":market == .stocks ? "買進":"買入"}
    var sellLabel:String {asset.derivative ? "開空":market == .stocks ? "賣出":"賣出"}
    var quantityUnit:String {identity?.unit ?? (asset.derivative ? "口":asset == .crypto ? "幣":"股")}
}
public extension RulePack {
    func tick(at price:Amount)->Amount {priceTicks?.first(where:{$0.below == nil || price < $0.below!})?.tick ?? tick}
    func roundedPrice(_ price:Amount,_ direction:Decimal.RoundingMode)throws->Amount {
        let unit=tick(at:price);return try (price/unit).rounded(0,direction)*unit
    }
}

public extension Instrument{
    var usesTaiwanBoards:Bool{isTaiwanEquity && identity?.legacy != true && [.taiwanStock,.etf].contains(asset)}
    func board(for request:OrderRequest)->TradingBoard?{guard usesTaiwanBoards else{return nil};return request.board ?? (request.quantity.decimal < Decimal(identity?.boardLot ?? 1000) ? .oddLot:.regular)}
    func quoteKey(board:TradingBoard?)->String{board == .oddLot ? id+"::oddLot":id}
    func boardIsOpen(_ board:TradingBoard?,at time:Int64)->Bool{
        guard rules.isOpen(at:time) else{return false}
        guard usesTaiwanBoards,board == .oddLot else{return true}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:rules.timeZone) ?? .gmt
        let parts=calendar.dateComponents([.year,.month,.day,.hour,.minute],from:Date(timeIntervalSince1970:TimeInterval(time)))
        // TWSE/TPEx 2026-12-07 reform is an effective-dated rule, not applied retroactively.
        let revised=(parts.year ?? 0)>2026 || ((parts.year ?? 0)==2026 && ((parts.month ?? 0)>12 || ((parts.month ?? 0)==12 && (parts.day ?? 0)>=7)))
        return (parts.hour ?? 0)*60+(parts.minute ?? 0) >= (revised ? 540:550)
    }
}
public extension Quote{var storageKey:String{board == .oddLot ? instrumentID+"::oddLot":instrumentID}}
