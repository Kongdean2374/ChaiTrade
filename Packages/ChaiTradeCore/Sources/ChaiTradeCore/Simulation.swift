import Foundation

public struct SimulationState: Codable, Sendable {
    public var seed: UInt64 = 2374
    public var algorithm = "factor-wave-1"
    public var time: Int64 = 1_793_059_200 // 2026-10-26 UTC
    public var paused = false
    public var speed = 1
    public var scenario = "盤整"
    public var volatility = 1.0
    public var liquidity = 1.0
    public var changes: [SimulationChange] = []
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
    public static func price(_ instrument: Instrument, at time: Int64, state: SimulationState) throws -> Amount {
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
        let raw = instrument.initialPrice.displayDouble * exp(common + sector + slow + fast * amplitudes[regime] * vol + trend)
        let tick = instrument.rules.tick.displayDouble
        guard raw.isFinite, tick > 0 else { throw TradeError.invalid("模擬價格超出範圍") }
        return try Amount(String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), max(tick, (raw / tick).rounded() * tick)))
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
        let lastStart = (end / interval) * interval
        var result: [Candle] = []
        for offset in (0..<count).reversed() {
            let start = lastStart - Int64(offset) * interval
            var values: [Double] = []
            // Authoritative five-second events; history never consumes mutable randomness.
            var t = start
            while t <= min(start + interval - step, end) {
                if instrument.rules.isOpen(at: t) { values.append(try price(instrument, at: t, state: state).displayDouble) }
                t += step
            }
            if let first = values.first, let last = values.last {
                result.append(Candle(time: start, open: first, high: values.max()!, low: values.min()!, close: last, volume: Double(values.count * instrument.liquidity), complete: start + interval <= state.time))
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
