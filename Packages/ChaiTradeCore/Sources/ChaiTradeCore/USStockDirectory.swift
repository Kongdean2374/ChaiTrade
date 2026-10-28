import Foundation

public struct DirectoryPage:Sendable{
    public var instruments:[Instrument]
    public var total:Int
    public var offset:Int
    public var updatedAt:String
}
/// Public identity metadata only. Quotes remain on the explicitly configured market-data source.
public struct USStockDirectory:Sendable{
    private let transport:any MarketTransport
    public init(mode:Mode,transport:any MarketTransport)throws{
        guard mode == .online else{throw TradeError.invalid("離線帳戶不讀取網路商品目錄")};self.transport=transport
    }
    public func search(_ query:String,offset:Int=0,limit:Int=40)async throws->DirectoryPage{
        guard query.utf8.count<=160,offset>=0,(1...100).contains(limit) else{throw TradeError.invalid("商品搜尋範圍不合法")}
        let nasdaq=try await transport.get(URL(string:"https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt")!,headers:[:])
        let other=try await transport.get(URL(string:"https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt")!,headers:[:])
        return try Self.parse(nasdaq:nasdaq,other:other,query:query,offset:offset,limit:limit)
    }
    public static func parse(nasdaq:Data,other:Data,query:String,offset:Int=0,limit:Int=40)throws->DirectoryPage{
        guard nasdaq.count<=4_000_000,other.count<=4_000_000,offset>=0,(1...100).contains(limit),let first=String(data:nasdaq,encoding:.utf8),let second=String(data:other,encoding:.utf8) else{throw TradeError.unavailable("官方商品目錄超過範圍或格式不正確")}
        var instruments:[Instrument]=[],updated:[String]=[],identities:Set<String>=[]
        for (text,isNasdaq) in [(first,true),(second,false)]{
            let lines=text.split(whereSeparator:{$0.isNewline}).map(String.init)
            guard lines.first?.hasPrefix(isNasdaq ? "Symbol|Security Name|":"ACT Symbol|Security Name|")==true,lines.last?.hasPrefix("File Creation Time:")==true else{throw TradeError.unavailable("官方商品目錄缺少完整標頭或更新時間，請稍後重試")}
            updated.append(lines.last!.components(separatedBy:"|")[0])
            for line in lines.dropFirst().dropLast(){
                let fields=line.components(separatedBy:"|");guard fields.count>=8 else{throw TradeError.unavailable("官方商品欄位不完整，未匯入")}
                let symbol=fields[0],name=fields[1].trimmingCharacters(in:.whitespaces),isETF=fields[isNasdaq ? 6:4]=="Y"
                guard fields[isNasdaq ? 3:6]=="N",symbol.range(of:#"^[A-Z]{1,5}(\.[A-Z])?$"#,options:.regularExpression) != nil,!name.isEmpty else{continue}
                let lower=name.lowercased()
                guard isETF || (["common stock","common share","ordinary share","depositary share","depository share"].contains{lower.contains($0)} && !["warrant","right","preferred","unit,"].contains{lower.contains($0)}) else{continue}
                let exchange:String
                if isNasdaq{exchange="NASDAQ"}else{guard let venue=["A":"NYSE AMERICAN","N":"NYSE","P":"NYSE ARCA","Z":"CBOE BZX","V":"IEX"][fields[2]] else{continue};exchange=venue}
                // A duplicate symbol across active listing venues is ambiguous and must be resolved upstream.
                guard identities.insert(symbol).inserted else{throw TradeError.unavailable("官方目錄出現跨交易所同碼商品，暫不自動合併")}
                guard query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || symbol.localizedCaseInsensitiveContains(query) || name.localizedCaseInsensitiveContains(query) else{continue}
                var rules=RulePack(tick:try Amount("0.01"),quantityStep:.one)
                rules.weekdaysOnly=true;rules.timeZone="America/New_York";rules.openMinute=570;rules.closeMinute=960;rules.settlementBusinessDays=1
                ExchangeCalendarFacts.applyUS(to:&rules)
                rules.source+="；Nasdaq Trader 官方身份；整股模擬、0.01美元報價保護步進、自訂費率；IEX行情需另行授權"
                var instrument=Instrument(id:"alpaca:"+symbol,symbol:symbol,name:name,asset:isETF ? .etf:.usStock,currency:"USD",rules:rules,initialPrice:.zero,provider:.alpaca)
                instrument.requiresRuleConfirmation=true
                instrument.identity=InstrumentIdentity(exchange:exchange,market:.stocks,baseAsset:symbol,unit:"股",boardLot:Int(fields[5]) ?? 100,sector:isETF ? "ETF":"美股")
                instrument.identity!.catalogVersion=InstrumentCatalog.version
                instruments.append(instrument)
            }
        }
        instruments.sort{a,b in let exactA=a.symbol.caseInsensitiveCompare(query) == .orderedSame,exactB=b.symbol.caseInsensitiveCompare(query) == .orderedSame;return exactA != exactB ? exactA:(a.symbol,a.id)<(b.symbol,b.id)}
        return DirectoryPage(instruments:Array(instruments.dropFirst(offset).prefix(limit)),total:instruments.count,offset:offset,updatedAt:updated.joined(separator:" · "))
    }
}
