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
        guard state.algorithm == "factor-wave-1" else { throw TradeError.unavailable("模擬演算法版本不相容，保留檢查點") }
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
        let raw = instrument.initialPrice.displayDouble * adjustment * exp(common + sector + slow + fast * amplitudes[regime] * vol + trend)
        let tick = instrument.rules.tick.displayDouble
        guard raw.isFinite, tick > 0 else { throw TradeError.invalid("模擬價格超出範圍") }
        return max(tick, (raw / tick).rounded() * tick)
    }
    public static func price(_ instrument: Instrument, at time: Int64, state: SimulationState) throws -> Amount {
        try Amount(String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),priceValue(instrument,at:time,state:state)))
    }
    public static func quote(_ instrument: Instrument, state: SimulationState) throws -> Quote {
        let time = state.time, price = try price(instrument, at: time, state: state)
        let spreadSteps = max(1, Int((price.displayDouble * 0.00015) / instrument.rules.tick.displayDouble))
        let spread = try instrument.rules.tick * Amount(spreadSteps)
        let liquidity = state.changes.last(where: { $0.time <= time })?.liquidity ?? 1
        let count = max(1, Int(Double(instrument.liquidity) * liquidity))
        var bids: [Level] = [], asks: [Level] = []
        for level in 1...8 {
            let delta = try spread * Amount(level)
            let size = try instrument.rules.quantityStep * Amount(max(1, count / level))
            bids.append(Level(max(instrument.rules.tick, try price - delta), size))
            asks.append(Level(try price + delta, size))
        }
        var q = Quote(instrumentID: instrument.id, source: "B 決定性離線市場", time: time, sequence: time / step, last: price, bids: bids, asks: asks)
        if instrument.asset.derivative { q.mark = price }
        return q
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
        for offset in (0..<count).reversed() {
            try Task.checkCancellation()
            let start=CandleCalendar.next(lastStart,interval:interval,zone:zone,offset:-offset)
            if start < state.time-10*366*86400{continue}
            let next=CandleCalendar.next(start,interval:interval,zone:zone)
            let key=prefix+String(start)
            if next<=end,let cached=candleCache.get(key){result.append(cached);continue}
            var first:Double?,last:Double?,high = -Double.infinity,low=Double.infinity,events=0
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
                    events+=Int((minuteEnd-t)/step+1)
                }
                t=minuteEnd+step
            }
            if let first,let last{
                func canonical(_ x:Double)throws->Double{try Amount(String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),x)).displayDouble}
                let candle=try Candle(time:start,open:canonical(first),high:canonical(high),low:canonical(low),close:canonical(last),volume:Double(events*instrument.liquidity),complete:next<=state.time)
                result.append(candle);if next<=end{candleCache.put(key,candle)}
            }
        }
        return result
    }
    public static func catalog() throws -> [Instrument] {
        let groups: [(AssetClass, Int, String, String)] = [(.taiwanStock,30,"TWD","島嶼"),(.usStock,30,"USD","星河"),(.etf,20,"TWD","柴選"),(.crypto,20,"USD","星幣"),(.forex,10,"USD","匯流"),(.perpetual,5,"USD","永續"),(.future,5,"TWD","期契"),(.index,5,"TWD","指標")]
        var result: [Instrument] = []
        for (asset, count, currency, prefix) in groups {
            for n in 1...count {
                let symbol = "\(asset.rawValue.uppercased())\(String(format:"%02d", n))"
                var rules = RulePack(tick: try Amount(asset == .forex ? "0.00001" : asset == .crypto ? "0.01" : "0.1"), quantityStep: try Amount(asset == .crypto || asset == .forex ? "0.001" : "1"))
                rules.fees.taker = try Amount("0.001"); rules.fees.maker = try Amount("0.0005")
                if asset == .taiwanStock || asset == .etf { rules.timeZone = "Asia/Taipei"; rules.weekdaysOnly = true; rules.openMinute = 9*60; rules.closeMinute = 13*60+30 }
                if asset == .usStock { rules.timeZone = "America/New_York"; rules.weekdaysOnly = true; rules.openMinute = 9*60+30; rules.closeMinute = 16*60 }
                if asset == .future { rules.multiplier = try Amount(50); rules.expiry = 1_824_940_800 }
                let initial = try Amount(asset == .forex ? "1.12" : String(20 + n * 17))
                result.append(Instrument(id: "SIM:\(symbol)", symbol: symbol, name: "\(prefix)\(n)\(asset.label)", asset: asset, currency: currency, rules: rules, initialPrice: initial))
            }
        }
        return result
    }
}
