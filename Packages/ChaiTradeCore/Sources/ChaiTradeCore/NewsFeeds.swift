import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Only publisher-provided RSS headlines/summaries and explicit article links.
/// No page scraping, remote images, full paid articles or generation service.
public enum PublicNewsFeed {
    public static let federalReserveURL=URL(string:"https://www.federalreserve.gov/feeds/press_all.xml")!
    public static func fetch(mode:Mode,transport:any MarketTransport,now:Int64)async throws->[MarketNewsStory]{
        guard mode == .online else{throw TradeError.invalid("離線市場禁止取得外部新聞")}
        let data=try await transport.get(federalReserveURL,headers:[:])
        return try parseFederalReserve(data,now:now)
    }
    public static func parseFederalReserve(_ data:Data,now:Int64)throws->[MarketNewsStory]{
        guard data.count<=2_000_000 else{throw TradeError.unavailable("新聞摘要回應過大")}
        let delegate=RSSSummaryParser(),parser=XMLParser(data:data);parser.shouldResolveExternalEntities=false;parser.delegate=delegate
        guard parser.parse() else{throw TradeError.unavailable("官方新聞摘要格式已變更，請稍後重試")}
        return delegate.items.prefix(100).compactMap{item in
            guard let title=item["title"],!title.isEmpty,let text=item["link"],let url=URL(string:text),url.scheme=="https",["www.federalreserve.gov","federalreserve.gov"].contains(url.host ?? ""),let date=item["pubDate"].flatMap(parseDate),date<=now else{return nil}
            let summary=(item["description"] ?? "官方發布資訊；點選原文查看完整內容。").replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            return MarketNewsStory(id:"fed-"+BackupService.digest(Data(url.absoluteString.utf8)),title:String(title.prefix(1000)),summary:String(summary.prefix(4000)),publishedAt:date,source:"美國聯準會官方新聞稿",origin:.real,url:url,markets:[.stocks,.crypto,.other],instrumentIDs:[],sector:"總體經濟",kind:"macroPolicy",endsAt:nil,logPriceImpact:nil,volumeMultiplier:nil,liquidityMultiplier:nil)
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
        if item != nil,["title","link","description","pubDate"].contains(elementName){item?[elementName]=text.trimmingCharacters(in:.whitespacesAndNewlines)}
        text=""
    }
}
