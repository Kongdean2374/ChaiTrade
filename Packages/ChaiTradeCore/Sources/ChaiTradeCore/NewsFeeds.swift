import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum PublicNewsSource:String,CaseIterable,Sendable{
    case federalReserve,twse,cryptoSlate
    public var label:String{switch self{case .federalReserve:"美國聯準會官方新聞稿";case .twse:"臺灣證券交易所新聞";case .cryptoSlate:"CryptoSlate"}}
    public var url:URL{let address:String=switch self{case .federalReserve:"https://www.federalreserve.gov/feeds/press_all.xml";case .twse:"https://www.twse.com.tw/rwd/zh/news/feed?type=rss";case .cryptoSlate:"https://cryptoslate.com/feed/"};return URL(string:address)!}
    var hosts:[String]{switch self{case .federalReserve:["www.federalreserve.gov","federalreserve.gov"];case .twse:["www.twse.com.tw"];case .cryptoSlate:["cryptoslate.com"]}}
    var markets:[MarketDomain]{switch self{case .federalReserve:[.stocks,.crypto,.other];case .twse:[.stocks];case .cryptoSlate:[.crypto]}}
}
public struct PublicNewsSourceResult:Sendable{
    public let source:PublicNewsSource
    public let stories:[MarketNewsStory]
    public let issue:String?
}
/// Only publisher-provided RSS headlines/excerpts and explicit article links for personal reading.
/// No page scraping, remote images, full paid articles or generation service.
public enum PublicNewsFeed {
    public static let federalReserveURL=URL(string:"https://www.federalreserve.gov/feeds/press_all.xml")!
    public static func fetch(mode:Mode,transport:any MarketTransport,now:Int64)async throws->[MarketNewsStory]{
        try await fetch(source:.federalReserve,mode:mode,transport:transport,now:now)
    }
    public static func fetch(source:PublicNewsSource,mode:Mode,transport:any MarketTransport,now:Int64,instruments:[Instrument]=[])async throws->[MarketNewsStory]{
        guard mode == .online else{throw TradeError.invalid("離線市場禁止取得外部新聞")}
        var data:Data
        do{data=try await transport.get(source.url,headers:[:])}
        catch let error as MarketDataFailure where [.connectionFailed,.unsupported].contains(error.kind){
            // One bounded retry for transient delivery errors. No retry storm on 429/permission.
            try await Task.sleep(for:.milliseconds(500));data=try await transport.get(source.url,headers:[:])
        }
        return try parse(data,source:source,now:now,instruments:instruments)
    }
    public static func fetchAll(mode:Mode,transport:any MarketTransport,now:Int64,instruments:[Instrument]=[])async throws->[PublicNewsSourceResult]{
        guard mode == .online else{throw TradeError.invalid("離線市場禁止取得外部新聞")}
        var results:[PublicNewsSourceResult]=[]
        for source in PublicNewsSource.allCases{
            try Task.checkCancellation()
            do{let stories=try await fetch(source:source,mode:mode,transport:transport,now:now,instruments:instruments);results.append(PublicNewsSourceResult(source:source,stories:stories,issue:stories.isEmpty ? "來源沒有可顯示且已發布的新聞。":nil))}
            catch is CancellationError{throw CancellationError()}
            catch{results.append(PublicNewsSourceResult(source:source,stories:[],issue:error.localizedDescription+" 請稍後重新整理；其他來源仍可閱讀。"))}
        }
        return results
    }
    public static func parseFederalReserve(_ data:Data,now:Int64)throws->[MarketNewsStory]{
        try parse(data,source:.federalReserve,now:now)
    }
    public static func parse(_ data:Data,source:PublicNewsSource,now:Int64,instruments:[Instrument]=[])throws->[MarketNewsStory]{
        guard data.count<=2_000_000 else{throw TradeError.unavailable("新聞摘要回應過大")}
        let prefix=String(decoding:data,as:UTF8.self).uppercased()
        guard !prefix.contains("<!DOCTYPE"),!prefix.contains("<!ENTITY") else{throw TradeError.unavailable("新聞摘要含不支援的實體宣告")}
        let delegate=RSSSummaryParser(),parser=XMLParser(data:data);parser.shouldResolveExternalEntities=false;parser.delegate=delegate
        guard parser.parse() else{throw TradeError.unavailable("官方新聞摘要格式已變更，請稍後重試")}
        return delegate.items.prefix(100).compactMap{item in
            guard let title=item["title"],!title.isEmpty,let text=item["link"],let url=URL(string:text,relativeTo:source.url)?.absoluteURL,url.scheme=="https",url.user==nil,url.password==nil,source.hosts.contains(url.host ?? ""),let date=item["pubDate"].flatMap(parseDate),date<=now else{return nil}
            let supplied=item["description"].flatMap{$0.isEmpty ? nil:$0} ?? item["content:encoded"]
            let summary=(supplied ?? "來源未附摘要；可閱讀來源原文。").replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            let ids=instruments.filter{instrument in
                guard source.markets.contains(instrument.market) else{return false}
                if source == .federalReserve{return false}
                if source == .cryptoSlate{
                    let root=instrument.symbol.split(whereSeparator:{$0=="-" || $0=="/"}).first.map(String.init) ?? instrument.symbol
                    let names=["BTC":"Bitcoin","ETH":"Ethereum","SOL":"Solana","XRP":"XRP","ADA":"Cardano","DOGE":"Dogecoin","DOT":"Polkadot","AVAX":"Avalanche","LINK":"Chainlink","LTC":"Litecoin","BCH":"Bitcoin Cash","ETC":"Ethereum Classic","UNI":"Uniswap","ATOM":"Cosmos","XLM":"Stellar","NEAR":"Near Protocol","FIL":"Filecoin","APT":"Aptos","ARB":"Arbitrum","OP":"Optimism"]
                    guard let name=names[root] else{return false}
                    return title.range(of:"(?<![A-Za-z])"+NSRegularExpression.escapedPattern(for:name)+"(?![A-Za-z])",options:[.regularExpression,.caseInsensitive]) != nil
                }
                return (instrument.name.count>=2 && title.contains(instrument.name)) || title.range(of:"(?<![0-9])"+NSRegularExpression.escapedPattern(for:instrument.symbol)+"(?![0-9])",options:.regularExpression) != nil
            }.map(\.id)
            var story=MarketNewsStory(id:(source == .federalReserve ? "fed":source.rawValue)+"-"+BackupService.digest(Data(url.absoluteString.utf8)),title:String(title.prefix(1000)),summary:String(summary.prefix(4000)),publishedAt:date,source:source.label,origin:.real,url:url,markets:source.markets,instrumentIDs:ids,sector:source == .federalReserve ? "總體經濟":source == .twse ? "台股市場":"加密市場",kind:source == .federalReserve ? "macroPolicy":"marketNews",endsAt:nil,logPriceImpact:nil,volumeMultiplier:nil,liquidityMultiplier:nil)
            if source == .twse{story.assetClasses=[.taiwanStock,.etf,.index]}
            if source == .cryptoSlate{story.assetClasses=[.crypto,.perpetual]}
            return story
        }.sorted{$0.publishedAt>$1.publishedAt}
    }
    private static func parseDate(_ string:String)->Int64?{
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone = .gmt
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz","dd MMM yyyy HH:mm:ss zzz","EEE, d MMM yyyy HH:mm:ss zzz"]{formatter.dateFormat=format;if let date=formatter.date(from:string){return Int64(date.timeIntervalSince1970)}}
        return nil
    }
}
private final class RSSSummaryParser:NSObject,XMLParserDelegate {
    var items:[[String:String]]=[]
    private var item:[String:String]?,element="",text=""
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]){
        if elementName=="item"{item=[:]}
        element=elementName;text=""
    }
    func parser(_ parser:XMLParser,foundCharacters string:String){if text.utf8.count<16000{text+=string}}
    func parser(_ parser:XMLParser,foundCDATA CDATABlock:Data){if let string=String(data:CDATABlock,encoding:.utf8),text.utf8.count<16000{text+=string}}
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?){
        if elementName=="item",let completed=item{if items.count<100{items.append(completed)};item=nil;return}
        if item != nil,["title","link","description","pubDate","content:encoded"].contains(elementName){item?[elementName]=text.trimmingCharacters(in:.whitespacesAndNewlines)}
        text=""
    }
}
