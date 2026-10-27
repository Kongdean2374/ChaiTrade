import Foundation

private final class SimulationCandleCache: @unchecked Sendable {
    private let lock=NSLock()
    private var values:[String:Candle]=[:],order:[String]=[]
    func get(_ key:String)->Candle?{lock.lock();defer{lock.unlock()};guard let value=values[key] else{return nil};order.removeAll{$0==key};order.append(key);return value}
    func put(_ key:String,_ value:Candle){lock.lock();defer{lock.unlock()};order.removeAll{$0==key};order.append(key);values[key]=value;while order.count>512{values.removeValue(forKey:order.removeFirst())}}
    func clear(){lock.lock();defer{lock.unlock()};values.removeAll();order.removeAll()}
}

public struct SimulationState: Codable, Sendable {
    public var seed: UInt64 = 2374
    public var algorithm = "factor-wave-1"
    public var time: Int64 = 1_793_064_600 // 2026-10-27 09:30 Asia/Taipei, a usable default local session
    public var paused = false
    public var speed = 1
    public var scenario = "盤整"
    public var volatility = 1.0
    public var liquidity = 1.0
    public var changes: [SimulationChange] = []
    public var priceAdjustments: [PriceAdjustment]?
    public var newsFrom:Int64?
    public var newsAccountingFrom:Int64?
    public var newsWorldID:String?
    public var newsUniverse:[NewsInstrument]?
    public init() {}
}
public struct SimulationChange: Codable, Sendable {
    public var time: Int64
    public var scenario: String
    public var volatility: Double
    public var liquidity: Double
}
public enum Simulation {
    public static let step: Int64 = 5
    private static let candleCache=SimulationCandleCache()
    public static func clearChartCache(){candleCache.clear()}
    /// Stable FNV-1a identifier mapping and SplitMix64 mixing. No Swift Hasher / mutable UI RNG.
    public static func hash(_ string: String) -> UInt64 {
        string.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
    public static func random(seed: UInt64, stream: UInt64, index: Int64) -> Double {
        var z = seed &+ stream &+ UInt64(bitPattern: index) &* 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992.0
    }
    private static func wave(seed: UInt64, stream: UInt64, time: Int64, scale: Int64) -> Double {
        let bucket = Int64(floor(Double(time) / Double(scale)))
        let fraction = Double(time - bucket * scale) / Double(scale)
        let a = random(seed: seed, stream: stream, index: bucket) * 2 - 1
        let b = random(seed: seed, stream: stream, index: bucket + 1) * 2 - 1
        return a + (b - a) * fraction
    }
    private static func priceValue(_ instrument: Instrument, at time: Int64, state: SimulationState) throws -> Double {
        guard ["factor-wave-1","factor-wave-2"].contains(state.algorithm) else { throw TradeError.unavailable("模擬演算法版本不相容，保留檢查點") }
        let stream = hash(instrument.id), category = hash(instrument.asset.rawValue)
        let regime = Int(random(seed: state.seed, stream: 11, index: time / 86400) * 5)
        let amplitudes = [1.0, 1.2, 0.5, 2.8, 1.6]
        let common = wave(seed: state.seed, stream: 7, time: time, scale: 86400) * 0.07
        let sector = wave(seed: state.seed, stream: category, time: time, scale: 21600) * 0.035
        let slow = wave(seed: state.seed, stream: stream, time: time, scale: 3600) * 0.018
        let fast = wave(seed: state.seed, stream: stream &+ 1, time: time, scale: 60) * instrument.volatility
        // Control changes are an immutable timeline; historical reads use the controls effective then.
        let control = state.changes.last(where: { $0.time <= time })
        let vol = control?.volatility ?? 1
        let scenario = control?.scenario ?? "盤整"
        let elapsed = Double(time - (control?.time ?? time))
        let trend = scenario == "多頭" ? min(0.15, elapsed / 86400 * 0.03) : scenario == "空頭" ? max(-0.15, -elapsed / 86400 * 0.03) : scenario == "恐慌" ? -0.12 * min(1, elapsed / 3600) : 0
        let adjustment = (state.priceAdjustments ?? []).filter { $0.instrumentID == instrument.id && $0.time <= time }.reduce(1.0) { $0 * $1.factor.displayDouble }
        let news=SimulationNews.priceImpact(instrument,at:time,state:state)
        let raw = instrument.initialPrice.displayDouble * adjustment * exp(common + sector + slow + fast * amplitudes[regime] * vol + trend + news)
        let tick = instrument.rules.priceTicks?.first(where:{$0.below == nil || raw < $0.below!.displayDouble})?.tick.displayDouble ?? instrument.rules.tick.displayDouble
        guard raw.isFinite, tick > 0 else { throw TradeError.invalid("模擬價格超出範圍") }
        return max(tick, (raw / tick).rounded() * tick)
    }
    public static func price(_ instrument: Instrument, at time: Int64, state: SimulationState) throws -> Amount {
        try Amount(String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),priceValue(instrument,at:time,state:state)))
    }
    public static func quote(_ instrument: Instrument, state: SimulationState) throws -> Quote {
        let time = state.time, price = try price(instrument, at: time, state: state)
        let active=SimulationNews.active(instrument,at:time,state:state)
        let tick=instrument.rules.tick(at:price)
        let shortage=active.map{$0.liquidityMultiplier ?? 1}.min() ?? 1
        let spreadSteps = max(1, Int((price.displayDouble * 0.00015 / max(0.1,shortage)) / tick.displayDouble))
        let spread = try tick * Amount(spreadSteps)
        let liquidity = state.changes.last(where: { $0.time <= time })?.liquidity ?? 1
        let count = max(1, Int(Double(instrument.liquidity) * liquidity * shortage))
        var bids: [Level] = [], asks: [Level] = []
        for level in 1...8 {
            let delta = try spread * Amount(level)
            let size = try instrument.rules.quantityStep * Amount(max(1, count / level))
            bids.append(Level(try instrument.rules.roundedPrice(max(tick,try price-delta),.down),size))
            asks.append(Level(try instrument.rules.roundedPrice(price+delta,.up),size))
        }
        var q = Quote(instrumentID: instrument.id, source: "B 決定性離線市場", time: time, sequence: time / step, last: price, bids: bids, asks: asks)
        if instrument.asset.derivative { q.mark = price }
        q.causalEventIDs=active.map(\.id)
        if active.contains(where:{$0.kind=="halt"}){q.valid=false;q.coverage="模擬暫停交易情境，委託保留"}
        let referenceTime=time-86400
        let reference=try self.price(instrument,at:referenceTime,state:state)
        q.summary=QuoteSummary(reference:reference,window:instrument.asset == .crypto || instrument.asset == .perpetual ? "模擬24小時":"模擬前一日",marketStatus:instrument.rules.isOpen(at:time) ? "模擬交易中":"模擬休市")
        return q
    }
    public static func stepVolume(_ instrument:Instrument,at time:Int64,state:SimulationState)->Double{
        guard state.algorithm == "factor-wave-2" || state.newsFrom != nil else{return Double(instrument.liquidity)}
        let active=SimulationNews.active(instrument,at:time,state:state)
        if active.contains(where:{$0.kind=="halt"}){return 0}
        let control=state.changes.last(where:{$0.time<=time})?.liquidity ?? 1
        let factor=active.map{$0.volumeMultiplier ?? 1}.max() ?? 1
        return Double(max(1,instrument.liquidity/20))*instrument.rules.quantityStep.displayDouble*control*factor
    }
    public static func summary(_ instrument:Instrument,state:SimulationState)throws->QuoteSummary{
        let end=state.time,continuous=[AssetClass.crypto,.perpetual,.forex].contains(instrument.asset)
        let day=CandleCalendar.start(end,interval:86400,zone:instrument.rules.timeZone)
        let previous=continuous ? end-86400:(try previousTradingTime(before:day,rules:instrument.rules) ?? end-86400)
        let from=continuous ? end-86400:day
        var boundaries:Set<Int64>=[from,end+step]
        for change in state.changes where change.time>from && change.time<=end{boundaries.insert(change.time)}
        let first=from/SimulationNews.period-1,last=end/SimulationNews.period
        if state.newsFrom != nil{for bucket in first...last{if let story=SimulationNews.story(bucket:bucket,state:state),story.instrumentIDs.contains(instrument.id){for time in [story.publishedAt,story.endsAt ?? end+step] where time>from && time<=end{boundaries.insert(time)}}}}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:instrument.rules.timeZone)!
        var date=calendar.startOfDay(for:Date(timeIntervalSince1970:TimeInterval(from)))
        while Int64(date.timeIntervalSince1970)<=end{
            for minute in [0,instrument.rules.openMinute,instrument.rules.closeMinute] where minute<1440{
                if let boundary=calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:date){let value=Int64(boundary.timeIntervalSince1970);if value>from && value<=end{boundaries.insert(value)}}
            }
            date=calendar.date(byAdding:.day,value:1,to:date)!
        }
        let sorted=boundaries.sorted();var volume=0.0
        for (left,right) in zip(sorted,sorted.dropFirst()) where instrument.rules.isOpen(at:left){volume+=Double(max(0,(right-left)/step))*stepVolume(instrument,at:left,state:state)}
        return QuoteSummary(reference:try price(instrument,at:previous,state:state),volume:try Amount(String(format:"%.10f",locale:Locale(identifier:"en_US_POSIX"),volume)),window:continuous ? "模擬24小時":"模擬當日",marketStatus:instrument.rules.isOpen(at:end) ? "模擬交易中":"模擬休市")
    }
    public static func candles(_ instrument: Instrument, state: SimulationState, interval: Int64, count: Int, before: Int64? = nil) throws -> [Candle] {
        guard interval >= 60, count > 0, count <= 2000 else { throw TradeError.invalid("圖表區間不合法") }
        let end = min(before ?? state.time, state.time)
        let zone=instrument.rules.timeZone
        let lastStart=CandleCalendar.start(end,interval:interval,zone:zone)
        var identity=state;identity.time=0;identity.paused=false;identity.speed=1
        var config=try AccountRepository.encode(identity);config.append(try AccountRepository.encode(instrument))
        let prefix=BackupService.digest(config)+"|\(interval)|"
        var result: [Candle] = []
        var start=lastStart
        while result.count<count && start>=state.time-10*366*86400{
            try Task.checkCancellation()
            let next=CandleCalendar.next(start,interval:interval,zone:zone)
            let key=prefix+String(start)
            if next<=end,let cached=candleCache.get(key){result.append(cached);start=CandleCalendar.next(start,interval:interval,zone:zone,offset:-1);continue}
            var first:Double?,last:Double?,high = -Double.infinity,low=Double.infinity,volume=0.0
            // Log-price is affine within each minute/control segment. Quantization is monotone.
            // Exact five-second extrema therefore occur at segment endpoints, not at arbitrary samples.
            var t = start
            let expiryLast=instrument.rules.expiry.map{(($0-1)/step)*step} ?? Int64.max
            let final=min(next-step,end/step*step,expiryLast)
            let continuous = !instrument.rules.weekdaysOnly && instrument.rules.holidays.isEmpty && instrument.rules.openMinute==0 && instrument.rules.closeMinute==1440 && instrument.rules.expiry==nil
            while t<=final {
                if t%3600==0{try Task.checkCancellation()}
                if let expiry=instrument.rules.expiry,t>=expiry{break}
                let minuteEnd=min((t/60+1)*60-step,final)
                if continuous || instrument.rules.isOpen(at:t){
                    var points:Set<Int64>=[t,minuteEnd]
                    for change in state.changes{
                        for boundary in [change.time,change.time+3600,change.time+5*86400] where boundary>=t && boundary<=minuteEnd{points.insert(boundary);if boundary-step>=t{points.insert(boundary-step)}}
                    }
                    for change in state.priceAdjustments ?? [] where change.instrumentID==instrument.id && change.time>=t && change.time<=minuteEnd{points.insert(change.time);if change.time-step>=t{points.insert(change.time-step)}}
                    for point in points.sorted(){let value=try priceValue(instrument,at:point,state:state);if first==nil{first=value};last=value;high=max(high,value);low=min(low,value)}
                    var boundaries=[t,minuteEnd+step]
                    boundaries += state.changes.map(\.time).filter{$0>t && $0<=minuteEnd}
                    let ordered=Set(boundaries).sorted()
                    for (left,right) in zip(ordered,ordered.dropFirst()){volume += Double((right-left)/step)*stepVolume(instrument,at:left,state:state)}
                }
                t=minuteEnd+step
            }
            if let first,let last{
                func canonical(_ x:Double)throws->Double{try Amount(String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),x)).displayDouble}
                let candle=try Candle(time:start,open:canonical(first),high:canonical(high),low:canonical(low),close:canonical(last),volume:volume,complete:next<=state.time)
                result.append(candle);if next<=end{candleCache.put(key,candle)}
            }
            let previous=CandleCalendar.next(start,interval:interval,zone:zone,offset:-1)
            if first==nil,interval<86400{
                guard let time=try previousTradingTime(before:start,rules:instrument.rules) else{break}
                start=min(previous,CandleCalendar.start(time,interval:interval,zone:zone))
            }else{start=previous}
        }
        return result.reversed()
    }
    private static func previousTradingTime(before:Int64,rules:RulePack)throws->Int64?{
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:rules.timeZone)!
        var cursor=min(before-step,rules.expiry.map{$0-step} ?? Int64.max)
        for _ in 0..<3700{
            try Task.checkCancellation()
            if rules.isOpen(at:cursor){return cursor}
            let date=Date(timeIntervalSince1970:TimeInterval(cursor)),day=calendar.dateInterval(of:.day,for:date)!
            let close:Date
            if rules.closeMinute==1440{close=day.end}else{close=calendar.date(bySettingHour:rules.closeMinute/60,minute:rules.closeMinute%60,second:0,of:date,matchingPolicy:.nextTime,repeatedTimePolicy:.last,direction:.forward)!}
            let candidate=Int64(close.timeIntervalSince1970)-step
            if candidate<=cursor,rules.isOpen(at:candidate){return candidate}
            cursor=Int64(day.start.timeIntervalSince1970)-step
        }
        return nil
    }
    public static func catalog() throws -> [Instrument] {try InstrumentCatalog.builtIn(mode:.offline)}
    public static func legacyCatalog() throws -> [Instrument] {
        let groups: [(AssetClass, Int, String, String)] = [(.taiwanStock,30,"TWD","島嶼"),(.usStock,30,"USD","星河"),(.etf,20,"TWD","柴選"),(.crypto,20,"USD","星幣"),(.forex,10,"USD","匯流"),(.perpetual,5,"USD","永續"),(.future,5,"TWD","期契"),(.index,5,"TWD","指標")]
        var result: [Instrument] = []
        for (asset, count, currency, prefix) in groups {
            for n in 1...count {
                let symbol = "\(asset.rawValue.uppercased())\(String(format:"%02d", n))"
                var rules = RulePack(tick: try Amount(asset == .forex ? "0.00001" : asset == .crypto ? "0.01" : "0.1"), quantityStep: try Amount(asset == .crypto || asset == .forex ? "0.001" : "1"))
                rules.version="offline-sim-2"
                rules.fees.taker = try Amount("0.001"); rules.fees.maker = try Amount("0.0005")
                if asset == .taiwanStock || asset == .etf { rules.timeZone = "Asia/Taipei"; rules.weekdaysOnly = true; rules.openMinute = 9*60; rules.closeMinute = 13*60+30 }
                if asset == .usStock { rules.timeZone = "America/New_York"; rules.weekdaysOnly = true; rules.openMinute = 9*60+30; rules.closeMinute = 16*60 }
                if asset == .future { rules.multiplier = try Amount(50); rules.expiry = 1_824_940_800 }
                if asset == .future{rules.dailySettlementMinute=0}
                if asset == .perpetual{rules.carrySchedule=CarrySchedule(longRate:try Amount("0.0001"),shortRate:try Amount("-0.0001"))}
                if asset == .forex{rules.weekdaysOnly=true;rules.carrySchedule=CarrySchedule(interval:86400,longRate:try Amount("0.00005"),shortRate:try Amount("0.00005"),kind:"interest")}
                let initial = try Amount(asset == .forex ? "1.12" : String(20 + n * 17))
                result.append(Instrument(id: "SIM:\(symbol)", symbol: symbol, name: "\(prefix)\(n)\(asset.label)", asset: asset, currency: currency, rules: rules, initialPrice: initial))
            }
        }
        return result
    }
}
