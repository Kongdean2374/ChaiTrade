import Foundation

public actor TradingEngine {
    public nonisolated let context: AccountContext
    private let repository: AccountRepository
    private var state: AccountState
    private let wallClock:(@Sendable ()->Int64)?
    private var maintenance:UUID?
    private var retired=false
    private var simulationDemand:Set<String>?
    public init(context: AccountContext, repository: AccountRepository, initial: AccountState,wallClock:(@Sendable ()->Int64)?=nil) throws {
        guard context.mode == repository.mode else { throw TradeError.wrongAccount }
        try AccountRepository.validate(initial, mode: context.mode)
        self.context = context; self.repository = repository; self.wallClock=wallClock;self.state = try repository.save(initial)
    }
    public func prepareProductExperience(context:AccountContext)throws{
        try check(context)
        guard state.productPreferences?.catalogMigrated != true || (state.mode == .offline && state.simulation?.participantsFrom == nil) else{return}
        try transaction{s in
            if s.productPreferences?.catalogMigrated != true{s=try InstrumentCatalog.migrate(s)}
            if s.mode == .offline,s.simulation?.participantsFrom == nil{
                s.simulation!.baseAlgorithm=s.simulation!.algorithm;s.simulation!.algorithm="factor-wave-3";s.simulation!.participantsFrom=s.simulation!.time+Simulation.step
            }
            if s.mode == .offline,s.simulation?.newsUniverse == nil{
                let universe=s.instruments.filter{$0.identity?.legacy != true}.map(NewsInstrument.init)
                s.simulation!.newsUniverse=universe;s.simulation!.newsWorldID=BackupService.digest(try AccountRepository.encode(universe))
                s.simulation!.newsFrom=((s.simulation!.time/60)+1)*60;s.simulation!.newsAccountingFrom=s.simulation!.time+Simulation.step
            }
            s.audit("catalogMigration","商品目錄增量升級；既有商品身份、部位、規則與歷史保持原值",time:s.simulation?.time ?? Int64(Date().timeIntervalSince1970))
        }
    }
    public func saveMarketBrowsing(_ browsing:MarketBrowsingState,market:MarketDomain,activate:Bool=false,context:AccountContext)throws{
        try check(context)
        guard browsing.search.utf8.count<=512,browsing.recent.count<=30,browsing.recent.allSatisfy({id in state.instruments.contains{$0.id==id && $0.market==market}}),browsing.selectedID.map({id in state.instruments.contains{$0.id==id && $0.market==market}}) ?? true else{throw TradeError.invalid("市場瀏覽狀態與商品不符")}
        try transaction{s in
            if s.productPreferences==nil{s.productPreferences=ProductPreferences()}
            s.productPreferences!.markets[market.rawValue]=browsing
            if activate{s.productPreferences!.activeMarket=market}
        }
    }
    public func saveWatchGroup(_ group:WatchGroup,context:AccountContext)throws{
        try check(context)
        guard !group.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,group.name.utf8.count<=160,group.instrumentIDs.count<=500,Set(group.instrumentIDs).count==group.instrumentIDs.count,group.instrumentIDs.allSatisfy({id in state.instruments.contains{$0.id==id && $0.market==group.market}}) else{throw TradeError.invalid("自選群組名稱或商品不合法")}
        try transaction{s in
            if s.productPreferences==nil{s.productPreferences=ProductPreferences()}
            s.productPreferences!.groups.removeAll{$0.id==group.id};s.productPreferences!.groups.append(group)
            guard s.productPreferences!.groups.count<=30 else{throw TradeError.invalid("最多 30 個自選群組")}
            s.watchlist.formUnion(group.instrumentIDs)
        }
    }
    public func removeWatchGroup(id:String,context:AccountContext)throws{
        try check(context);try transaction{s in
            s.productPreferences?.groups.removeAll{$0.id==id}
            for market in MarketDomain.allCases{if s.productPreferences?.markets[market.rawValue]?.groupID==id{s.productPreferences!.markets[market.rawValue]!.groupID=nil}}
        }
    }
    public func snapshot() -> AccountState { state }
    public func fillPage(limit: Int = 100,before: Int64? = nil,context: AccountContext) throws -> [FillPageRow] {
        try check(context);return try repository.fillPage(limit:limit,before:before)
    }
    public func equityPage(limit:Int=100,before:Int64?=nil,context:AccountContext)throws->[EquityPageRow]{try check(context);return try repository.equityPage(limit:limit,before:before)}
    public nonisolated func fullSnapshot(context:AccountContext)async throws->AccountState{
        guard context==self.context else{throw TradeError.wrongAccount}
        let repository=self.repository
        return try await Task.detached(priority:.utility){guard let full=try repository.readSnapshot() else{throw TradeError.corrupt("帳戶不存在")};return full}.value
    }
    public func beginMaintenance(context:AccountContext)async throws->(UUID,AccountState){
        try check(context);let token=UUID();maintenance=token
        do{return try await (token,fullSnapshot(context:context))}catch{maintenance=nil;throw error}
    }
    public func endMaintenance(token:UUID,context:AccountContext)throws{
        guard context==self.context else{throw TradeError.wrongAccount}
        guard maintenance==nil || maintenance==token else{throw TradeError.invalid("維護工作階段不符")};maintenance=nil
    }
    public func exportCSV(kind:String,time:Int64,context:AccountContext)throws->Data{try check(context);return try repository.csv(kind:kind,time:time)}
    public func performance(from:Int64=0,until:Int64=Int64.max,context:AccountContext)throws->PerformanceReport{try check(context);return try repository.performance(from:from,until:until)}
    public func orderPage(limit:Int=100,before:Int64?=nil,beforeID:String?=nil,search:String="",context:AccountContext)throws->[Order]{try check(context);return try repository.orderPage(limit:limit,before:before,beforeID:beforeID,search:search)}
    private func check(_ context: AccountContext) throws {
        guard context == self.context,!retired else { throw TradeError.wrongAccount }
        guard maintenance==nil else{throw TradeError.unavailable("帳戶正在建立恢復點或還原，暫停新的帳務操作")}
    }
    public func retire(context:AccountContext)throws{try check(context);retired=true}
    @discardableResult private func transaction<T>(catchup:Bool=false,_ body: (inout AccountState) throws -> T) throws -> T {
        var next = state
        let result = try body(&next)
        let kinds:Set<String>=["fill","priceAlert","marginRisk","liquidation","monitoringGap","rejected","catchupComplete"]
        let added=next.events.filter{$0.sequence>state.sequence && kinds.contains($0.kind)}
        if !added.isEmpty{
            if next.inbox==nil{next.inbox=[]}
            let known=Set(next.inbox!.map(\.id))
            next.inbox! += added.map{event in var notice=LocalNotice(accountID:next.accountID,event:event,catchup:catchup || event.kind=="catchupComplete");notice.delivered=next.notificationEnabled != true;return notice}.filter{!known.contains($0.id)}
            // Delivered center entries may leave the hot projection; canonical AuditEvent history remains intact.
            while next.inbox!.count>200,let index=next.inbox!.firstIndex(where:{$0.delivered}){next.inbox!.remove(at:index)}
        }
        state = try repository.save(next)
        return result
    }
    public static func initial(mode: Mode, baseCurrency: String = "TWD", capital: Amount, time: Int64) throws -> AccountState {
        var s = AccountState(mode: mode, baseCurrency: baseCurrency, instruments: try mode == .offline ? Simulation.catalog() : Providers.catalog())
        if mode == .offline{
            s.schema=2
            s.simulation!.algorithm="factor-wave-3";s.simulation!.baseAlgorithm="factor-wave-2";s.simulation!.participantsFrom=s.simulation!.time
            s.simulation!.newsUniverse=s.instruments.map(NewsInstrument.init)
            s.simulation!.newsWorldID=BackupService.digest(try AccountRepository.encode(s.simulation!.newsUniverse!))
            s.simulation!.newsFrom=s.simulation!.time-366*86400;s.simulation!.newsAccountingFrom=s.simulation!.time+Simulation.step
        }
        s.productPreferences=ProductPreferences();s.productPreferences!.catalogMigrated=true
        try adjustCash(&s, currency: baseCurrency, amount: capital, time: s.simulation?.time ?? time, eventID: "initial-capital")
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
            state.instruments.first(where: { $0.id == p.instrumentKey })?.currency == currency ? p.margin : nil
        })
        let payables = try sum((state.lifecycle?.settlements ?? []).filter { $0.currency == currency && $0.completedAt == nil }.map(\.payable))
        return try (state.cash[currency] ?? .zero) - sum(groups.values) - locked - payables
    }
    private static func adjustCash(_ s: inout AccountState, currency: String, amount: Amount, time: Int64, eventID: String) throws {
        guard !s.appliedEvents.contains(eventID) else { return }
        if try amount < .zero && amount.magnitude > available(s, currency: currency) { throw TradeError.insufficient("減資超過可用資金；請先撤單或平倉") }
        s.cash[currency] = try (s.cash[currency] ?? .zero) + amount
        s.netFlows[currency] = try (s.netFlows[currency] ?? .zero) + amount
        s.post(event: eventID, currency: currency, debit: "cash", credit: "external-capital", amount: amount, time: time)
        s.appliedEvents.insert(eventID); s.audit("cashFlow", "虛擬資金調整 \(currency) \(amount)", time: time, id: eventID)
        let value = try Analytics.valuation(s,now:time)
        let baseFlow: Amount
        if currency == s.baseCurrency{baseFlow=amount}
        else if let rate=s.lifecycle?.rates.first(where:{$0.currency==currency && $0.base==s.baseCurrency && $0.usable(at:time)}){baseFlow=try amount*rate.rate}
        else{baseFlow = .zero}
        s.equity.append(EquityPoint(time:time,value:value.complete ? value.total:nil,flow:baseFlow))
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
        guard i.requiresRuleConfirmation != true else{throw TradeError.invalid("請先核對並保存此合約的乘數、到期日與自訂模擬規則，再建立部位")}
        guard i.rules.expiry == nil || time < i.rules.expiry! else { throw TradeError.invalid("合約已到期") }
        let board=i.board(for:r)
        if let board{
            let lot=try Amount(i.identity?.boardLot ?? 1000)
            if board == .regular{guard try r.quantity.isMultiple(of:lot) else{throw TradeError.invalid("整股數量須為每張交易單位的整數倍；零股請選盤中零股")}}
            else{guard r.quantity > .zero,r.quantity<lot,try r.quantity.isMultiple(of:.one) else{throw TradeError.invalid("盤中零股數量須為1至999股")}
                guard r.kind == .limit,r.timeInForce == .DAY,!r.postOnly else{throw TradeError.invalid("盤中零股採當日有效限價委託；市價、跨日與立即成交指令不適用")}
            }
        }
        guard r.quantity > .zero, try r.quantity.isMultiple(of: i.rules.quantityStep) else { throw TradeError.invalid("數量不符合商品級距") }
        for p in [r.price, r.trigger].compactMap({$0}) {
            guard p > .zero, try p.isMultiple(of: i.rules.tick(at:p)) else { throw TradeError.invalid("價格不符合最小跳動") }
        }
        if [.limit, .stopLimit].contains(r.kind) && r.price == nil { throw TradeError.invalid("請輸入限價") }
        if r.kind.conditional && r.kind != .trailing && r.trigger == nil { throw TradeError.invalid("請輸入觸發價") }
        if r.kind == .trailing && (r.trailingDistance ?? .zero) <= .zero { throw TradeError.invalid("移動停損距離必須大於零") }
        if r.trailingPercent && (r.trailingDistance ?? .zero) >= .one { throw TradeError.invalid("百分比距離需小於 1（例如 0.05）") }
        if r.timeInForce == .GTD && (r.expiresAt ?? 0) <= time { throw TradeError.invalid("GTD 到期時間必須在未來") }
        if r.postOnly && r.kind != .limit { throw TradeError.invalid("Post-only 只適用限價委託") }
        guard r.leverage >= 1, r.leverage <= i.rules.maxLeverage else { throw TradeError.invalid("槓桿超出規則上限") }
        if i.asset.derivative,s.positionMode == .hedge{guard let side=r.positionSide else{throw TradeError.invalid("雙向模式需指定多倉或空倉")};let opens=(side == .long && r.side == .buy) || (side == .short && r.side == .sell);if !opens && !r.reduceOnly{throw TradeError.invalid("雙向平倉需啟用僅減倉，避免意外反向建立部位")}}
        let positionKey=s.positionKey(for:r,instrument:i)
        let position = s.positions[positionKey]?.quantity ?? .zero
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
        let q = s.quotes[i.quoteKey(board:board)]
        let ref = r.price ?? q?.last ?? i.initialPrice
        guard ref > .zero else { throw TradeError.unavailable("缺少有效價格，請先更新行情；不使用合成報價估算保留資金") }
        let protection = try Amount("0.05")
        let protected = r.kind == .limit || r.kind == .stopLimit ? ref : try ref * (.one + protection)
        let notional = try protected * r.quantity * i.rules.multiplier
        guard notional >= i.rules.minimumNotional else { throw TradeError.invalid("未達最小名目金額") }
        let fee = try i.rules.fees.cumulative(notional: notional, maker: false)
        let reducing = position != .zero && position.sign != r.side.sign.sign
        let openingQty = reducing ? max(.zero, try r.quantity - position.magnitude) : r.quantity
        if i.asset.derivative && openingQty > .zero && !s.leverageEnabled { throw TradeError.invalid("請先於設定確認啟用合約風險功能；既有部位仍可平倉") }
        let reservation: Amount
        if i.asset.derivative {
            let resulting=try (reducing ? max(.zero,r.quantity-position.magnitude):position.magnitude+r.quantity)*protected*i.rules.multiplier
            if openingQty > .zero,let tier=i.rules.tier(at:resulting),r.leverage>tier.maxLeverage{throw TradeError.invalid("委託後持倉超過此名目金額級距的槓桿上限")}
            let existingMargin=s.positions[positionKey]?.margin ?? .zero
            reservation=openingQty == .zero && reducing ? .zero:try max(.zero,i.rules.initialMargin(notional:resulting,leverage:r.leverage)-existingMargin)+fee
        }
        else if r.side == .buy { reservation = try notional + fee }
        else { reservation = .zero }
        var groupCredit: Amount = .zero
        if let group = r.groupID {
            groupCredit = s.orders.values.filter { $0.status.open && $0.request.groupID == group && $0.id != excluding }.map(\.reserved).max() ?? .zero
        }
        guard try (i.asset.derivative && reducing && openingQty == .zero) || reservation <= available(s, currency: i.currency, excluding: excluding) + groupCredit else { throw TradeError.insufficient("\(i.currency) 可用資金不足（含費用及價格保護）") }
        if r.postOnly, let q, Self.fresh(q,now:time) {
            let cross = r.side == .buy ? (q.asks.first.map { $0.price <= ref } ?? false) : (q.bids.first.map { $0.price >= ref } ?? false)
            if cross { throw TradeError.invalid("Post-only 會立即吃單，已拒絕") }
        }
        return (i, ref, reservation)
    }
    @discardableResult private static func accept(_ r: OrderRequest, in s: inout AccountState, time: Int64) throws -> String {
        if let existing = s.orders.values.first(where: { $0.request.requestID == r.requestID }) { return existing.id }
        let (i, ref, reservation) = try validate(r, in: s, time: time)
        var r=r;r.board=i.board(for:r)
        let id = r.requestID
        var order=Order(id: id, accountID: s.accountID, request: r, reserved: reservation, referencePrice: ref, createdAt: time, updatedAt: time, ruleVersion: i.rules.version)
        order.postOnlyChecked=s.quotes[i.quoteKey(board:r.board)].map{Self.fresh($0,now:time)} ?? false
        s.orders[id]=order
        s.audit("accepted", "\(i.symbol) \(r.kind.label) \(r.quantity)", time: time)
        return id
    }
    @discardableResult public func submit(_ request: OrderRequest, time: Int64, context: AccountContext) throws -> String {
        try check(context)
        if let existing=try repository.order(id:request.requestID){return existing.id}
        let eventTime=state.simulation?.time ?? wallClock?() ?? time
        return try transaction { s in
            let id = try Self.accept(request, in: &s, time: eventTime)
            if let order=s.orders[id],let i=s.instruments.first(where:{$0.id==request.instrumentID}),let q = s.quotes[i.quoteKey(board:i.board(for:order.request))] { try Self.match(&s, quote: q, now: eventTime) }
            try Self.recordEquity(&s,time:eventTime)
            return id
        }
    }
    public func submitOCO(_ first: OrderRequest, _ second: OrderRequest, time: Int64, context: AccountContext) throws {
        try check(context)
        let time=state.simulation?.time ?? wallClock?() ?? time
        let a=try repository.order(id:first.requestID),b=try repository.order(id:second.requestID)
        if a != nil && b != nil{return}
        guard a == nil && b == nil else{throw TradeError.invalid("OCO 識別已部分使用，請重新建立整組")}
        guard first.instrumentID == second.instrumentID, first.side == second.side, first.quantity == second.quantity,first.positionSide==second.positionSide else { throw TradeError.invalid("OCO 需同商品、同方向、同數量") }
        try transaction { s in
            var a = first, b = second; let group = "oco-\(first.requestID)"
            a.groupID = group; b.groupID = group
            _ = try Self.accept(a, in: &s, time: time); _ = try Self.accept(b, in: &s, time: time)
            if let i=s.instruments.first(where:{$0.id==a.instrumentID}),let q = s.quotes[i.quoteKey(board:i.board(for:a))] { try Self.match(&s, quote: q, now: time) }
            try Self.recordEquity(&s,time:time)
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
    public func amend(id: String, quantity: Amount, price: Amount?, trigger: Amount? = nil, time: Int64, context: AccountContext) throws {
        try check(context)
        let time=state.simulation?.time ?? wallClock?() ?? time
        try transaction { s in
            guard var o = s.orders[id], o.status.open, quantity > o.filled else { throw TradeError.invalid("委託已完成或新總量不大於成交量") }
            var r = o.request; r.quantity = try quantity - o.filled; r.price = price
            if let trigger { r.trigger = trigger }
            let (i, ref, reservation) = try Self.validate(r, in: s, time: time, excluding: id)
            o.request.quantity = quantity; o.request.price = price; o.referencePrice = ref; o.reserved = reservation
            o.request.trigger = r.trigger
            o.postOnlyChecked=s.quotes[i.quoteKey(board:i.board(for:r))].map{Self.fresh($0,now:time)} ?? false
            o.revision += 1; o.updatedAt = time; s.orders[id] = o
            s.audit("amended", "改單第 \(o.revision) 次，重新計算保留", time: time)
            if let q = s.quotes[i.quoteKey(board:i.board(for:r))] { try Self.match(&s, quote: q, now: time) }
            try Self.recordEquity(&s,time:time)
        }
    }
    public func ingest(_ quote: Quote, now: Int64, context: AccountContext) throws {
        try check(context)
        let now=wallClock?() ?? now
        guard state.mode == .online else { throw TradeError.invalid("B 模式拒絕外部行情") }
        guard quote.last > .zero else{throw TradeError.unavailable("來源沒有有效參考價格，不用零覆蓋最後已知報價")}
        var quote=quote
        if quote.mark == nil,state.useReferenceRiskPrice == true,try Self.instrument(state,quote.instrumentID).asset.derivative {
            quote.mark=quote.last;quote.coverage += "；使用者啟用自訂參考風險價模型（非交易所標記價）"
        }
        try transaction { s in
            try Self.settleDue(&s, now:now)
            if let old=s.quotes[quote.storageKey],Self.fresh(old,now:now),old.source.hasPrefix("Coinbase Exchange WS "),quote.source==ProviderID.coinbase.label{
                // REST supplements list statistics while a healthy stream owns the executable book.
                // It must not reset already consumed WS liquidity or replace newer stream prices.
                if let summary=quote.summary,summary.reference != nil || summary.volume != nil{var merged=old;merged.summary=summary;s.quotes[quote.storageKey]=merged}
                return
            }
            if let old=s.quotes[quote.storageKey],old.source==quote.source{
                if old.sequence>quote.sequence{return}
                if old.sequence==quote.sequence && old.valid && old.quality == .realtime && quote.valid && quote.quality == .realtime && old.grade==quote.grade && old.sourceIssue==quote.sourceIssue{
                    if let summary=quote.summary{var merged=old;merged.summary=summary;s.quotes[quote.storageKey]=merged}
                    return
                }
            }
            s.quotes[quote.storageKey] = quote
            try Self.match(&s, quote: quote, now: now)
            try Self.risk(&s, quote: quote, now: now)
            try Self.recordEquity(&s,time:now)
        }
    }
    public func markMonitoringGap(instrumentID: String,time: Int64,expectedSourcePrefix:String?=nil,context: AccountContext) throws {
        try check(context)
        guard let previous=state.quotes[instrumentID],previous.valid || previous.quality != .stale else{return}
        if let expectedSourcePrefix,state.quotes[instrumentID]?.source.hasPrefix(expectedSourcePrefix) != true{return}
        try transaction {s in
            if var quote=s.quotes[instrumentID]{quote.valid=false;quote.quality = .stale;s.quotes[instrumentID]=quote}
            for id in s.orders.keys where s.orders[id]!.status.open && s.orders[id]!.request.instrumentID==instrumentID{s.orders[id]!.suspension="行情監控曾中斷，等待新快照；不回填缺口成交"}
            s.audit("monitoringGap","\(instrumentID) 監控中斷；沒有背景成交保證",time:time)
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
    private static func fresh(_ q: Quote,now: Int64) -> Bool {
        q.quality == .realtime && q.valid && (q.sourceIssue.map{[MarketIssueKind.ready,.referenceOnly].contains($0)} ?? true) && now >= q.time-5 && now-q.time <= q.maximumAge && now-q.receivedAt <= q.maximumAge
    }
    private static func match(_ s: inout AccountState, quote q: Quote, now: Int64) throws {
        let i = try instrument(s, q.instrumentID)
        let fresh = Self.fresh(q,now:now)
        let bookValid = q.last > .zero && q.bids.allSatisfy { $0.price > .zero && $0.quantity >= .zero } && q.asks.allSatisfy { $0.price > .zero && $0.quantity >= .zero } && (q.bids.first == nil || q.asks.first == nil || q.bids[0].price < q.asks[0].price)
        let gradeOK = q.grade == .E1 || q.grade == .E2 || (q.grade == .E3 && s.allowEstimatedExecution)
        let ordered = s.orders.values.filter { $0.status.open && $0.request.instrumentID == i.id && (!i.usesTaiwanBoards || i.board(for:$0.request)==(q.board ?? .regular)) }.sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }.map(\.id)
        for id in ordered {
            guard var o = s.orders[id], o.status.open else { continue }
            let startingFilled = o.filled
            let dayExpired = o.request.timeInForce == .DAY && utcDay(o.createdAt, zone: i.rules.timeZone) != utcDay(now, zone: i.rules.timeZone)
            if dayExpired || (o.request.expiresAt.map { now >= $0 } ?? false) {
                o.status = .expired; o.reserved = .zero; s.orders[id] = o; s.audit("expired", id, time: now); continue
            }
            let riskPriceValid = !i.asset.derivative || (q.mark ?? .zero) > .zero
            guard fresh && bookValid && gradeOK && i.boardIsOpen(q.board,at: q.time) && !i.halted && riskPriceValid else {
                o.suspension = !fresh ? "行情過期或非即時，暫停成交" : !bookValid ? "委託簿無效" : !gradeOK ? "資料能力不足；E3 估算須明確啟用" : !riskPriceValid ? "缺少合約風險價；需有效標記價或明確啟用自訂參考價模型" : "非交易時段或停牌"
                s.orders[id] = o; continue
            }
            o.suspension = nil
            if o.request.postOnly && o.postOnlyChecked != true {
                let price=o.request.price!
                let crosses=o.request.side == .buy ? (q.asks.first.map{$0.price<=price} ?? false):(q.bids.first.map{$0.price>=price} ?? false)
                if crosses{o.status = .cancelled;o.reserved = .zero;o.suspension="Post-only 首次取得有效報價時會吃單，已取消";s.orders[id]=o;s.audit("postOnlyCancelled",id,time:now);continue}
                o.postOnlyChecked=true
            }
            let wasTriggered = o.triggered
            guard try trigger(&o, q) else { s.orders[id] = o; continue }
            if !wasTriggered && o.triggered && o.request.kind != .stopLimit { o.referencePrice = q.last }
            let key = "\(q.storageKey)|\(o.request.side.rawValue)"
            let stamp = "\(key)|\(q.source)|\(q.sequence)"
            var levels: [Level]
            let participantBook=s.mode == .offline && (o.request.side == .buy ? q.asks:q.bids).contains{$0.liquidityID != nil}
            if participantBook{
                levels=try (o.request.side == .buy ? q.asks:q.bids).map{level in var value=level;value.quantity=max(.zero,try value.quantity-(s.participantUsage?[level.liquidityID!]?.quantity ?? .zero));return value}
            }else if let saved = s.consumed[stamp] { levels = saved }
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
                let position = s.positions[s.positionKey(for:o.request,instrument:i)]?.quantity ?? .zero
                if position == .zero || position.sign == o.request.side.sign.sign { o.status = .cancelled; o.reserved = .zero; s.orders[id] = o; continue }
                needed = min(needed, position.magnitude)
            }
            let limited = o.request.kind == .limit || o.request.kind == .stopLimit
            let guardPrice = limited ? o.request.price! : (o.request.side == .buy ? try o.referencePrice * Amount("1.05") : try o.referencePrice * Amount("0.95"))
            var plan: [(Int,Amount)] = []
            for n in levels.indices where needed > .zero {
                let p = levels[n].price
                guard o.request.side == .buy ? p <= guardPrice : p >= guardPrice else { continue }
                var quantity = min(needed, levels[n].quantity)
                if i.usesTaiwanBoards,q.board != .oddLot{let lot=try Amount(i.identity?.boardLot ?? 1000);quantity=try (quantity/lot).rounded(0,.down)*lot}
                if quantity > .zero { plan.append((n,quantity)); needed = try needed - quantity }
            }
            if o.request.timeInForce == .FOK && needed > .zero { plan = [] }
            for (n, quantity) in plan {
                // Funds and fees are checked again at execution; a gap cannot consume unbounded cash.
                let before = s
                do {
                    try execute(&s, order: &o, quantity: quantity, price: levels[n].price, instrument: i, quote: q, now: now,liquidity:levels[n])
                    if let pool=levels[n].liquidityID,let expires=levels[n].liquidityExpiresAt{
                        if s.participantUsage==nil{s.participantUsage=[:]}
                        s.participantUsage![pool]=ParticipantUsage(quantity:try (s.participantUsage![pool]?.quantity ?? .zero)+quantity,expiresAt:expires)
                    }
                    levels[n].quantity = try levels[n].quantity - quantity
                } catch TradeError.insufficient(let reason) { s = before; o.suspension = reason; break }
            }
            if (try o.remaining) == .zero { o.status = .filled; o.reserved = .zero }
            else if o.filled > .zero { o.status = .partiallyFilled }
            if [.IOC,.FOK].contains(o.request.timeInForce) && o.status.open { o.status = .cancelled; o.reserved = .zero }
            if !limited && !o.request.kind.conditional && o.status.open { o.status = .cancelled; o.reserved = .zero }
            s.orders[id] = o;if !participantBook{s.consumed[stamp] = levels}
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
        for idx in s.alerts.indices where fresh && q.last > .zero && s.alerts[idx].instrumentID == i.id && s.alerts[idx].firedAt == nil && (!i.usesTaiwanBoards || (s.alerts[idx].board ?? .regular)==(q.board ?? .regular)) {
            let a = s.alerts[idx]
            if a.above ? q.last >= a.price : q.last <= a.price { s.alerts[idx].firedAt = now;let detail=a.percentage.map{"（相對固定基準 \(a.baseline ?? .zero)，\(a.above ? "上漲":"下跌") \($0)%）"} ?? "";s.audit("priceAlert", "\(i.symbol) 到價 \(a.price)\(detail)", time: now, id: "alert-\(a.id)",instrumentID:i.id) }
        }
    }
    private static func execute(_ s: inout AccountState, order o: inout Order, quantity: Amount, price: Amount, instrument i: Instrument, quote q: Quote, now: Int64,liquidity:Level?=nil) throws {
        let notional = try quantity * price * i.rules.multiplier
        let totalNotional = try o.cumulativeNotional + notional
        let cumulativeFee = try i.rules.fees.cumulative(notional: totalNotional, maker: o.request.postOnly)
        let fee = try max(.zero, cumulativeFee - o.fees)
        let tax = o.request.side == .sell ? try notional * i.rules.fees.sellTax : .zero
        let positionKey=s.positionKey(for:o.request,instrument:i)
        var p = s.positions[positionKey] ?? Position(id:positionKey)
        if positionKey != i.id{p.instrumentID=i.id;p.side=o.request.positionSide}
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
        let openingQuantity=try quantity-closing
        if openingQuantity > .zero {p.leverage = o.request.leverage; p.marginMode = o.request.marginMode}
        if old == .zero { p.openedAt = now }
        if i.asset.derivative {
            let released = old == .zero ? .zero : try oldMargin * closing / old.magnitude
            let opening = try quantity - closing
            let added=try i.rules.initialMargin(notional:opening*price*i.rules.multiplier,leverage:o.request.leverage)
            p.margin=try oldMargin-released+added
            if opening > .zero{p.margin=max(p.margin,try i.rules.initialMargin(notional:next.magnitude*price*i.rules.multiplier,leverage:o.request.leverage))}
        }
        let delayedSettlement = !i.asset.derivative && (i.rules.settlementBusinessDays ?? 0) > 0
        let tradeCash = i.asset.derivative ? realized : delayedSettlement ? .zero : (o.request.side == .buy ? notional.negated : notional)
        let cashDelta = try tradeCash - fee - tax
        let newCash = try (s.cash[i.currency] ?? .zero) + cashDelta
        let otherLocks = try (s.cash[i.currency] ?? .zero) - available(s, currency: i.currency, excluding: o.id) - oldMargin
        let newPayable = delayedSettlement && o.request.side == .buy ? notional:.zero
        guard try (i.asset.derivative && closing > .zero && openingQuantity == .zero) || newCash >= otherLocks + p.margin + newPayable else { throw TradeError.insufficient("成交時可用資金不足，保留原帳務") }
        s.cash[i.currency] = newCash; s.positions[positionKey] = p
        if p.quantity == .zero{s.marginWarningLevels?.removeValue(forKey:positionKey)}
        o.filled = try o.filled + quantity; o.cumulativeNotional = totalNotional; o.fees = cumulativeFee
        o.updatedAt = now
        let rem = try o.remaining
        if rem == .zero {o.reserved = .zero}
        else {
            let ceiling=try ([.limit,.stopLimit].contains(o.request.kind) ? (o.request.price ?? o.referencePrice):o.referencePrice*Amount("1.05"))
            let remainingNotional=try rem*ceiling*i.rules.multiplier
            let feeRemaining=try max(.zero,i.rules.fees.cumulative(notional:o.cumulativeNotional+remainingNotional,maker:o.request.postOnly)-o.fees)
            if i.asset.derivative {
                let stillClosing=p.quantity.sign != 0 && p.quantity.sign != o.request.side.sign.sign ? min(rem,p.quantity.magnitude):.zero
                let toOpen=try rem-stillClosing
                o.reserved = toOpen == .zero ? .zero:try i.rules.initialMargin(notional:toOpen*ceiling*i.rules.multiplier,leverage:o.request.leverage)+feeRemaining
            }else{o.reserved = o.request.side == .buy ? try remainingNotional+feeRemaining:.zero}
        }
        let fillID = "fill-\(o.id)-\(s.sequence + 1)"
        var fill = Fill(id: fillID, accountID: s.accountID, orderID: o.id, instrumentID: i.id, side: o.request.side, quantity: quantity, price: price, fee: fee, tax: tax, time: now, quoteTime: q.time, source: q.source, grade: q.grade, estimatedExecution: q.grade == .E3, liquidityEventID: "\(q.source)-\(q.board?.rawValue ?? "default")-\(q.sequence)", ruleVersion: o.ruleVersion, realized: realized)
        fill.causalEventIDs=q.causalEventIDs;fill.multiplier=i.rules.multiplier;fill.notional=notional;fill.positionKey=positionKey;fill.timelineSequence=s.sequence+1
        if let pool=liquidity?.liquidityID,let sim=s.simulation,let enabled=sim.participantsFrom,now>=enabled{
            fill.liquidityEventID=pool;fill.modelVersion=SimulationParticipants.model+"-impact-1"
            let impact=try SimulationParticipants.impact(instrument:i,quantity:quantity,side:o.request.side,quote:q,time:now)
            fill.simulationImpact=impact;fill.generatedEventIDs=[impact.groupID]
            s.simulation!.impactGroups=try SimulationParticipants.grouped((s.simulation!.impactGroups ?? [])+[impact])
        }
        s.fills.append(fill)
        if delayedSettlement {
            if s.lifecycle == nil { s.lifecycle = LifecycleState() }
            let due = try MarketCalendar.settlementDate(tradeTime:now,businessDays:i.rules.settlementBusinessDays!,rules:i.rules)
            s.lifecycle!.settlements.append(SettlementEvent(id:"settle-\(fillID)",currency:i.currency,due:due,receivable:o.request.side == .sell ? notional:.zero,payable:newPayable))
            s.post(event:fillID,currency:i.currency,debit:o.request.side == .buy ? "spot-clearing":"receivable",credit:o.request.side == .buy ? "payable":"spot-clearing",amount:notional,time:now)
        } else {
            s.post(event: fillID, currency: i.currency, debit: "cash", credit: i.asset.derivative ? "derivative-clearing" : "spot-clearing", amount: tradeCash, time: now)
        }
        s.post(event: fillID, currency: i.currency, debit: "fees", credit: "cash", amount: try fee + tax, time: now)
        s.audit("fill", "\(i.symbol) \(o.request.side.label) \(quantity) @ \(price)；\(q.grade.rawValue)", time: now, id: fillID,instrumentID:i.id,orderID:o.id)
    }
    private static func protect(_ s: inout AccountState, parent: Order, time: Int64) throws {
        guard parent.request.bracketProfit != nil || parent.request.bracketStop != nil,
              let i=s.instruments.first(where:{$0.id==parent.request.instrumentID}),let p = s.positions[s.positionKey(for:parent.request,instrument:i)], p.quantity != .zero else { return }
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
                var request = OrderRequest(instrumentID: p.instrumentKey, side: p.quantity > .zero ? .sell : .buy, kind: kind, quantity: remainingProtection, trigger: trigger)
                request.requestID = id; request.groupID = group; request.parentID = parent.id; request.reduceOnly = true
                request.leverage = p.leverage; request.marginMode = p.marginMode;request.positionSide=p.side
                _ = try accept(request, in: &s, time: time)
            }
        }
    }
    private static func risk(_ s: inout AccountState, quote q: Quote, now: Int64) throws {
        let i = try instrument(s, q.instrumentID)
        guard i.asset.derivative else{return}
        for key in s.heldPositions(i.id).map(\.id){try riskPosition(&s,key:key,quote:q,now:now)}
    }
    private static func riskPosition(_ s:inout AccountState,key:String,quote q:Quote,now:Int64)throws{
        let i=try instrument(s,q.instrumentID)
        guard let p = s.positions[key], p.quantity != .zero, let mark = q.mark,
              q.quality == .realtime, q.valid, now - q.time <= q.maximumAge else { return }
        guard let evaluation=try? ContractRisk.evaluate(s,positionKey:p.id,now:now) else{return}
        let maintenance=evaluation.maintenanceAndClosingFee,previous=s.marginWarningLevels?[key] ?? 0
        let level=evaluation.equity<=maintenance ? 2:evaluation.equity <= (try maintenance*Amount(2)) ? 1:0
        if s.marginWarningLevels==nil{s.marginWarningLevels=[:]}
        if level>previous{
            s.audit("marginRisk","\(i.symbol) \(p.side?.label ?? "淨倉") \(level==2 ? "已達本機強平條件":"保證金高風險")；權益 \(evaluation.equity)，維持保證金及預估平倉費 \(maintenance) \(i.currency)。請檢查部位或調整保證金。",time:now,instrumentID:i.id)
            s.marginWarningLevels![key]=level
        }else if level==0,evaluation.equity > (try maintenance*Amount("2.5")){s.marginWarningLevels!.removeValue(forKey:key)}
        guard evaluation.equity<=evaluation.maintenanceAndClosingFee else{return}
        let event="liquidation-\(p.id)-\(q.sequence)"
        guard !s.appliedEvents.contains(event) else{return}
        for id in s.orders.keys where s.orders[id]!.status.open && s.orders[id]!.request.instrumentID==i.id && s.positionKey(for:s.orders[id]!.request,instrument:i)==p.id{s.orders[id]!.status = .cancelled;s.orders[id]!.reserved = .zero}
        var request=OrderRequest(instrumentID:i.id,side:p.quantity > .zero ? .sell:.buy,kind:.market,quantity:p.quantity.magnitude)
        request.requestID=event;request.reduceOnly=true;request.positionSide=p.side;request.leverage=p.leverage;request.marginMode=p.marginMode
        // This is a disclosed local risk settlement, not an invented exchange book or trade.
        var order=Order(id:event,accountID:s.accountID,request:request,referencePrice:mark,createdAt:now,updatedAt:now,ruleVersion:i.rules.version)
        var riskQuote=q;riskQuote.grade = .E3;riskQuote.source += "；本機標記價強平模型";riskQuote.bids=[];riskQuote.asks=[]
        try execute(&s,order:&order,quantity:p.quantity.magnitude,price:mark,instrument:i,quote:riskQuote,now:now)
        order.status = .filled;s.orders[event]=order
        if let last=s.fills.indices.last{s.fills[last].modelVersion="mark-liquidation-2"}
        s.marginWarningLevels!.removeValue(forKey:key)
        s.appliedEvents.insert(event);s.audit("liquidation","\(i.symbol) \(p.side?.label ?? "淨倉") 本機標記價強平估算；費用 \(order.fees)，穿倉餘額保留",time:now,id:event,instrumentID:i.id,orderID:event)
    }

    private static func utcDay(_ t: Int64, zone: String) -> String {
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(identifier: zone); formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
    }
    public func advance(to target: Int64, wallTarget: Int64? = nil,catchup:Bool=false, context: AccountContext) throws -> Int64 {
        try check(context)
        guard state.mode == .offline, let simulation = state.simulation, target >= simulation.time else { throw TradeError.invalid("模擬時間不可倒退或在 A 推進") }
        // A bounded checkpoint transaction. Call repeatedly; a crash resumes from the last committed five-second event.
        return try transaction(catchup:catchup) { s in
            let end = min(target - target % Simulation.step, simulation.time + 300)
            while s.simulation!.time + Simulation.step <= end {
                s.simulation!.time += Simulation.step
                let financialSequence=s.sequence
                let sim = s.simulation!
                if sim.time%60==0{try Self.applySimulationNews(&s,at:sim.time)}
                try Self.settleDue(&s,now:sim.time)
                try Self.scheduledOfflineLifecycle(&s,previous:sim.time-Simulation.step,now:sim.time)
                s.participantUsage=s.participantUsage?.filter{$0.value.expiresAt>sim.time}
                let expired=(s.simulation!.impactGroups ?? []).filter{$0.endsAt+65<sim.time}
                if let last=expired.map(\.endsAt).max(){s.simulation!.impactArchiveCutoff=max(s.simulation!.impactArchiveCutoff ?? 0,last)}
                s.simulation!.impactGroups=s.simulation!.impactGroups?.filter{$0.endsAt+65>=sim.time}
                let currentSimulation=s.simulation!
                for i in s.instruments.sorted(by: { $0.id < $1.id }) where i.rules.isOpen(at: sim.time) && !i.halted {
                    // Every financial five-second step still runs. Invisible intermediate UI books need not
                    // be rebuilt during catchup when there is no position or live/conditional order.
                    // Each committed checkpoint ends with the complete demanded book, including pauses.
                    let fullBook=(!catchup || sim.time==end) && (self.simulationDemand.map{$0.contains(i.id)} ?? true) || s.heldPositions(i.id).contains{$0.quantity != .zero} || s.orders.values.contains{$0.status.open && $0.request.instrumentID==i.id}
                    let q = try Simulation.quote(i, state: currentSimulation,includeBook:fullBook); s.quotes[i.id] = q
                    try Self.match(&s, quote: q, now: sim.time); try Self.risk(&s, quote: q, now: sim.time)
                    if i.usesTaiwanBoards{let odd=try Simulation.quote(i,state:currentSimulation,board:.oddLot,includeBook:fullBook);s.quotes[odd.storageKey]=odd;try Self.match(&s,quote:odd,now:sim.time)}
                }
                if sim.time % 60 == 0 || s.sequence>financialSequence { try Self.recordEquity(&s,time:sim.time) }
            }
            if let wallTarget { s.lastWallTime = wallTarget - max(0,target-s.simulation!.time) }
            return s.simulation!.time
        }
    }
    private static func applySimulationNews(_ s:inout AccountState,at time:Int64)throws{
        guard let sim=s.simulation,let accountingFrom=sim.newsAccountingFrom,time>=accountingFrom else{return}
        for bucket in [time/SimulationNews.period-1,time/SimulationNews.period]{
            guard let story=SimulationNews.story(bucket:bucket,state:sim),story.publishedAt>=accountingFrom else{continue}
            let publication="published-"+story.id
            if story.publishedAt<=time,!s.appliedEvents.contains(publication){
                s.appliedEvents.insert(publication);s.audit("simulationNews",story.title+"；模擬情境，非真實新聞",time:story.publishedAt,id:publication)
                if let id=story.instrumentIDs.first,story.kind=="dividend"{
                    let action=CorporateAction(id:story.id,instrumentID:id,kind:.dividend,time:story.publishedAt,cashPerUnit:try Amount("0.25"),paymentTime:story.endsAt,source:"B 模擬新聞情境 "+story.id)
                    try applyCorporateAction(action,to:&s)
                }
                if let id=story.instrumentIDs.first,story.kind=="split"{
                    let action=CorporateAction(id:story.id,instrumentID:id,kind:.split,time:story.publishedAt,ratio:try Amount("2"),source:"B 模擬新聞情境 "+story.id)
                    try applyCorporateAction(action,to:&s)
                }
            }
        }
    }
    public func configureSimulation(speed: Int, paused: Bool, scenario: String, volatility: Double, liquidity: Double, context: AccountContext) throws {
        try check(context)
        guard state.mode == .offline, [1,2,5,10,60,100].contains(speed), volatility >= 0.1, volatility <= 5, liquidity >= 0.1, liquidity <= 10,["多頭","空頭","盤整","恐慌","復甦"].contains(scenario) else { throw TradeError.invalid("模擬參數不合法") }
        try transaction { s in
            s.simulation!.speed = speed; s.simulation!.paused = paused
            if s.simulation!.scenario != scenario || s.simulation!.volatility != volatility || s.simulation!.liquidity != liquidity {
                s.simulation!.changes.append(SimulationChange(time: s.simulation!.time+Simulation.step, scenario: scenario, volatility: volatility, liquidity: liquidity))
                s.simulation!.scenario = scenario; s.simulation!.volatility = volatility; s.simulation!.liquidity = liquidity
                s.audit("simulationControl", "未來情境改為 \(scenario)", time: s.simulation!.time)
            }
        }
    }
    public func initializeQuotes(fullBookIDs:Set<String>?=nil,context: AccountContext) throws {
        try check(context)
        guard let sim = state.simulation else { return }
        simulationDemand=fullBookIDs
        var histories:[String:SimulationState]=[:]
        for i in state.instruments{histories[i.id]=try simulationSnapshot(instrumentID:i.id,from:max(0,sim.time-10*366*86400),context:context)}
        try transaction { s in for i in s.instruments { let history=histories[i.id]!,fullBook=(fullBookIDs.map{$0.contains(i.id)} ?? true) || s.heldPositions(i.id).contains{$0.quantity != .zero} || s.orders.values.contains{$0.status.open && $0.request.instrumentID==i.id};s.quotes[i.id] = try Simulation.quote(i, state: history,includeBook:fullBook);if i.usesTaiwanBoards{let odd=try Simulation.quote(i,state:history,board:.oddLot,includeBook:fullBook);s.quotes[odd.storageKey]=odd} } }
    }
    public func setSimulationDemand(_ ids:Set<String>,context:AccountContext)throws{
        try check(context);guard state.mode == .offline else{throw TradeError.wrongAccount}
        guard simulationDemand != ids else{return};simulationDemand=ids
        var quotes:[Quote]=[]
        for i in state.instruments where ids.contains(i.id){
            let history=try simulationSnapshot(instrumentID:i.id,from:max(0,state.simulation!.time-10*366*86400),context:context)
            quotes.append(try Simulation.quote(i,state:history))
            if i.usesTaiwanBoards{quotes.append(try Simulation.quote(i,state:history,board:.oddLot))}
        }
        try transaction{s in for quote in quotes{s.quotes[quote.storageKey]=quote}}
    }
    public func simulationSnapshot(instrumentID:String,from:Int64,context:AccountContext)throws->SimulationState{
        try check(context)
        guard var simulation=state.simulation,state.instruments.contains(where:{$0.id==instrumentID}) else{throw TradeError.invalid("沒有此離線商品")}
        if let cutoff=simulation.impactArchiveCutoff,from<cutoff{
            simulation.impactGroups=try repository.simulationImpacts(instrumentID:instrumentID,from:max(0,from-305),through:simulation.time)
            simulation.impactArchiveCutoff=max(0,from)
        }
        return simulation
    }
    public func simulationCandles(instrumentID:String,interval:Int64,count:Int,before:Int64?=nil,context:AccountContext)async throws->[Candle]{
        let instrument=try Self.instrument(state,instrumentID)
        let simulation=try simulationSnapshot(instrumentID:instrumentID,from:max(0,(before ?? state.simulation?.time ?? 0)-10*366*86400),context:context)
        return try await Task.detached(priority:.userInitiated){try Simulation.candles(instrument,state:simulation,interval:interval,count:count,before:before)}.value
    }
    public func setPositionMode(_ mode:PositionMode,context:AccountContext)throws{
        try check(context)
        guard !state.positions.values.contains(where:{p in p.quantity != .zero && state.instruments.first{$0.id==p.instrumentKey}?.asset.derivative==true}),!state.orders.values.contains(where:{o in o.status.open && state.instruments.first{$0.id==o.request.instrumentID}?.asset.derivative==true}) else{throw TradeError.invalid("切換持倉模式前請先結束所有合約持倉與未結委託；不會自動合併或搬移部位")}
        try transaction{$0.positionMode=mode}
    }
    public func updatePreferences(watchlist: Set<String>? = nil, allowEstimated: Bool? = nil, leverageEnabled: Bool? = nil, useReferenceRiskPrice: Bool? = nil, continueWhileAway: Bool? = nil, context: AccountContext) throws {
        try check(context)
        try transaction { s in
            if let watchlist { s.watchlist = watchlist }; if let allowEstimated { s.allowEstimatedExecution = allowEstimated }
            if let leverageEnabled { s.leverageEnabled = leverageEnabled }; if let continueWhileAway { s.continueWhileAway = continueWhileAway }
            if let useReferenceRiskPrice{s.useReferenceRiskPrice=useReferenceRiskPrice}
        }
    }
    public func toggleWatch(_ instrumentID:String,context:AccountContext)throws{
        try check(context)
        guard state.instruments.contains(where:{$0.id==instrumentID}) else{throw TradeError.invalid("自選商品不存在")}
        try transaction{s in if s.watchlist.contains(instrumentID){s.watchlist.remove(instrumentID)}else{s.watchlist.insert(instrumentID)}}
    }
    public func recordJournal(_ journal: JournalEntry, context: AccountContext) throws {
        try check(context)
        guard !journal.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw TradeError.invalid("日誌內容不能空白")}
        if let id=journal.orderID{guard try repository.order(id:id) != nil else{throw TradeError.invalid("關聯委託不在目前帳戶")}}
        try transaction{$0.journals.removeAll{$0.id==journal.id};$0.journals.append(journal)}
    }
    public func saveChartPreferences(instrumentID:String,preferences:ChartPreferences,context:AccountContext)throws{
        try check(context)
        guard state.instruments.contains(where:{$0.id==instrumentID}),(2...100).contains(preferences.period),[60,300,900,1800,3600,14400,86400,604800,2592000].contains(preferences.interval),["無","MA","EMA","MACD","RSI","KD","BOLL","VWAP","ATR"].contains(preferences.indicator) else{throw TradeError.invalid("圖表偏好超過範圍")}
        try transaction{if $0.chartPreferences==nil{$0.chartPreferences=[:]};$0.chartPreferences![instrumentID]=preferences}
    }
    public func addAlert(_ alert: PriceAlert, context: AccountContext) throws {
        try check(context)
        guard alert.percentage==nil,alert.baseline==nil,alert.basis==nil,alert.price > .zero,alert.firedAt==nil,!alert.id.isEmpty,alert.id.count<=128 else{throw TradeError.invalid("提醒價格或身份不合法")}
        let i=try Self.instrument(state,alert.instrumentID)
        guard i.asset != .index || !i.halted else{throw TradeError.invalid("此商品目前無可監控價格")}
        if state.alerts.contains(where:{$0.id==alert.id}){throw TradeError.invalid("此提醒已存在，未重複建立")}
        try transaction{$0.alerts.append(alert)}
    }
    public func addPercentageAlert(id:String=UUID().uuidString,instrumentID:String,percentage:Amount,above:Bool,basis:AlertPriceBasis = .creationPrice,board:TradingBoard?=nil,time:Int64,context:AccountContext)throws{
        try check(context)
        let i=try Self.instrument(state,instrumentID),now=state.simulation?.time ?? wallClock?() ?? time
        let maximum=try Amount(1000),hundred=try Amount(100)
        guard !id.isEmpty,id.count<=128,!state.alerts.contains(where:{$0.id==id}),percentage > .zero,percentage<=maximum,above || percentage<hundred,let q=state.quotes[i.quoteKey(board:board)],Self.fresh(q,now:now),q.last > .zero else{throw TradeError.invalid("建立百分比提醒需要有效新鮮價格及合理百分比；向下幅度須小於100%")}
        let baseline=basis == .creationPrice ? q.last:q.summary?.reference
        guard let baseline,baseline > .zero else{throw TradeError.unavailable("來源沒有提供前收／24小時起價，請改用建立時價格")}
        let ratio=try percentage/Amount(100),threshold=try baseline*(above ? .one+ratio:.one-ratio)
        var alert=PriceAlert(instrumentID:i.id,price:threshold,above:above);alert.id=id;alert.percentage=percentage;alert.baseline=baseline;alert.baselineTime=q.time;alert.basis=basis;alert.board=i.usesTaiwanBoards ? (board ?? .regular):nil
        try transaction{$0.alerts.append(alert)}
    }
    public func removeAlert(id:String,context:AccountContext)throws{try check(context);try transaction{$0.alerts.removeAll{$0.id==id}}}
    public func noticeDestination(_ link:NoticeLink,context:AccountContext)throws->NoticeDestination{
        try check(context);guard link.accountID==context.accountID else{throw TradeError.wrongAccount}
        guard let event=try repository.auditEvent(id:link.eventID),event.id==link.eventID else{throw TradeError.unavailable("原事件不在目前帳戶中；請檢查是否還原了另一份備份")}
        return NoticeDestination(event:event,instrument:state.instruments.first{$0.id==event.instrumentID})
    }
    public func configureNotifications(_ enabled:Bool,context:AccountContext)throws{try check(context);try transaction{s in s.notificationEnabled=enabled;if !enabled{for n in s.inbox?.indices ?? 0..<0{s.inbox![n].delivered=true}}}}
    public func acknowledgeNotices(_ ids:Set<String>,context:AccountContext)throws{
        try check(context);try transaction{s in for n in s.inbox?.indices ?? 0..<0{if ids.contains(s.inbox![n].id){s.inbox![n].delivered=true}}}
    }
    public func recordNotice(_ kind:String,message:String,time:Int64,context:AccountContext)throws{
        try check(context);guard ["rejected","catchupComplete"].contains(kind),message.utf8.count<=1000 else{throw TradeError.invalid("提醒類型不合法")}
        try transaction{$0.audit(kind,message,time:time)}
    }
    public func saveDrawing(_ drawing: Drawing, context: AccountContext) throws { try check(context); try transaction { $0.drawings.removeAll { $0.id == drawing.id }; $0.drawings.append(drawing) } }
    public func removeDrawing(id: String, context: AccountContext) throws { try check(context); try transaction { $0.drawings.removeAll { $0.id == id } } }
    public func addInstrument(_ i: Instrument, context: AccountContext) throws {
        try check(context)
        guard state.mode == .offline, i.id.hasPrefix("SIM:"), !state.instruments.contains(where: { $0.id == i.id }), i.initialPrice > .zero, i.rules.tick > .zero, i.rules.quantityStep > .zero else { throw TradeError.invalid("自訂商品規格不合法或代碼重複") }
        try transaction { s in s.instruments.append(i); if let sim = s.simulation { s.quotes[i.id] = try Simulation.quote(i, state: sim) } }
    }
    public func importOnlineInstruments(_ instruments: [Instrument],context: AccountContext) throws {
        try check(context)
        guard context.mode == .online,instruments.count<=2000,instruments.allSatisfy({$0.provider != nil && !$0.id.hasPrefix("SIM:") && $0.rules.tick > .zero && $0.rules.quantityStep > .zero}) else{throw TradeError.invalid("來源商品不合法或數量過多")}
        try transaction{s in for i in instruments where !s.instruments.contains(where:{$0.id==i.id}){s.instruments.append(i)};s.audit("catalogImported","匯入來源商品 \(instruments.count) 個；既有商品規格與持倉不改寫",time:Int64(Date().timeIntervalSince1970))}
    }
    public func saveWallClock(_ time: Int64, context: AccountContext) throws { try check(context); try transaction { $0.lastWallTime = time } }
    private static func recordEquity(_ s: inout AccountState,time: Int64) throws {
        let v=try Analytics.valuation(s,now:time)
        let value=v.complete ? v.total:nil
        if s.equity.last?.time==time,s.equity.last?.value==value{return}
        s.equity.append(EquityPoint(time:time,value:v.complete ? v.total:nil,flow:.zero))
    }
    private static func settleDue(_ s: inout AccountState,now: Int64) throws {
        guard s.lifecycle != nil else { return }
        for n in s.lifecycle!.settlements.indices {
            let event=s.lifecycle!.settlements[n]
            guard event.completedAt == nil,event.due <= now else { continue }
            s.cash[event.currency] = try (s.cash[event.currency] ?? .zero)+event.receivable-event.payable
            if event.receivable != .zero { s.post(event:event.id,currency:event.currency,debit:"cash",credit:"receivable",amount:event.receivable,time:now) }
            if event.payable != .zero { s.post(event:event.id,currency:event.currency,debit:"payable",credit:"cash",amount:event.payable,time:now) }
            s.lifecycle!.settlements[n].completedAt=now;s.appliedEvents.insert(event.id);s.audit("settlement","\(event.currency) 交割 \(event.id)",time:now)
        }
    }
    public func processDueEvents(time: Int64,context: AccountContext) throws {
        try check(context);try transaction { s in try Self.settleDue(&s,now:time) }
    }
    public func adoptCatalogRules(instrumentID:String,context:AccountContext)throws{
        try check(context)
        guard let replacement=try InstrumentCatalog.builtIn(mode:state.mode).first(where:{$0.id==instrumentID}) else{throw TradeError.invalid("此舊版自訂身份沒有可安全對應的內建規則")}
        try transaction{s in
            guard let index=s.instruments.firstIndex(where:{$0.id==instrumentID}),s.heldPositions(instrumentID).isEmpty,!s.orders.values.contains(where:{$0.request.instrumentID==instrumentID && $0.status.open}) else{throw TradeError.invalid("升級前須無持倉及未結委託；不會自動清倉、取消或搬移歷史")}
            s.instruments[index].rules=replacement.rules;s.instruments[index].identity=replacement.identity;s.instruments[index].requiresRuleConfirmation=replacement.requiresRuleConfirmation
            s.quotes.removeValue(forKey:instrumentID);s.quotes.removeValue(forKey:instrumentID+"::oddLot")
            s.consumed=s.consumed.filter{!$0.key.hasPrefix(instrumentID+"|") && !$0.key.hasPrefix(instrumentID+"::oddLot|")}
            s.audit("catalogRulesAdopted","核對原商品身份後升級交易規則；原帳務及成交保留",time:s.simulation?.time ?? Int64(Date().timeIntervalSince1970))
        }
    }
    public func updateRules(instrumentID: String,rules: RulePack,context: AccountContext) throws {
        try check(context);try TradingSessions.validate(rules)
        guard rules.tick > .zero,rules.quantityStep > .zero,rules.multiplier > .zero,rules.fees.taker >= .zero,rules.fees.taker < .one,rules.maxLeverage >= 1,rules.maintenance >= .zero,
              TimeZone(identifier:rules.timeZone) != nil,(0...1440).contains(rules.openMinute),(0...1440).contains(rules.closeMinute),(0...10).contains(rules.settlementBusinessDays ?? 0) else { throw TradeError.invalid("交易規則不合法") }
        try transaction { s in
            guard let n=s.instruments.firstIndex(where:{$0.id==instrumentID}) else { throw TradeError.invalid("找不到商品") }
            guard s.heldPositions(instrumentID).isEmpty,!s.orders.values.contains(where:{$0.status.open && $0.request.instrumentID==instrumentID}) else { throw TradeError.invalid("有持倉或未完成委託時不得直接更改商品規格") }
            if rules.carrySchedule != nil || rules.dailySettlementMinute != nil{s.schema=2}
            s.instruments[n].rules=rules;s.audit("rulesChanged","自訂模擬規則 \(rules.version)",time:s.simulation?.time ?? Int64(Date().timeIntervalSince1970))
            if s.instruments[n].requiresRuleConfirmation == true {
                guard s.instruments[n].asset != .future || rules.expiry != nil else{throw TradeError.invalid("到期期貨必須有明確到期日")}
                s.instruments[n].requiresRuleConfirmation=false
            }
        }
    }
    public func setFX(_ rate: FXRate,context: AccountContext) throws {
        try check(context)
        guard rate.rate > .zero,rate.base == state.baseCurrency,rate.currency != rate.base,rate.currency.range(of:"^[A-Z]{3,8}$",options:.regularExpression) != nil,rate.time>=0,rate.source.utf8.count<=512,!rate.source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,(60...604800).contains(rate.maximumAge ?? 86400),state.mode != .online || rate.kind != .simulated else { throw TradeError.invalid("匯率方向或來源不合法") }
        try transaction { s in if s.lifecycle == nil {s.lifecycle=LifecycleState()};s.lifecycle!.rates.removeAll{$0.currency==rate.currency && $0.base==rate.base};s.lifecycle!.rates.append(rate) }
    }
    public func adjustMargin(instrumentID: String,amount: Amount,time: Int64,positionSide:PositionSide?=nil,context: AccountContext) throws {
        try check(context)
        try transaction { s in
            let i=try Self.instrument(s,instrumentID)
            let key=s.positionKey(instrument:i,side:positionSide)
            guard i.asset.derivative,var p=s.positions[key],p.quantity != .zero,p.marginMode == .isolated else {throw TradeError.invalid("需有有效標記價與逐倉合約部位")}
            guard try amount <= Self.available(s,currency:i.currency) else {throw TradeError.insufficient("可用資金不足")}
            let changed=try p.margin+amount
            guard changed > .zero else{throw TradeError.invalid("保證金須大於零")}
            p.margin=changed;s.positions[key]=p
            if amount < .zero{
                let risk=try ContractRisk.evaluate(s,positionKey:key,now:self.wallClock?() ?? time)
                guard risk.equity>risk.maintenanceAndClosingFee else{throw TradeError.invalid("移除後不足以支付維持保證金與預估平倉費用")}
            }
            s.audit("marginAdjustment","\(instrumentID) 保證金調整 \(amount)",time:time)
        }
    }
    private static func postCarry(_ s:inout AccountState,instrument i:Instrument,rate:Amount,mark:Amount,amount:Amount,time:Int64,eventID:String,kind:String,source:String,model:String,positionKey:String?=nil)throws{
        guard !s.appliedEvents.contains(eventID) else{return}
        let key=positionKey ?? i.id
        if amount > .zero,var position=s.positions[key],position.marginMode == .isolated{
            let free=max(Amount.zero,try Self.available(s,currency:i.currency)),fromMargin=max(Amount.zero,try amount-free)
            position.margin=max(Amount.zero,try position.margin-fromMargin);s.positions[key]=position
        }
        s.cash[i.currency]=try (s.cash[i.currency] ?? .zero)-amount
        s.post(event:eventID,currency:i.currency,debit:kind,credit:"cash",amount:amount,time:time)
        if s.lifecycle==nil{s.lifecycle=LifecycleState()}
        s.lifecycle!.carry.append(CarryEvent(id:eventID,instrumentID:i.id,time:time,rate:rate,mark:mark,amount:amount,kind:kind,source:source,calculationModel:model,positionKey:positionKey))
        s.recordFinancialFlow(id:eventID,instrument:i,positionKey:key,time:time,kind:kind,amount:amount.negated,source:source)
        s.appliedEvents.insert(eventID);s.audit(kind,"\(i.id) \(source)；費率 \(rate)；費用 \(amount)",time:time,id:eventID)
    }
    public func applyCarry(instrumentID: String,rate: Amount,mark: Amount,time: Int64,eventID: String,kind: String,source: String,context: AccountContext) throws {
        try check(context)
        guard mark > .zero,!source.isEmpty,rate.magnitude <= .one else {throw TradeError.invalid("費率、標記價或來源不合法")}
        try transaction{s in
            guard !s.appliedEvents.contains(eventID) else{return}
            let i=try Self.instrument(s,instrumentID)
            guard i.asset.derivative else{throw TradeError.invalid("此介面僅限合約持有費用")}
            for position in s.heldPositions(instrumentID){
                let amount=try mark*position.quantity*i.rules.multiplier*rate
                let id=position.side.map{eventID+"-"+$0.rawValue} ?? eventID
                try Self.postCarry(&s,instrument:i,rate:rate,mark:mark,amount:amount,time:time,eventID:id,kind:kind,source:source,model:"signed-notional-rate-1",positionKey:position.id)
            }
            s.appliedEvents.insert(eventID)
            if let quote=s.quotes[i.id]{try Self.risk(&s,quote:quote,now:time)}
        }
    }
    private static func settleFutureState(_ s:inout AccountState,instrument i:Instrument,price:Amount,time:Int64,eventID:String,final:Bool,source:String)throws{
        guard !s.appliedEvents.contains(eventID) else{return}
        guard i.asset == .future,price > .zero else{throw TradeError.invalid("需為有效期貨結算價")}
        for current in s.heldPositions(i.id){
            var p=current
            let pnl=try (price-p.average)*p.quantity*i.rules.multiplier
            s.cash[i.currency]=try (s.cash[i.currency] ?? .zero)+pnl;p.realized=try p.realized+pnl;p.average=price
            let id=p.side.map{eventID+"-"+$0.rawValue} ?? eventID
            s.post(event:id,currency:i.currency,debit:"cash",credit:"future-settlement",amount:pnl,time:time)
            s.recordFinancialFlow(id:id,instrument:i,positionKey:p.id,time:time,kind:"futureSettlement",amount:pnl,closesPosition:final,newBasis:price,source:source)
            if final{p.quantity = .zero;p.average = .zero;p.margin = .zero}
            s.positions[p.id]=p
        }
        if final,let idx=s.instruments.firstIndex(where:{$0.id==i.id}){s.instruments[idx].rules.expiry=time}
        if final{for id in s.orders.keys where s.orders[id]!.status.open && s.orders[id]!.request.instrumentID==i.id{s.orders[id]!.status = .expired;s.orders[id]!.reserved = .zero}}
        s.appliedEvents.insert(eventID);s.audit("futureSettlement","\(i.id) \(final ? "到期現金結算":"每日結算，重設成本基準")；\(source)",time:time,id:eventID)
    }
    public func settleFuture(instrumentID: String,price: Amount,time: Int64,eventID: String,final: Bool,context: AccountContext) throws {
        try check(context)
        try transaction{s in try Self.settleFutureState(&s,instrument:Self.instrument(s,instrumentID),price:price,time:time,eventID:eventID,final:final,source:"使用者人工結算價")}
    }
    private static func scheduledOfflineLifecycle(_ s:inout AccountState,previous:Int64,now:Int64)throws{
        guard s.mode == .offline,let sim=s.simulation else{throw TradeError.wrongAccount}
        for i in s.instruments.sorted(by:{$0.id<$1.id}) where i.asset.derivative{
            let positions=s.heldPositions(i.id)
            if i.asset == .future,let expiry=i.rules.expiry,previous<expiry,expiry<=now{
                let mark=try s.quotes[i.id]?.mark ?? Simulation.price(i,at:previous,state:sim)
                try settleFutureState(&s,instrument:i,price:mark,time:expiry,eventID:"sim-expiry-\(i.id)-\(expiry)",final:true,source:"B 自訂最後權威標記價模型；非交易所結算價")
                continue
            }
            guard !positions.isEmpty else{continue}
            if let schedule=i.rules.carrySchedule,now%schedule.interval==schedule.offset,i.rules.isOpen(at:now){
                let mark=try i.halted ? (s.quotes[i.id]?.mark ?? Simulation.price(i,at:previous,state:sim)):Simulation.price(i,at:now,state:sim)
                for position in positions{
                    let rate=position.quantity > .zero ? schedule.longRate:schedule.shortRate
                    let amount=try mark*position.quantity.magnitude*i.rules.multiplier*rate
                    let event="sim-\(schedule.kind)-\(position.id)-\(now)"
                    try postCarry(&s,instrument:i,rate:rate,mark:mark,amount:amount,time:now,eventID:event,kind:schedule.kind,source:"B 自訂固定排程；正費率扣款、負費率返還",model:"absolute-notional-side-rate-1",positionKey:position.id)
                }
            }
            if i.asset == .future,let minute=i.rules.dailySettlementMinute{
                var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:i.rules.timeZone)!
                let day=Date(timeIntervalSince1970:TimeInterval(now))
                if let due=calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:day,matchingPolicy:.nextTime,repeatedTimePolicy:.first,direction:.forward){
                    let time=Int64(due.timeIntervalSince1970)
                    if previous<time,time<=now,(i.rules.isOpen(at:previous) || i.rules.isOpen(at:now)){
                        let mark=try s.quotes[i.id]?.mark ?? Simulation.price(i,at:previous,state:sim)
                        try settleFutureState(&s,instrument:i,price:mark,time:time,eventID:"sim-daily-\(i.id)-\(Self.utcDay(time,zone:i.rules.timeZone))",final:false,source:"B 自訂時區排程／最後權威標記價；DST 缺時取下一有效時間、重複時取首次")
                    }
                }
            }
        }
    }
    public func corporateAction(_ action:CorporateAction,context:AccountContext)throws{
        try check(context);try transaction{s in try Self.applyCorporateAction(action,to:&s)}
    }
    private static func applyCorporateAction(_ action:CorporateAction,to s:inout AccountState)throws{
            guard !s.appliedEvents.contains(action.id) else{return}
            guard !action.source.isEmpty,let index=s.instruments.firstIndex(where:{$0.id==action.instrumentID}) else {throw TradeError.invalid("缺少事件來源或商品")}
            let i=s.instruments[index]
            guard !i.asset.derivative else {throw TradeError.invalid("股務事件不可套到合約")}
            if s.lifecycle == nil{s.lifecycle=LifecycleState()}
            switch action.kind {
            case .split:
                guard let ratio=action.ratio,ratio > .zero else {throw TradeError.invalid("分割比例必須大於零")}
                if var p=s.positions[i.id]{p.quantity=try p.quantity*ratio;p.average=try p.average/ratio;s.positions[i.id]=p}
                for id in s.orders.keys where s.orders[id]!.status.open && s.orders[id]!.request.instrumentID==i.id {
                    var o=s.orders[id]!;o.request.quantity=try o.request.quantity*ratio;o.filled=try o.filled*ratio
                    if let p=o.request.price{o.request.price=try p/ratio};if let p=o.request.trigger{o.request.trigger=try p/ratio};if let p=o.extreme{o.extreme=try p/ratio};o.referencePrice=try o.referencePrice/ratio
                    if let p=o.request.bracketProfit{o.request.bracketProfit=try p/ratio};if let p=o.request.bracketStop{o.request.bracketStop=try p/ratio}
                    if let d=o.request.trailingDistance,!o.request.trailingPercent{o.request.trailingDistance=try d/ratio}
                    if try !o.request.quantity.isMultiple(of:i.rules.quantityStep) || !(o.request.price ?? i.rules.tick).isMultiple(of:i.rules.tick(at:o.request.price ?? i.rules.tick)){o.status = .cancelled;o.reserved = .zero}
                    o.revision+=1;s.orders[id]=o
                }
                s.recordFinancialFlow(id:action.id,instrument:i,time:action.time,kind:"split",amount:.zero,quantityRatio:ratio,source:action.source)
                if s.simulation != nil{s.simulation!.priceAdjustments=(s.simulation!.priceAdjustments ?? [])+[PriceAdjustment(instrumentID:i.id,time:action.time,factor:try .one/ratio,eventID:action.id)]}
                s.quotes.removeValue(forKey:i.id);s.quotes.removeValue(forKey:i.quoteKey(board:.oddLot));s.consumed=[:]
            case .dividend:
                guard let amount=action.cashPerUnit,amount >= .zero,let payment=action.paymentTime,payment >= action.time else {throw TradeError.invalid("股息金額或入帳時間不合法")}
                let income=try (s.positions[i.id]?.quantity ?? .zero)*amount
                s.lifecycle!.settlements.append(SettlementEvent(id:"dividend-\(action.id)",currency:i.currency,due:payment,receivable:income,payable:.zero))
                s.post(event:action.id,currency:i.currency,debit:"receivable",credit:"dividend-income",amount:income,time:action.time)
                s.recordFinancialFlow(id:action.id,instrument:i,time:action.time,kind:"dividend",amount:income,source:action.source)
            case .rename:guard let symbol=action.newSymbol,!symbol.isEmpty else{throw TradeError.invalid("新代碼不可空白")};s.instruments[index].symbol=symbol
            case .halt:s.instruments[index].halted=true
            case .resume:s.instruments[index].halted=false
            case .cashLiquidation:
                guard let price=action.cashPerUnit,price >= .zero else{throw TradeError.invalid("現金清算價不合法")}
                let realized=try s.positions[i.id].map{try (price-$0.average)*$0.quantity} ?? .zero
                s.recordFinancialFlow(id:action.id,instrument:i,time:action.time,kind:"cashLiquidation",amount:realized,closesPosition:true,newBasis:price,source:action.source)
                let value=try (s.positions[i.id]?.quantity ?? .zero)*price
                s.cash[i.currency]=try (s.cash[i.currency] ?? .zero)+value
                s.post(event:action.id,currency:i.currency,debit:"cash",credit:"spot-clearing",amount:value,time:action.time)
                if var p=s.positions[i.id]{p.realized=try p.realized+(price-p.average)*p.quantity;p.quantity = .zero;p.average = .zero;s.positions[i.id]=p}
                s.instruments[index].halted=true
                for id in s.orders.keys where s.orders[id]!.status.open && s.orders[id]!.request.instrumentID==i.id{s.orders[id]!.status = .cancelled;s.orders[id]!.reserved = .zero}
            }
            s.lifecycle!.actions.append(action);s.appliedEvents.insert(action.id);s.audit("corporateAction","\(action.kind.rawValue) · \(action.source)",time:action.time,id:action.id)
            try Self.settleDue(&s,now:action.time)
    }
    public func restore(_ restored: AccountState,maintenanceToken:UUID?=nil, context: AccountContext) throws {
        guard context==self.context,!retired else{throw TradeError.wrongAccount}
        guard maintenance==maintenanceToken else{throw TradeError.invalid("還原維護工作階段不符")}
        try AccountRepository.validate(restored, mode: context.mode)
        state = try repository.save(restored, replacing: true)
        maintenance=nil
    }
}
