import Foundation

public enum Mode: String, Codable, CaseIterable, Sendable {
    case online, offline
    public var accountID: String { self == .online ? "account-online" : "account-offline" }
    public var label: String { self == .online ? "A 真實行情・模擬交易" : "B 離線市場・模擬交易" }
}
public struct AccountContext: Codable, Equatable, Sendable {
    public let mode: Mode
    public let epoch: UUID
    public var accountID: String { mode.accountID }
    public init(mode: Mode, epoch: UUID = UUID()) { self.mode = mode; self.epoch = epoch }
}
public enum AssetClass: String, Codable, CaseIterable, Sendable {
    case taiwanStock, usStock, etf, crypto, forex, perpetual, future, index
    public var label: String {
        switch self { case .taiwanStock: "台股"; case .usStock: "美股"; case .etf: "ETF"; case .crypto: "加密現貨"; case .forex: "外匯合約"; case .perpetual: "永續合約"; case .future: "期貨"; case .index: "參考指數" }
    }
    public var derivative: Bool { [.forex, .perpetual, .future].contains(self) }
}
public struct FeeRule: Codable, Sendable, Equatable {
    public var maker: Amount = .zero
    public var taker: Amount = .zero
    public var fixed: Amount = .zero
    public var minimum: Amount = .zero
    public var sellTax: Amount = .zero
    public init() {}
    public func cumulative(notional: Amount, maker: Bool) throws -> Amount {
        guard notional > .zero else { return .zero }
        return try Swift.max(minimum, fixed + notional * (maker ? self.maker : taker)).rounded(8, .up)
    }
}
public struct RulePack: Codable, Sendable, Equatable {
    public var version = "custom-sim-1"
    public var source = "ChaiTrade 自訂模擬規則；非交易所已核驗規則"
    public var effectiveFrom: Int64 = 1_761_523_200
    public var verifiedAt: Int64? = nil
    public var tick: Amount
    public var quantityStep: Amount
    public var minimumNotional: Amount = .zero
    public var multiplier: Amount = .one
    public var fees = FeeRule()
    public var maintenance: Amount
    public var maxLeverage: Int = 20
    public var timeZone = "UTC"
    public var openMinute = 0
    public var closeMinute = 1440
    public var weekdaysOnly = false
    public var holidays: [String] = []
    public var expiry: Int64? = nil
    public var settlementBusinessDays: Int? = nil
    public init(tick: Amount, quantityStep: Amount) {
        self.tick = tick; self.quantityStep = quantityStep
        maintenance = try! Amount("0.005")
    }
    public func isOpen(at seconds: Int64) -> Bool {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let day = c.component(.weekday, from: date)
        if weekdaysOnly && (day == 1 || day == 7) { return false }
        let parts = c.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        if holidays.contains(key) { return false }
        let m = parts.hour! * 60 + parts.minute!
        let inSession = openMinute <= closeMinute ? (m >= openMinute && m < closeMinute) : (m >= openMinute || m < closeMinute)
        return inSession && (expiry == nil || seconds < expiry!)
    }
}
public struct Instrument: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var symbol: String
    public var name: String
    public var asset: AssetClass
    public var currency: String
    public var provider: ProviderID?
    public var rules: RulePack
    public var initialPrice: Amount
    public var volatility: Double = 0.002
    public var liquidity: Int = 1000
    public var halted = false
    public var requiresRuleConfirmation: Bool?
    public init(id: String, symbol: String, name: String, asset: AssetClass, currency: String, rules: RulePack, initialPrice: Amount, provider: ProviderID? = nil) {
        self.id = id; self.symbol = symbol; self.name = name; self.asset = asset; self.currency = currency
        self.rules = rules; self.initialPrice = initialPrice; self.provider = provider
    }
}
public enum DataQuality: String, Codable, Sendable { case realtime, delayed, historical, stale, unavailable }
public enum ExecutionGrade: String, Codable, Sendable { case E0, E1, E2, E3 }
public struct Level: Codable, Equatable, Sendable {
    public var price: Amount
    public var quantity: Amount
    public init(_ price: Amount, _ quantity: Amount) { self.price = price; self.quantity = quantity }
}
public struct Quote: Codable, Sendable, Equatable {
    public var instrumentID: String
    public var source: String
    public var time: Int64
    public var receivedAt: Int64
    public var sequence: Int64
    public var last: Amount
    public var mark: Amount?
    public var bids: [Level]
    public var asks: [Level]
    public var quality: DataQuality
    public var grade: ExecutionGrade
    public var coverage: String
    public var valid = true
    public var maximumAge: Int64 = 30
    public init(instrumentID: String, source: String, time: Int64, sequence: Int64, last: Amount, bids: [Level], asks: [Level], quality: DataQuality = .realtime, grade: ExecutionGrade = .E1, coverage: String = "模擬市場", receivedAt: Int64? = nil) {
        self.instrumentID = instrumentID; self.source = source; self.time = time; self.receivedAt = receivedAt ?? time
        self.sequence = sequence; self.last = last; self.bids = bids; self.asks = asks; self.quality = quality; self.grade = grade; self.coverage = coverage
    }
}
public struct Candle: Codable, Sendable, Equatable {
    public var time: Int64
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double
    public var complete: Bool
    public init(time: Int64, open: Double, high: Double, low: Double, close: Double, volume: Double, complete: Bool = true) {
        self.time = time; self.open = open; self.high = high; self.low = low; self.close = close; self.volume = volume; self.complete = complete
    }
}
public enum Side: String, Codable, CaseIterable, Sendable { case buy, sell
    public var label: String { self == .buy ? "買入／開多" : "賣出／開空" }
    public var sign: Amount { self == .buy ? .one : .one.negated }
    public var opposite: Side { self == .buy ? .sell : .buy }
}
public enum OrderKind: String, Codable, CaseIterable, Sendable {
    case market, limit, stopMarket, stopLimit, takeProfit, trailing
    public var label: String {
        switch self { case .market: "市價"; case .limit: "限價"; case .stopMarket: "停損市價"; case .stopLimit: "停損限價"; case .takeProfit: "停利條件"; case .trailing: "移動停損" }
    }
    public var conditional: Bool { ![.market, .limit].contains(self) }
}
public enum TimeInForce: String, Codable, CaseIterable, Sendable { case GTC, DAY, GTD, IOC, FOK }
public enum OrderStatus: String, Codable, Sendable { case working, partiallyFilled, filled, cancelled, expired
    public var open: Bool { self == .working || self == .partiallyFilled }
}
public enum MarginMode: String, Codable, CaseIterable, Sendable { case isolated, cross }
public enum TriggerReference: String, Codable, CaseIterable, Sendable { case last, mark, bidAsk }
public struct OrderRequest: Codable, Sendable {
    public var requestID: String = UUID().uuidString
    public var instrumentID: String
    public var side: Side
    public var kind: OrderKind
    public var quantity: Amount
    public var price: Amount?
    public var trigger: Amount?
    public var trailingDistance: Amount?
    public var trailingPercent = false
    public var triggerReference: TriggerReference = .last
    public var timeInForce: TimeInForce = .GTC
    public var expiresAt: Int64?
    public var postOnly = false
    public var reduceOnly = false
    public var leverage = 1
    public var marginMode: MarginMode = .isolated
    public var groupID: String?
    public var parentID: String?
    public var bracketProfit: Amount?
    public var bracketStop: Amount?
    public init(instrumentID: String, side: Side, kind: OrderKind, quantity: Amount, price: Amount? = nil, trigger: Amount? = nil) {
        self.instrumentID = instrumentID; self.side = side; self.kind = kind; self.quantity = quantity; self.price = price; self.trigger = trigger
    }
}
public struct Order: Codable, Identifiable, Sendable {
    public var id: String
    public var accountID: String
    public var request: OrderRequest
    public var status: OrderStatus = .working
    public var filled: Amount = .zero
    public var cumulativeNotional: Amount = .zero
    public var fees: Amount = .zero
    public var reserved: Amount = .zero
    public var referencePrice: Amount
    public var triggered = false
    public var extreme: Amount?
    public var createdAt: Int64
    public var updatedAt: Int64
    public var revision = 0
    public var ruleVersion: String
    public var suspension: String?
    public var remaining: Amount { get throws { try request.quantity - filled } }
}
public struct Fill: Codable, Identifiable, Sendable {
    public var id: String
    public var accountID: String
    public var orderID: String
    public var instrumentID: String
    public var side: Side
    public var quantity: Amount
    public var price: Amount
    public var fee: Amount
    public var tax: Amount
    public var time: Int64
    public var quoteTime: Int64
    public var source: String
    public var grade: ExecutionGrade
    public var estimatedExecution: Bool
    public var modelVersion = "shadow-depth-1"
    public var liquidityEventID: String
    public var ruleVersion: String
    public var realized: Amount
}
public struct Position: Codable, Identifiable, Sendable {
    public var id: String
    public var quantity: Amount = .zero
    public var average: Amount = .zero
    public var realized: Amount = .zero
    public var margin: Amount = .zero
    public var leverage = 1
    public var marginMode: MarginMode = .isolated
    public var openedAt: Int64 = 0
}
public struct LedgerEntry: Codable, Sendable {
    public var eventID: String
    public var accountID: String
    public var time: Int64
    public var currency: String
    public var account: String
    public var amount: Amount
}
public struct AuditEvent: Codable, Identifiable, Sendable {
    public var id: String
    public var sequence: Int64
    public var time: Int64
    public var kind: String
    public var message: String
}
public struct EquityPoint: Codable, Sendable {
    public var time: Int64
    public var value: Amount?
    public var flow: Amount
}
public struct JournalEntry: Codable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var tags: String
    public var time: Int64
    public init(id: String = UUID().uuidString, text: String, tags: String, time: Int64) { self.id = id; self.text = text; self.tags = tags; self.time = time }
}
public struct PriceAlert: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var instrumentID: String
    public var price: Amount
    public var above: Bool
    public var firedAt: Int64?
    public init(instrumentID: String, price: Amount, above: Bool) { self.instrumentID = instrumentID; self.price = price; self.above = above }
}
public struct Drawing: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var instrumentID: String
    public var kind: String
    public var time1: Int64
    public var price1: Double
    public var time2: Int64
    public var price2: Double
    public init(instrumentID: String, kind: String, time1: Int64, price1: Double, time2: Int64, price2: Double) { self.instrumentID = instrumentID; self.kind = kind; self.time1 = time1; self.price1 = price1; self.time2 = time2; self.price2 = price2 }
}
public struct AccountState: Codable, Sendable {
    public var schema = 1
    public var accountID: String
    public var mode: Mode
    public var baseCurrency: String
    public var cash: [String: Amount] = [:]
    public var netFlows: [String: Amount] = [:]
    public var orders: [String: Order] = [:]
    public var positions: [String: Position] = [:]
    public var fills: [Fill] = []
    public var ledger: [LedgerEntry] = []
    public var events: [AuditEvent] = []
    public var appliedEvents: Set<String> = []
    public var quotes: [String: Quote] = [:]
    public var consumed: [String: [Level]] = [:]
    public var instruments: [Instrument]
    public var watchlist: Set<String> = []
    public var journals: [JournalEntry] = []
    public var alerts: [PriceAlert] = []
    public var drawings: [Drawing] = []
    public var equity: [EquityPoint] = []
    public var simulation: SimulationState?
    public var allowEstimatedExecution = false
    public var leverageEnabled = false
    public var continueWhileAway = true
    public var lastWallTime: Int64?
    public var sequence: Int64 = 0
    public var lifecycle: LifecycleState?
    public init(mode: Mode, baseCurrency: String, instruments: [Instrument]) {
        self.mode = mode; self.accountID = mode.accountID; self.baseCurrency = baseCurrency; self.instruments = instruments
        if mode == .offline { self.simulation = SimulationState() }
    }
    public mutating func audit(_ kind: String, _ message: String, time: Int64, id: String? = nil) {
        sequence += 1
        events.append(AuditEvent(id: id ?? "event-\(sequence)", sequence: sequence, time: time, kind: kind, message: message))
    }
    public mutating func post(event: String, currency: String, debit: String, credit: String, amount: Amount, time: Int64) {
        ledger.append(LedgerEntry(eventID: event, accountID: accountID, time: time, currency: currency, account: debit, amount: amount))
        ledger.append(LedgerEntry(eventID: event, accountID: accountID, time: time, currency: currency, account: credit, amount: amount.negated))
    }
}
