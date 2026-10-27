import Foundation

public enum NewsOrigin:String,Codable,Sendable {case real,simulated}
public struct MarketNewsStory:Codable,Identifiable,Sendable,Equatable {
    public var id:String
    public var title:String
    public var summary:String
    public var publishedAt:Int64
    public var source:String
    public var origin:NewsOrigin
    public var url:URL?
    public var markets:[MarketDomain]
    public var instrumentIDs:[String]
    public var sector:String?
    public var kind:String
    public var endsAt:Int64?
    public var logPriceImpact:Double?
    public var volumeMultiplier:Double?
    public var liquidityMultiplier:Double?
    public var label:String {origin == .simulated ? "模擬情境，非真實新聞":source}
}
public struct NewsInstrument:Codable,Sendable,Equatable {
    public var id:String,name:String,symbol:String,sector:String
    public var asset:AssetClass
    public var market:MarketDomain
    public init(_ instrument:Instrument){id=instrument.id;name=instrument.name;symbol=instrument.symbol;sector=instrument.identity?.sector ?? instrument.asset.label;asset=instrument.asset;market=instrument.market}
}
private final class SimulationNewsCache:@unchecked Sendable {
    private let lock=NSLock()
    private var values:[String:MarketNewsStory]=[:],order:[String]=[]
    func value(_ key:String,create:()->MarketNewsStory?)->MarketNewsStory?{
        lock.lock();defer{lock.unlock()}
        if let value=values[key]{return value}
        guard let value=create() else{return nil};values[key]=value;order.append(key)
        while order.count>96{values.removeValue(forKey:order.removeFirst())};return value
    }
}
public enum SimulationNews {
    public static let period:Int64=10800
    private static let cache=SimulationNewsCache()
    public static func story(bucket:Int64,state:SimulationState)->MarketNewsStory?{
        guard let universe=state.newsUniverse,!universe.isEmpty,let enabled=state.newsFrom else{return nil}
        let key="\(state.seed)|\(state.newsWorldID ?? "legacy")|\(enabled)|\(bucket)"
        return cache.value(key){
            let r=Simulation.random(seed:state.seed,stream:713,index:bucket)
            let published=bucket*period+Int64(Int(r*20)+1)*60
            guard published>=enabled else{return nil}
            let kind=Int(Simulation.random(seed:state.seed,stream:717,index:bucket)*8)
            let stocks=universe.filter{[.taiwanStock,.usStock,.etf].contains($0.asset)}
            let crypto=universe.filter{[.crypto,.perpetual].contains($0.asset)}
            var pool=(kind==7 ? crypto:stocks);if pool.isEmpty{pool=universe}
            let target=pool[Int(Simulation.random(seed:state.seed,stream:719,index:bucket)*Double(pool.count))%pool.count]
            let positive=Simulation.random(seed:state.seed,stream:723,index:bucket)>0.5
            let amplitude=(positive ? 1.0:-1.0)*(0.008+Simulation.random(seed:state.seed,stream:727,index:bucket)*0.035)
            let duration=Int64(30+Int(Simulation.random(seed:state.seed,stream:729,index:bucket)*120))*60
            let titles=["財報預期差情境","產業需求變化","利率與政策路徑情境","模擬現金股息安排","模擬股份分割安排","市場流動性枯竭","暫時交易中斷","加密市場波動情境"]
            let names=["earnings","industry","policy","dividend","split","liquidity","halt","cryptoVolatility"]
            let affected:[NewsInstrument]=kind==2 || kind==5 ? universe:kind==1 ? universe.filter{$0.sector==target.sector}:kind==7 ? crypto:[target]
            let subject=kind==2 || kind==5 ? "跨市場":kind==1 ? target.sector:kind==7 ? "加密市場":"\(target.name)（\(target.symbol)）"
            let detail=kind==3 ? "本機情境安排每單位 0.25 報價幣模擬股息；只有作用時刻的持倉符合資格，將以相同事件 ID 記錄應收與入帳。":kind==4 ? "本機情境安排 1 拆 2，數量與每單位成本依同一事件調整，總成本不變。":kind==6 ? "本機模型暫停此標的撮合，作用期間結束後恢復；委託與歷史保留。":"模型調整價格共同／產業因子、成交量與可用對手盤；其他因子仍可能抵銷方向，並不保證獲利。"
            return MarketNewsStory(id:"sim-news-\(state.seed)-\(bucket)-\(names[kind])",title:subject+" · "+titles[kind],summary:"模擬情境，非真實新聞。此為本機生成的練習情境，與真實公司公告無關。"+detail,publishedAt:published,source:"ChaiTrade 離線情境引擎",origin:.simulated,url:nil,markets:Array(Set(affected.map(\.market))).sorted{$0.rawValue<$1.rawValue},instrumentIDs:affected.map(\.id),sector:kind==1 ? target.sector:nil,kind:names[kind],endsAt:published+duration,logPriceImpact:kind==4 ? 0:amplitude,volumeMultiplier:kind==5 ? 0.25:1.5+abs(amplitude)*15,liquidityMultiplier:kind==5 ? 0.12:kind==6 ? 0:0.7)
        }
    }
    public static func stories(state:SimulationState,from:Int64?=nil,through:Int64?=nil,limit:Int=80)->[MarketNewsStory]{
        let end=min(through ?? state.time,state.time),start=max(state.newsFrom ?? end,from ?? end-7*86400)
        guard start<=end,limit>0 else{return []}
        let last=end/period,first=max(start/period,last-Int64(min(512,limit+2)))
        return (first...last).compactMap{story(bucket:$0,state:state)}.filter{$0.publishedAt>=start && $0.publishedAt<=end}.sorted{$0.publishedAt>$1.publishedAt}.prefix(limit).map{$0}
    }
    public static func active(_ instrument:Instrument,at time:Int64,state:SimulationState)->[MarketNewsStory]{
        guard state.newsFrom != nil else{return []}
        let bucket=time/period
        return [bucket-1,bucket].compactMap{story(bucket:$0,state:state)}.filter{$0.publishedAt<=time && time<($0.endsAt ?? time) && $0.instrumentIDs.contains(instrument.id)}
    }
    public static func priceImpact(_ instrument:Instrument,at time:Int64,state:SimulationState)->Double {
        active(instrument,at:time,state:state).reduce(0){sum,event in
            let elapsed=Double(time-event.publishedAt),remaining=Double((event.endsAt ?? time)-time)
            return sum+(event.logPriceImpact ?? 0)*max(0,min(1,elapsed/600,remaining/600))
        }
    }
}


public enum MarketNewsSelection{
    public static func filter(_ stories:[MarketNewsStory],instruments:[Instrument],market:MarketDomain,category:String,watchlist:Set<String>,favoritesOnly:Bool,now:Int64,origin:NewsOrigin)->[MarketNewsStory]{
        let eligible=Set(instruments.filter{instrument in
            guard instrument.market==market else{return false}
            if market == .crypto{return category=="合約" ? instrument.asset == .perpetual:instrument.asset == .crypto}
            switch category{case "台股":return instrument.asset == .taiwanStock;case "美股":return instrument.asset == .usStock;case "ETF":return instrument.asset == .etf;case "外匯":return instrument.asset == .forex;case "期貨":return instrument.asset == .future;default:return true}
        }.map(\.id))
        return stories.filter{story in
            guard story.publishedAt<=now,story.markets.contains(market),story.origin==origin else{return false}
            if !story.instrumentIDs.isEmpty && eligible.isDisjoint(with:story.instrumentIDs){return false}
            if favoritesOnly{return !watchlist.intersection(eligible).intersection(story.instrumentIDs).isEmpty}
            return true
        }
    }
}
