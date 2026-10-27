import Foundation

public struct Valuation: Sendable {
    public var total: Amount
    public var complete: Bool
    public var missing: [String]
    public var tradingPnL: Amount?
}
public struct FXRate: Codable, Sendable {
    public var currency: String
    public var base: String
    public var rate: Amount
    public var time: Int64
    public var source: String
    public init(currency: String, base: String, rate: Amount, time: Int64, source: String) { self.currency = currency; self.base = base; self.rate = rate; self.time = time; self.source = source }
}
public enum Analytics {
    public static func fillTotals(_ s:AccountState)throws->[String:FillTotals]{
        var totals=s.history?.totals ?? [:]
        let currencies=Dictionary(uniqueKeysWithValues:s.instruments.map{($0.id,$0.currency)})
        for fill in s.fills{guard let currency=currencies[fill.instrumentID] else{throw TradeError.corrupt("未知商品成交")};var total=totals[currency] ?? FillTotals();try total.include(fill);totals[currency]=total}
        return totals
    }
    public static func valuation(_ state: AccountState, rates: [FXRate] = []) throws -> Valuation {
        var total = Amount.zero, flows = Amount.zero, missing: [String] = []
        func convert(_ value: Amount, currency: String) throws -> Amount? {
            if value == .zero { return .zero }
            if currency == state.baseCurrency { return value }
            guard let rate = (rates + (state.lifecycle?.rates ?? [])).first(where: { $0.currency == currency && $0.base == state.baseCurrency && $0.rate > .zero }) else { missing.append("缺少 \(currency)/\(state.baseCurrency) 匯率"); return nil }
            return try value * rate.rate
        }
        for (currency,cash) in state.cash { if let converted = try convert(cash,currency:currency) { total = try total + converted } }
        for (currency,flow) in state.netFlows { if let converted = try convert(flow,currency:currency) { flows = try flows + converted } }
        for event in state.lifecycle?.settlements ?? [] where event.completedAt == nil {
            if let converted=try convert(event.receivable-event.payable,currency:event.currency){total=try total+converted}
        }
        for p in state.positions.values where p.quantity != .zero {
            guard let instrument = state.instruments.first(where: { $0.id == p.id }), let q = state.quotes[p.id] else { missing.append("缺少 \(p.id) 估值價格"); continue }
            let price = instrument.asset.derivative ? q.mark : q.last
            guard let price else { missing.append("缺少 \(p.id) 標記價"); continue }
            if q.quality != .realtime { missing.append("\(p.id) 使用最後已知價格（非即時）") }
            let value = instrument.asset.derivative ? try (price - p.average) * p.quantity * instrument.rules.multiplier : try price * p.quantity
            if let converted = try convert(value, currency:instrument.currency) { total = try total + converted }
        }
        return Valuation(total:total,complete:missing.isEmpty,missing:Array(Set(missing)).sorted(),tradingPnL:missing.isEmpty ? try total - flows : nil)
    }
    public static func csvCell(_ value: String) -> String {
        let bytes=Array(value.utf8),start=bytes.first==45 ? 1:0
        var dot=false,digit=false,numeric=bytes.count>start
        for n in start..<bytes.count{let c=bytes[n];if c>=48 && c<=57{digit=true}else if c==46 && !dot && digit && n+1<bytes.count{dot=true}else{numeric=false;break}}
        numeric = numeric && digit
        let dangerous = !numeric && (value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@\t\r".contains($0) } ?? false)
        return "\"" + (dangerous ? "'" : "") + value.replacingOccurrences(of:"\"",with:"\"\"") + "\""
    }
    public static let fillHeader=["模擬交易","accountID","mode","schema","exportedAt","fillID","instrument","side","quantity","price","fee","tax","time","estimatedExecution"]
    public static func fillFields(_ f:Fill)->[String]{[f.id,f.instrumentID,f.side.rawValue,f.quantity.description,f.price.description,f.fee.description,f.tax.description,String(f.time),String(f.estimatedExecution)]}
    public static func fillRow(_ f:Fill,account s:AccountState,time:Int64)->[String]{["模擬交易",s.accountID,s.mode.rawValue,String(s.schema),String(time)]+fillFields(f)}
    public static let orderHeader=["模擬交易","accountID","mode","schema","exportedAt","orderID","instrument","side","kind","status","quantity","filled","price","trigger","timeInForce","ruleVersion"]
    public static func orderRow(_ o:Order,account s:AccountState,time:Int64)->[String]{["模擬交易",s.accountID,s.mode.rawValue,String(s.schema),String(time),o.id,o.request.instrumentID,o.request.side.rawValue,o.request.kind.rawValue,o.status.rawValue,o.request.quantity.description,o.filled.description,o.request.price?.description ?? "",o.request.trigger?.description ?? "",o.request.timeInForce.rawValue,o.ruleVersion]}
    public static func fillsCSV(_ s: AccountState, time: Int64) -> String {
        var output=fillHeader.map(csvCell).joined(separator:",")
        for f in s.fills{output += "\r\n"+fillRow(f,account:s,time:time).map(csvCell).joined(separator:",")}
        return output
    }
    public static func ledgerCSV(_ s: AccountState, time: Int64) -> String {
        var output=["模擬交易","accountID","exportedAt","eventID","time","currency","account","amount"].map(csvCell).joined(separator:",")
        for e in s.ledger{output += "\r\n"+["模擬交易",s.accountID,String(time),e.eventID,String(e.time),e.currency,e.account,e.amount.description].map(csvCell).joined(separator:",")}
        return output
    }
    public static func ordersCSV(_ s: AccountState,time: Int64) -> String {
        var output=orderHeader.map(csvCell).joined(separator:",")
        for o in s.orders.values.sorted(by:{$0.createdAt<$1.createdAt}){output += "\r\n"+orderRow(o,account:s,time:time).map(csvCell).joined(separator:",")}
        return output
    }
    /// Time-weighted return removes external flows at each valuation boundary.
    public static func timeWeighted(_ points: [EquityPoint]) -> [Double?] {
        var nav = 1.0, last: Double? = nil
        return points.map { point in
            guard let value = point.value?.displayDouble else { last = nil; return nil }
            defer { last = value }
            if let prior = last, prior > 0 { nav *= (value - point.flow.displayDouble) / prior }
            return nav
        }
    }
    public static func maximumDrawdown(_ nav: [Double?]) -> Double? {
        var peak = 0.0, drawdown = 0.0; var found = false
        for case let value? in nav where value > 0 { found = true; peak = max(peak,value); drawdown = max(drawdown,(peak-value)/peak) }
        return found ? drawdown : nil
    }
}

/// Presentation/analysis only. Financial settlement never reads these Double results.
public enum Indicators {
    public static func ma(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return values.map { _ in nil } }
        var sum = 0.0
        return values.indices.map { n in sum += values[n]; if n >= period { sum -= values[n-period] }; return n+1 >= period ? sum/Double(period) : nil }
    }
    public static func ema(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0 else { return values.map { _ in nil } }
        let sma = ma(values,period:period); var last: Double?
        return values.indices.map { n in
            if let old = last { last = old + (values[n]-old)*2/Double(period+1) }
            else if let seed = sma[n] { last = seed }
            return last
        }
    }
    public static func rsi(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count > period else { return values.map { _ in nil } }
        var result = [Double?](repeating:nil,count:values.count), gain = 0.0, loss = 0.0
        for n in 1..<values.count {
            let change = values[n]-values[n-1]
            if n <= period { gain += max(change,0)/Double(period); loss += max(-change,0)/Double(period) }
            else { gain = (gain*Double(period-1)+max(change,0))/Double(period); loss = (loss*Double(period-1)+max(-change,0))/Double(period) }
            if n >= period { result[n] = loss == 0 ? (gain == 0 ? 50 : 100) : 100-100/(1+gain/loss) }
        }
        return result
    }
    public static func macd(_ values: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> (line:[Double?], signal:[Double?], histogram:[Double?]) {
        let a = ema(values,period:fast), b = ema(values,period:slow)
        let line: [Double?] = values.indices.map { n in guard let x = a[n],let y = b[n] else { return nil }; return x-y }
        let compact = line.compactMap{$0}, smoothed = ema(compact,period:signal)
        let padding = values.count-compact.count
        let signals = [Double?](repeating:nil,count:padding)+smoothed
        let histogram: [Double?] = values.indices.map { guard let x = line[$0],let y = signals[$0] else { return nil }; return x-y }
        return (line,signals,histogram)
    }
    public static func bollinger(_ values: [Double], period: Int = 20, deviations: Double = 2) -> (middle:[Double?], upper:[Double?], lower:[Double?]) {
        let middle = ma(values,period:period)
        var upper = middle, lower = middle
        for n in values.indices { if let mean = middle[n] {
            let variance = values[(n-period+1)...n].reduce(0) { $0+pow($1-mean,2) }/Double(period)
            upper[n] = mean + deviations*sqrt(variance); lower[n] = mean-deviations*sqrt(variance)
        }}
        return (middle,upper,lower)
    }
    public static func atr(_ candles: [Candle], period: Int = 14) -> [Double?] {
        guard period > 0 else { return candles.map { _ in nil } }
        let tr = candles.indices.map { n in n == 0 ? candles[n].high-candles[n].low : max(candles[n].high-candles[n].low,abs(candles[n].high-candles[n-1].close),abs(candles[n].low-candles[n-1].close)) }
        var last: Double?; let seed = ma(tr,period:period)
        return tr.indices.map { n in if let old = last { last = (old*Double(period-1)+tr[n])/Double(period) } else { last = seed[n] }; return last }
    }
    public static func kd(_ candles: [Candle], period: Int = 9) -> (k:[Double?],d:[Double?]) {
        guard period > 0 else { return (candles.map{_ in nil},candles.map{_ in nil}) }
        var k = 50.0,d = 50.0, ks = [Double?](repeating:nil,count:candles.count),ds = ks
        for n in candles.indices where n >= period-1 {
            let window = candles[(n-period+1)...n], hi = window.map(\.high).max()!,lo = window.map(\.low).min()!
            let rsv = hi == lo ? 50 : (candles[n].close-lo)/(hi-lo)*100
            k = k*2/3+rsv/3; d = d*2/3+k/3; ks[n]=k;ds[n]=d
        }
        return (ks,ds)
    }
    public static func vwap(_ candles: [Candle], timeZone: String = "UTC") -> [Double?] {
        var pv = 0.0,volume = 0.0, lastDay: DateComponents?
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:timeZone) ?? .gmt
        return candles.map { candle in
            let day = calendar.dateComponents([.year,.month,.day],from:Date(timeIntervalSince1970:TimeInterval(candle.time)))
            if day != lastDay { pv=0;volume=0;lastDay=day }
            guard let v=candle.volume else{return nil}
            pv += (candle.high+candle.low+candle.close)/3*v; volume += v
            return volume > 0 ? pv/volume : nil
        }
    }
}
