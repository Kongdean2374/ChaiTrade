import Foundation

public actor TradingEngine {
    public nonisolated let context: AccountContext
    private let repository: AccountRepository
    private var state: AccountState
    public init(context: AccountContext, repository: AccountRepository, initial: AccountState) throws {
        guard context.mode == repository.mode else { throw TradeError.wrongAccount }
        try AccountRepository.validate(initial, mode: context.mode)
        self.context = context; self.repository = repository; self.state = initial
        try repository.save(initial)
    }
    public func snapshot() -> AccountState { state }
    private func check(_ context: AccountContext) throws {
        guard context == self.context else { throw TradeError.wrongAccount }
    }
    @discardableResult private func transaction<T>(_ body: (inout AccountState) throws -> T) throws -> T {
        var next = state
        let result = try body(&next)
        try repository.save(next)
        state = next
        return result
    }
    public static func initial(mode: Mode, baseCurrency: String = "TWD", capital: Amount, time: Int64) throws -> AccountState {
        var s = AccountState(mode: mode, baseCurrency: baseCurrency, instruments: try mode == .offline ? Simulation.catalog() : Providers.catalog())
        try adjustCash(&s, currency: baseCurrency, amount: capital, time: time, eventID: "initial-capital")
        return s
    }
    public static func available(_ state: AccountState, currency: String, excluding: String? = nil) throws -> Amount {
        var groups: [String: Amount] = [:]
        for order in state.orders.values where order.status.open && order.id != excluding {
            guard let i = state.instruments.first(where: { $0.id == order.request.instrumentID }), i.currency == currency else { continue }
            let key = order.request.groupID ?? order.id
            groups[key] = max(groups[key] ?? .zero, order.reserved)
        }
        let locked = try sum(state.positions.values.compactMap { p -> Amount? in
            state.instruments.first(where: { $0.id == p.id })?.currency == currency ? p.margin : nil
        })
        return try (state.cash[currency] ?? .zero) - sum(groups.values) - locked
    }
    private static func adjustCash(_ s: inout AccountState, currency: String, amount: Amount, time: Int64, eventID: String) throws {
        guard !s.appliedEvents.contains(eventID) else { return }
        if try amount < .zero && amount.magnitude > available(s, currency: currency) { throw TradeError.insufficient("減資超過可用資金；請先撤單或平倉") }
        s.cash[currency] = try (s.cash[currency] ?? .zero) + amount
        s.netFlows[currency] = try (s.netFlows[currency] ?? .zero) + amount
        s.post(event: eventID, currency: currency, debit: "cash", credit: "external-capital", amount: amount, time: time)
        s.appliedEvents.insert(eventID); s.audit("cashFlow", "虛擬資金調整 \(currency) \(amount)", time: time, id: eventID)
    }
    public func cashFlow(currency: String, amount: Amount, time: Int64, eventID: String = UUID().uuidString, context: AccountContext) throws {
        try check(context)
        guard currency.range(of: "^[A-Z]{3,8}$", options: .regularExpression) != nil else { throw TradeError.invalid("幣別代碼不合法") }
        try transaction { try Self.adjustCash(&$0, currency: currency, amount: amount, time: time, eventID: eventID) }
    }
    public func exchange(from: String, to: String, amount: Amount, rate: Amount, time: Int64, eventID: String = UUID().uuidString, context: AccountContext) throws {
        try check(context)
        guard from != to, amount > .zero, rate > .zero else { throw TradeError.invalid("換匯資料不合法") }
        try transaction { s in
            if s.appliedEvents.contains(eventID) { return }
            guard try Self.available(s, currency: from) >= amount else { throw TradeError.insufficient("換匯資金不足") }
            let received = try amount * rate
            s.cash[from] = try (s.cash[from] ?? .zero) - amount; s.cash[to] = try (s.cash[to] ?? .zero) + received
            s.post(event: eventID, currency: from, debit: "fx-clearing", credit: "cash", amount: amount, time: time)
            s.post(event: eventID, currency: to, debit: "cash", credit: "fx-clearing", amount: received, time: time)
            s.appliedEvents.insert(eventID); s.audit("exchange", "自訂模擬換匯 \(from)/\(to) @ \(rate)", time: time)
        }
    }
    private static func instrument(_ s: AccountState, _ id: String) throws -> Instrument {
        guard let i = s.instruments.first(where: { $0.id == id }) else { throw TradeError.invalid("找不到商品") }; return i
    }
    private static func validate(_ r: OrderRequest, in s: AccountState, time: Int64, excluding: String? = nil) throws -> (Instrument, Amount, Amount) {
        let i = try instrument(s, r.instrumentID)
        guard i.asset != .index, !i.halted else { throw TradeError.invalid("此商品目前不可交易（指數只供參考）") }
        guard i.rules.expiry == nil || time < i.rules.expiry! else { throw TradeError.invalid("合約已到期") }
        guard r.quantity > .zero, try r.quantity.isMultiple(of: i.rules.quantityStep) else { throw TradeError.invalid("數量不符合商品級距") }
        for p in [r.price, r.trigger].compactMap({$0}) {
            guard p > .zero, try p.isMultiple(of: i.rules.tick) else { throw TradeError.invalid("價格不符合最小跳動") }
        }
        if [.limit, .stopLimit].contains(r.kind) && r.price == nil { throw TradeError.invalid("請輸入限價") }
        if r.kind.conditional && r.kind != .trailing && r.trigger == nil { throw TradeError.invalid("請輸入觸發價") }
        if r.kind == .trailing && (r.trailingDistance ?? .zero) <= .zero { throw TradeError.invalid("移動停損距離必須大於零") }
        if r.trailingPercent && (r.trailingDistance ?? .zero) >= .one { throw TradeError.invalid("百分比距離需小於 1（例如 0.05）") }
        if r.timeInForce == .GTD && (r.expiresAt ?? 0) <= time { throw TradeError.invalid("GTD 到期時間必須在未來") }
        if r.postOnly && r.kind != .limit { throw TradeError.invalid("Post-only 只適用限價委託") }
        guard r.leverage >= 1, r.leverage <= i.rules.maxLeverage else { throw TradeError.invalid("槓桿超出規則上限") }
        if i.asset.derivative && !s.leverageEnabled { throw TradeError.invalid("請先於設定確認啟用合約風險功能") }
        let position = s.positions[i.id]?.quantity ?? .zero
        if r.reduceOnly {
            guard position != .zero, position.sign != r.side.sign.sign, r.quantity <= position.magnitude else { throw TradeError.invalid("Reduce-only 不能增加或反向建立部位") }
        }
        if !i.asset.derivative && r.side == .sell {
            var groups: [String: Amount] = [:]
            for o in s.orders.values where o.status.open && o.id != excluding && o.request.instrumentID == i.id && o.request.side == .sell {
                if r.groupID != nil && o.request.groupID == r.groupID { continue }
                let key = o.request.groupID ?? o.id
                groups[key] = max(groups[key] ?? .zero, try o.remaining)
            }
            guard try r.quantity + sum(groups.values) <= position else { throw TradeError.insufficient("可用持倉不足，或已由其他委託保留") }
        }
        let q = s.quotes[i.id]
        let ref = r.price ?? q?.last ?? i.initialPrice
        guard ref > .zero else { throw TradeError.unavailable("缺少有效價格，請先更新行情；不使用合成報價估算保留資金") }
        let protection = try Amount("0.05")
        let protected = r.kind == .limit || r.kind == .stopLimit ? ref : try ref * (.one + protection)
        let notional = try protected * r.quantity * i.rules.multiplier
        guard notional >= i.rules.minimumNotional else { throw TradeError.invalid("未達最小名目金額") }
        let fee = try i.rules.fees.cumulative(notional: notional, maker: false)
        let reducing = position != .zero && position.sign != r.side.sign.sign
        let openingQty = reducing ? max(.zero, try r.quantity - position.magnitude) : r.quantity
        let reservation: Amount
        if i.asset.derivative { reservation = try protected * openingQty * i.rules.multiplier / Amount(r.leverage) + fee }
        else if r.side == .buy { reservation = try notional + fee }
        else { reservation = .zero }
        var groupCredit: Amount = .zero
        if let group = r.groupID {
            groupCredit = s.orders.values.filter { $0.status.open && $0.request.groupID == group && $0.id != excluding }.map(\.reserved).max() ?? .zero
        }
        guard try reservation <= available(s, currency: i.currency, excluding: excluding) + groupCredit else { throw TradeError.insufficient("\(i.currency) 可用資金不足（含費用及價格保護）") }
        if r.postOnly, let q {
            let cross = r.side == .buy ? (q.asks.first.map { $0.price <= ref } ?? false) : (q.bids.first.map { $0.price >= ref } ?? false)
            if cross { throw TradeError.invalid("Post-only 會立即吃單，已拒絕") }
        }
        return (i, ref, reservation)
    }
    @discardableResult private static func accept(_ r: OrderRequest, in s: inout AccountState, time: Int64) throws -> String {
        if let existing = s.orders.values.first(where: { $0.request.requestID == r.requestID }) { return existing.id }
        let (i, ref, reservation) = try validate(r, in: s, time: time)
        let id = r.requestID
        s.orders[id] = Order(id: id, accountID: s.accountID, request: r, reserved: reservation, referencePrice: ref, createdAt: time, updatedAt: time, ruleVersion: i.rules.version)
        s.audit("accepted", "\(i.symbol) \(r.kind.label) \(r.quantity)", time: time)
        return id
    }
    @discardableResult public func submit(_ request: OrderRequest, time: Int64, context: AccountContext) throws -> String {
        try check(context)
        return try transaction { s in
            let id = try Self.accept(request, in: &s, time: time)
            if let q = s.quotes[request.instrumentID] { try Self.match(&s, quote: q, now: time) }
            return id
        }
    }
    public func submitOCO(_ first: OrderRequest, _ second: OrderRequest, time: Int64, context: AccountContext) throws {
        try check(context)
        guard first.instrumentID == second.instrumentID, first.side == second.side, first.quantity == second.quantity else { throw TradeError.invalid("OCO 需同商品、同方向、同數量") }
        try transaction { s in
            var a = first, b = second; let group = "oco-\(first.requestID)"
            a.groupID = group; b.groupID = group
            _ = try Self.accept(a, in: &s, time: time); _ = try Self.accept(b, in: &s, time: time)
            if let q = s.quotes[a.instrumentID] { try Self.match(&s, quote: q, now: time) }
        }
    }
    public func cancel(id: String, time: Int64, context: AccountContext) throws {
        try check(context)
        try transaction { s in
            guard var o = s.orders[id], o.status.open else { return }
            o.status = .cancelled; o.reserved = .zero; o.updatedAt = time; s.orders[id] = o
            s.audit("cancelled", "本機撤單 \(id)", time: time)
        }
    }
    public func amend(id: String, quantity: Amount, price: Amount?, time: Int64, context: AccountContext) throws {
        try check(context)
        try transaction { s in
            guard var o = s.orders[id], o.status.open, quantity > o.filled else { throw TradeError.invalid("委託已完成或新總量不大於成交量") }
            var r = o.request; r.quantity = try quantity - o.filled; r.price = price
            let (_, ref, reservation) = try Self.validate(r, in: s, time: time, excluding: id)
            o.request.quantity = quantity; o.request.price = price; o.referencePrice = ref; o.reserved = reservation
            o.revision += 1; o.updatedAt = time; s.orders[id] = o
            s.audit("amended", "改單第 \(o.revision) 次，重新計算保留", time: time)
            if let q = s.quotes[r.instrumentID] { try Self.match(&s, quote: q, now: time) }
        }
    }
    public func ingest(_ quote: Quote, now: Int64, context: AccountContext) throws {
        try check(context)
        guard state.mode == .online else { throw TradeError.invalid("B 模式拒絕外部行情") }
        try transaction { s in
            if let old = s.quotes[quote.instrumentID], old.source == quote.source, old.sequence >= quote.sequence { return }
            s.quotes[quote.instrumentID] = quote
            try Self.match(&s, quote: quote, now: now)
            try Self.risk(&s, quote: quote, now: now)
        }
    }
    private static func trigger(_ o: inout Order, _ q: Quote) throws -> Bool {
        if !o.request.kind.conditional || o.triggered { return true }
        let price: Amount
        switch o.request.triggerReference {
        case .last: price = q.last
        case .mark: guard let mark = q.mark else { o.suspension = "缺少標記價"; return false }; price = mark
        case .bidAsk: guard let p = o.request.side == .buy ? q.asks.first?.price : q.bids.first?.price else { return false }; price = p
        }
        if o.request.kind == .trailing {
            let old = o.extreme ?? price
            o.extreme = o.request.side == .sell ? max(old, price) : min(old, price)
            let distance = o.request.trailingPercent ? try o.extreme! * o.request.trailingDistance! : o.request.trailingDistance!
            o.request.trigger = o.request.side == .sell ? try o.extreme! - distance : try o.extreme! + distance
        }
        guard let t = o.request.trigger else { return false }
        let above = o.request.kind == .takeProfit ? o.request.side == .sell : o.request.side == .buy
        o.triggered = above ? price >= t : price <= t
        return o.triggered
    }
    private static func match(_ s: inout AccountState, quote q: Quote, now: Int64) throws {
        let i = try instrument(s, q.instrumentID)
        let fresh = q.quality == .realtime && q.valid && now >= q.time - 5 && now - q.time <= q.maximumAge && now - q.receivedAt <= q.maximumAge
        let bookValid = q.bids.allSatisfy { $0.price > .zero && $0.quantity >= .zero } && q.asks.allSatisfy { $0.price > .zero && $0.quantity >= .zero } && (q.bids.first == nil || q.asks.first == nil || q.bids[0].price < q.asks[0].price)
        let gradeOK = q.grade == .E1 || q.grade == .E2 || (q.grade == .E3 && s.allowEstimatedExecution)
        let ordered = s.orders.values.filter { $0.status.open && $0.request.instrumentID == i.id }.sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }.map(\.id)
        for id in ordered {
            guard var o = s.orders[id], o.status.open else { continue }
            let startingFilled = o.filled
            let dayExpired = o.request.timeInForce == .DAY && utcDay(o.createdAt, zone: i.rules.timeZone) != utcDay(now, zone: i.rules.timeZone)
            if dayExpired || (o.request.expiresAt.map { now >= $0 } ?? false) {
                o.status = .expired; o.reserved = .zero; s.orders[id] = o; s.audit("expired", id, time: now); continue
            }
            guard fresh && bookValid && gradeOK && i.rules.isOpen(at: q.time) && !i.halted else {
                o.suspension = !fresh ? "行情過期或非即時，暫停成交" : !bookValid ? "委託簿無效" : !gradeOK ? "資料能力不足；E3 估算須明確啟用" : "非交易時段或停牌"
                s.orders[id] = o; continue
            }
            o.suspension = nil
            let wasTriggered = o.triggered
            guard try trigger(&o, q) else { s.orders[id] = o; continue }
            if !wasTriggered && o.triggered && o.request.kind != .stopLimit { o.referencePrice = q.last }
            let key = "\(i.id)|\(o.request.side.rawValue)"
            let stamp = "\(key)|\(q.source)|\(q.sequence)"
            var levels: [Level]
            if let saved = s.consumed[stamp] { levels = saved }
            else {
                for k in s.consumed.keys.filter({ $0.hasPrefix(key + "|") }) { s.consumed.removeValue(forKey: k) }
                levels = o.request.side == .buy ? q.asks : q.bids
                if q.grade == .E3 {
                    let delta = try q.last * Amount("0.001")
                    levels = [Level(o.request.side == .buy ? try q.last + delta : try q.last - delta, try i.rules.quantityStep * Amount(100))]
                }
            }
            levels.sort { o.request.side == .buy ? $0.price < $1.price : $0.price > $1.price }
            var needed = try o.remaining
            if o.request.reduceOnly {
                let position = s.positions[i.id]?.quantity ?? .zero
                if position == .zero || position.sign == o.request.side.sign.sign { o.status = .cancelled; o.reserved = .zero; s.orders[id] = o; continue }
                needed = min(needed, position.magnitude)
            }
            let limited = o.request.kind == .limit || o.request.kind == .stopLimit
            let guardPrice = limited ? o.request.price! : (o.request.side == .buy ? try o.referencePrice * Amount("1.05") : try o.referencePrice * Amount("0.95"))
            var plan: [(Int,Amount)] = []
            for n in levels.indices where needed > .zero {
                let p = levels[n].price
                guard o.request.side == .buy ? p <= guardPrice : p >= guardPrice else { continue }
                let quantity = min(needed, levels[n].quantity)
                if quantity > .zero { plan.append((n,quantity)); needed = try needed - quantity }
            }
            if o.request.timeInForce == .FOK && needed > .zero { plan = [] }
            for (n, quantity) in plan {
                // Funds and fees are checked again at execution; a gap cannot consume unbounded cash.
                let before = s
                do {
                    try execute(&s, order: &o, quantity: quantity, price: levels[n].price, instrument: i, quote: q, now: now)
                    levels[n].quantity = try levels[n].quantity - quantity
                } catch TradeError.insufficient(let reason) { s = before; o.suspension = reason; break }
            }
            if (try o.remaining) == .zero { o.status = .filled; o.reserved = .zero }
            else if o.filled > .zero { o.status = .partiallyFilled }
            if [.IOC,.FOK].contains(o.request.timeInForce) && o.status.open { o.status = .cancelled; o.reserved = .zero }
            if !limited && !o.request.kind.conditional && o.status.open { o.status = .cancelled; o.reserved = .zero }
            s.orders[id] = o; s.consumed[stamp] = levels
            if o.filled > startingFilled {
                // Group cancellation is atomic with fills. The first fill wins.
                if let group = o.request.groupID {
                    for sibling in s.orders.keys where sibling != id && s.orders[sibling]?.request.groupID == group && s.orders[sibling]!.status.open {
                        s.orders[sibling]!.status = .cancelled; s.orders[sibling]!.reserved = .zero
                    }
                }
                if let parentID = o.request.parentID, var parent = s.orders[parentID] {
                    if parent.status.open { parent.status = .cancelled; parent.reserved = .zero; s.orders[parentID] = parent }
                    // A partially filled exit is replaced by a new, correctly sized protection group.
                    if s.orders[id]!.status.open { s.orders[id]!.status = .cancelled; s.orders[id]!.reserved = .zero }
                    try protect(&s, parent: parent, time: now)
                }
            }
            if o.filled > .zero && o.request.parentID == nil { try protect(&s, parent: o, time: now) }
        }
        for idx in s.alerts.indices where s.alerts[idx].instrumentID == i.id && s.alerts[idx].firedAt == nil {
            let a = s.alerts[idx]
            if a.above ? q.last >= a.price : q.last <= a.price { s.alerts[idx].firedAt = now; s.audit("priceAlert", "\(i.symbol) 到價 \(a.price)", time: now, id: "alert-\(a.id)") }
        }
    }
    private static func execute(_ s: inout AccountState, order o: inout Order, quantity: Amount, price: Amount, instrument i: Instrument, quote q: Quote, now: Int64) throws {
        let notional = try quantity * price * i.rules.multiplier
        let totalNotional = try o.cumulativeNotional + notional
        let cumulativeFee = try i.rules.fees.cumulative(notional: totalNotional, maker: o.request.postOnly)
        let fee = try max(.zero, cumulativeFee - o.fees)
        let tax = o.request.side == .sell ? try notional * i.rules.fees.sellTax : .zero
        var p = s.positions[i.id] ?? Position(id: i.id)
        let old = p.quantity, delta = try quantity * o.request.side.sign
        let closing = old.sign != 0 && old.sign != delta.sign ? min(old.magnitude, quantity) : .zero
        let realized = try (price - p.average) * closing * Amount(old.sign) * i.rules.multiplier
        let next = try old + delta
        if old == .zero || old.sign == delta.sign {
            p.average = try (p.average * old.magnitude + price * quantity) / next.magnitude
        } else if next == .zero { p.average = .zero }
        else if next.sign != old.sign { p.average = price }
        let oldMargin = p.margin
        p.quantity = next; p.realized = try p.realized + realized
        p.leverage = o.request.leverage; p.marginMode = o.request.marginMode
        if old == .zero { p.openedAt = now }
        if i.asset.derivative {
            let released = old == .zero ? .zero : try oldMargin * closing / old.magnitude
            let opening = try quantity - closing
            p.margin = try oldMargin - released + opening * price * i.rules.multiplier / Amount(o.request.leverage)
        }
        let cashDelta = i.asset.derivative ? try realized - fee - tax : try (o.request.side == .buy ? notional.negated : notional) - fee - tax
        let newCash = try (s.cash[i.currency] ?? .zero) + cashDelta
        let otherLocks = try (s.cash[i.currency] ?? .zero) - available(s, currency: i.currency, excluding: o.id) - oldMargin
        guard newCash >= (try otherLocks + p.margin) else { throw TradeError.insufficient("成交時可用資金不足，保留原帳務") }
        s.cash[i.currency] = newCash; s.positions[i.id] = p
        o.filled = try o.filled + quantity; o.cumulativeNotional = totalNotional; o.fees = cumulativeFee
        o.updatedAt = now
        let rem = try o.remaining
        o.reserved = o.request.quantity == .zero ? .zero : try o.reserved * rem / (rem + quantity)
        let fillID = "fill-\(o.id)-\(s.sequence + 1)"
        let fill = Fill(id: fillID, accountID: s.accountID, orderID: o.id, instrumentID: i.id, side: o.request.side, quantity: quantity, price: price, fee: fee, tax: tax, time: now, quoteTime: q.time, source: q.source, grade: q.grade, estimatedExecution: q.grade == .E3, liquidityEventID: "\(q.source)-\(q.sequence)", ruleVersion: o.ruleVersion, realized: realized)
        s.fills.append(fill)
        s.post(event: fillID, currency: i.currency, debit: "cash", credit: i.asset.derivative ? "derivative-clearing" : "spot-clearing", amount: i.asset.derivative ? realized : (o.request.side == .buy ? notional.negated : notional), time: now)
        s.post(event: fillID, currency: i.currency, debit: "fees", credit: "cash", amount: try fee + tax, time: now)
        s.audit("fill", "\(i.symbol) \(o.request.side.label) \(quantity) @ \(price)；\(q.grade.rawValue)", time: now, id: fillID)
    }
    private static func protect(_ s: inout AccountState, parent: Order, time: Int64) throws {
        guard parent.request.bracketProfit != nil || parent.request.bracketStop != nil,
              let p = s.positions[parent.request.instrumentID], p.quantity != .zero else { return }
        let oldChildren = s.orders.values.filter { $0.request.parentID == parent.id }
        let exited = try sum(oldChildren.map(\.filled))
        let remainingProtection = min(p.quantity.magnitude, max(.zero, try parent.filled - exited))
        guard remainingProtection > .zero else { return }
        let activeChildren = oldChildren.filter { $0.status.open }
        let group = activeChildren.first?.request.groupID ?? "bracket-\(parent.id)-\(s.sequence)"
        for (suffix, kind, trigger) in [("tp",OrderKind.takeProfit,parent.request.bracketProfit),("sl",.stopMarket,parent.request.bracketStop)] {
            guard let trigger else { continue }
            let id = "\(group)-\(suffix)"
            if var existing = s.orders[id], existing.status.open {
                existing.request.quantity = try existing.filled + remainingProtection; s.orders[id] = existing
            } else if s.orders[id] == nil {
                var request = OrderRequest(instrumentID: p.id, side: p.quantity > .zero ? .sell : .buy, kind: kind, quantity: remainingProtection, trigger: trigger)
                request.requestID = id; request.groupID = group; request.parentID = parent.id; request.reduceOnly = true
                request.leverage = p.leverage; request.marginMode = p.marginMode
                _ = try accept(request, in: &s, time: time)
            }
        }
    }
    private static func risk(_ s: inout AccountState, quote q: Quote, now: Int64) throws {
        let i = try instrument(s, q.instrumentID)
        guard i.asset.derivative, let p = s.positions[i.id], p.quantity != .zero, let mark = q.mark,
              q.quality == .realtime, q.valid, now - q.time <= q.maximumAge else { return }
        let pnl = try (mark - p.average) * p.quantity * i.rules.multiplier
        let maintenance = try mark * p.quantity.magnitude * i.rules.multiplier * i.rules.maintenance
        var collateral = p.margin
        if p.marginMode == .cross {
            collateral = try (s.cash[i.currency] ?? .zero) - sum(s.positions.values.filter { $0.marginMode == .isolated && $0.id != p.id }.map(\.margin))
            for other in s.positions.values where other.id != p.id && other.marginMode == .cross {
                guard let oi = s.instruments.first(where: { $0.id == other.id }), oi.currency == i.currency, let om = s.quotes[other.id]?.mark else { continue }
                collateral = try collateral + (om - other.average) * other.quantity * oi.rules.multiplier
            }
        }
        guard try collateral + pnl <= maintenance else { return }
        // Risk settlement uses a disclosed local mark liquidation model, records any deficit instead of zeroing it.
        for id in s.orders.keys where s.orders[id]!.status.open && s.orders[id]!.request.instrumentID == i.id { s.orders[id]!.status = .cancelled; s.orders[id]!.reserved = .zero }
        let fee = try mark * p.quantity.magnitude * i.rules.multiplier * i.rules.fees.taker
        let delta = try pnl - fee
        s.cash[i.currency] = try (s.cash[i.currency] ?? .zero) + delta
        s.positions[i.id]!.quantity = .zero; s.positions[i.id]!.average = .zero; s.positions[i.id]!.margin = .zero
        s.positions[i.id]!.realized = try p.realized + pnl
        let event = "liquidation-\(i.id)-\(q.sequence)"
        s.post(event: event, currency: i.currency, debit: "cash", credit: "liquidation-clearing", amount: delta, time: now)
        s.audit("liquidation", "\(i.symbol) 本機標記價強平估算；費用 \(fee)，穿倉餘額保留", time: now, id: event)
    }
    private static func utcDay(_ t: Int64, zone: String) -> String {
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(identifier: zone); formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
    }
    public func advance(to target: Int64, wallTarget: Int64? = nil, context: AccountContext) throws -> Int64 {
        try check(context)
        guard state.mode == .offline, let simulation = state.simulation, target >= simulation.time else { throw TradeError.invalid("模擬時間不可倒退或在 A 推進") }
        // A bounded checkpoint transaction. Call repeatedly; a crash resumes from the last committed five-second event.
        return try transaction { s in
            let end = min(target - target % Simulation.step, simulation.time + 300)
            while s.simulation!.time + Simulation.step <= end {
                s.simulation!.time += Simulation.step
                let sim = s.simulation!
                for i in s.instruments.sorted(by: { $0.id < $1.id }) where i.rules.isOpen(at: sim.time) && !i.halted {
                    let q = try Simulation.quote(i, state: sim); s.quotes[i.id] = q
                    try Self.match(&s, quote: q, now: sim.time); try Self.risk(&s, quote: q, now: sim.time)
                }
                if sim.time % 21600 == 0 {
                    s.audit("simulationNews", "模擬事件：產業、政策與流動性因子重新定價；非真實新聞", time: sim.time)
                }
            }
            if let wallTarget { s.lastWallTime = wallTarget - max(0,target-s.simulation!.time) }
            return s.simulation!.time
        }
    }
    public func configureSimulation(speed: Int, paused: Bool, scenario: String, volatility: Double, liquidity: Double, context: AccountContext) throws {
        try check(context)
        guard state.mode == .offline, [1,2,5,10,60,100].contains(speed), volatility >= 0.1, volatility <= 5, liquidity >= 0.1, liquidity <= 10 else { throw TradeError.invalid("模擬參數不合法") }
        try transaction { s in
            s.simulation!.speed = speed; s.simulation!.paused = paused
            if s.simulation!.scenario != scenario || s.simulation!.volatility != volatility || s.simulation!.liquidity != liquidity {
                s.simulation!.changes.append(SimulationChange(time: s.simulation!.time, scenario: scenario, volatility: volatility, liquidity: liquidity))
                s.simulation!.scenario = scenario; s.simulation!.volatility = volatility; s.simulation!.liquidity = liquidity
                s.audit("simulationControl", "未來情境改為 \(scenario)", time: s.simulation!.time)
            }
        }
    }
    public func initializeQuotes(context: AccountContext) throws {
        try check(context)
        guard let sim = state.simulation else { return }
        try transaction { s in for i in s.instruments { s.quotes[i.id] = try Simulation.quote(i, state: sim) } }
    }
    public func updatePreferences(watchlist: Set<String>? = nil, allowEstimated: Bool? = nil, leverageEnabled: Bool? = nil, continueWhileAway: Bool? = nil, context: AccountContext) throws {
        try check(context)
        try transaction { s in
            if let watchlist { s.watchlist = watchlist }; if let allowEstimated { s.allowEstimatedExecution = allowEstimated }
            if let leverageEnabled { s.leverageEnabled = leverageEnabled }; if let continueWhileAway { s.continueWhileAway = continueWhileAway }
        }
    }
    public func recordJournal(_ journal: JournalEntry, context: AccountContext) throws { try check(context); try transaction { $0.journals.removeAll { $0.id == journal.id }; $0.journals.append(journal) } }
    public func addAlert(_ alert: PriceAlert, context: AccountContext) throws { try check(context); try transaction { $0.alerts.append(alert) } }
    public func saveDrawing(_ drawing: Drawing, context: AccountContext) throws { try check(context); try transaction { $0.drawings.removeAll { $0.id == drawing.id }; $0.drawings.append(drawing) } }
    public func removeDrawing(id: String, context: AccountContext) throws { try check(context); try transaction { $0.drawings.removeAll { $0.id == id } } }
    public func addInstrument(_ i: Instrument, context: AccountContext) throws {
        try check(context)
        guard state.mode == .offline, i.id.hasPrefix("SIM:"), !state.instruments.contains(where: { $0.id == i.id }), i.initialPrice > .zero, i.rules.tick > .zero, i.rules.quantityStep > .zero else { throw TradeError.invalid("自訂商品規格不合法或代碼重複") }
        try transaction { s in s.instruments.append(i); if let sim = s.simulation { s.quotes[i.id] = try Simulation.quote(i, state: sim) } }
    }
    public func saveWallClock(_ time: Int64, context: AccountContext) throws { try check(context); try transaction { $0.lastWallTime = time } }
    public func restore(_ restored: AccountState, context: AccountContext) throws {
        try check(context); try AccountRepository.validate(restored, mode: context.mode)
        try repository.save(restored, replacing: true); state = restored
    }
}
