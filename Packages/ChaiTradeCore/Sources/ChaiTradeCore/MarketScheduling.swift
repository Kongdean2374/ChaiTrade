import Foundation

public struct QuoteLease:Sendable,Equatable {
    public let id:UUID
    public let instrumentID:String
    public let context:AccountContext
}
/// Plans bounded work. The transport independently enforces a shared HTTP budget,
/// including history and catalog calls, so list updates cannot bypass quotas.
public actor VisibleQuoteScheduler {
    private var context:AccountContext?
    private var visible:Set<String>=[],protected:Set<String>=[]
    private var selected:String?
    private var due:[String:Int64]=[:],attempted:[String:Int64]=[:],failures:[String:Int]=[:]
    private var flights:[String:QuoteLease]=[:]
    private var retryFloor:[String:Int64]=[:],manualAttempts:[String:Int64]=[:]
    public init(){}
    public func demand(context:AccountContext,visible:Set<String>,selected:String?,protected:Set<String>){
        if self.context != context{self.context=context;due=[:];attempted=[:];failures=[:];flights=[:];retryFloor=[:];manualAttempts=[:]}
        self.visible=Set(visible.sorted().prefix(48));self.selected=selected;self.protected=protected
        let wanted=all
        flights=flights.filter{wanted.contains($0.key)}
        due=due.filter{wanted.contains($0.key)};attempted=attempted.filter{wanted.contains($0.key)}
    }
    private var all:Set<String>{visible.union(protected).union(selected.map{[$0]} ?? [])}
    public func next(context:AccountContext,now:Int64,limit:Int=4)->[QuoteLease]{
        guard self.context==context,limit>0 else{return []}
        retryFloor=retryFloor.filter{$0.value>now}
        let ids=all.filter{flights[$0]==nil && max(due[$0] ?? 0,retryFloor[$0] ?? 0)<=now}.sorted{a,b in
            let pa=a==selected || protected.contains(a) ? 0:1,pb=b==selected || protected.contains(b) ? 0:1
            return (pa,attempted[a] ?? 0,a)<(pb,attempted[b] ?? 0,b)
        }.prefix(min(8,limit))
        return ids.map{id in let lease=QuoteLease(id:UUID(),instrumentID:id,context:context);flights[id]=lease;attempted[id]=now;return lease}
    }
    @discardableResult public func complete(_ lease:QuoteLease,now:Int64,failure:MarketDataFailure?=nil)->Bool{
        guard context==lease.context,flights[lease.instrumentID]==lease,all.contains(lease.instrumentID) else{return false}
        flights.removeValue(forKey:lease.instrumentID)
        if let failure{
            let count=(failures[lease.instrumentID] ?? 0)+1;failures[lease.instrumentID]=count
            due[lease.instrumentID]=now+max(failure.retryAfter ?? 0,failure.kind == .missingKey || failure.kind == .unauthorized || failure.kind == .unsupported ? 3600:Int64(min(300,5*(1<<min(6,count-1)))))
            if let seconds=failure.retryAfter,seconds>0{retryFloor[lease.instrumentID]=max(retryFloor[lease.instrumentID] ?? 0,now+seconds)}
        }else{failures[lease.instrumentID]=0;retryFloor.removeValue(forKey:lease.instrumentID);due[lease.instrumentID]=now+10}
        return true
    }
    public func retry(_ ids:Set<String>){for id in ids{due[id]=0}}
    /// A foreground user refresh joins current flights and cannot reset source cooldowns.
    @discardableResult public func manualRefresh(_ ids:Set<String>,context:AccountContext,now:Int64)->Set<String>{
        guard self.context==context else{return []}
        var accepted=Set<String>()
        for id in ids.intersection(all){
            if let previous=manualAttempts[id],now-previous<5{continue}
            manualAttempts[id]=now
            guard flights[id]==nil,(retryFloor[id] ?? 0)<=now else{continue}
            due[id]=0;accepted.insert(id)
        };return accepted
    }
    public func cancel(context:AccountContext){if self.context==context{flights=[:];visible=[];selected=nil;protected=[]}}
}

public enum HTTPMarketFailure {
    public static func classify(status:Int,retryAfter:String?,now:Date=Date())->MarketDataFailure{
        switch status {
        case 401,403:return MarketDataFailure(.unauthorized)
        case 451:return MarketDataFailure(.regionRestricted)
        case 404,400,422:return MarketDataFailure(.unsupported)
        case 429:
            var seconds=retryAfter.flatMap(Int64.init)
            if seconds==nil,let retryAfter{
                let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone = .gmt;f.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date=f.date(from:retryAfter){seconds=max(1,Int64(ceil(date.timeIntervalSince(now))))}
            }
            return MarketDataFailure(.rateLimited,retryAfter:max(1,seconds ?? 60))
        case 500...599:return MarketDataFailure(.maintenance,retryAfter:30)
        default:return MarketDataFailure(.connectionFailed,retryAfter:15)
        }
    }
}
public actor HTTPRequestBudget {
    public static let shared=HTTPRequestBudget()
    private let clock=ContinuousClock()
    private var next:[String:ContinuousClock.Instant]=[:],blocked:[String:ContinuousClock.Instant]=[:]
    private var custom:[String:Double]=[:]
    public init(){}
    public func configure(host:String,requestsPerMinute:Double)throws{
        guard requestsPerMinute>=1,requestsPerMinute<=180 else{throw TradeError.invalid("行情請求預算必須為每分鐘 1 至 180 次；仍受來源方案限制")}
        custom[host]=60/requestsPerMinute
    }
    private func interval(_ host:String)->Double{
        if let value=custom[host]{return value}
        switch host {case "api.exchange.coinbase.com":return 1.0/3;case "api.twelvedata.com":return 7.5;case "api.fugle.tw":return 2;case "data.alpaca.markets":return 1;case "fapi.binance.com":return 0.5;default:return 2}
    }
    public func wait(host:String)async throws{
        while true {
            try Task.checkCancellation()
            let now=clock.now
            if let until=blocked[host],until>now{
                let duration=now.duration(to:until).components
                throw MarketDataFailure(.rateLimited,retryAfter:max(1,duration.seconds+1))
            }
            if let until=next[host],until>now{try await clock.sleep(until:until);continue}
            next[host]=now.advanced(by:.seconds(interval(host)));return
        }
    }
    public func throttle(host:String,seconds:Int64){blocked[host]=clock.now.advanced(by:.seconds(max(1,seconds)))}
}
