import Foundation

public enum PositionMode:String,Codable,CaseIterable,Sendable{case oneWay,hedge
    public var label:String{self == .oneWay ? "單向淨持倉":"雙向持倉"}
}
public enum PositionSide:String,Codable,CaseIterable,Sendable{case long,short
    public var label:String{self == .long ? "多倉":"空倉"}
}
public struct RiskTier:Codable,Equatable,Sendable{
    public var upperNotional:Amount?
    public var initialRate:Amount
    public var maintenanceRate:Amount
    public var maxLeverage:Int
    public init(upperNotional:Amount?,initialRate:Amount,maintenanceRate:Amount,maxLeverage:Int){self.upperNotional=upperNotional;self.initialRate=initialRate;self.maintenanceRate=maintenanceRate;self.maxLeverage=maxLeverage}
}
public extension Position{
    var instrumentKey:String{instrumentID ?? id}
}
public extension AccountState{
    func positionKey(instrument:Instrument,side:PositionSide?)->String{
        guard instrument.asset.derivative,positionMode == .hedge,let side else{return instrument.id}
        return instrument.id+"::"+side.rawValue
    }
    func positionKey(for request:OrderRequest,instrument:Instrument)->String{positionKey(instrument:instrument,side:request.positionSide)}
    func heldPositions(_ instrumentID:String)->[Position]{positions.values.filter{$0.instrumentKey==instrumentID && $0.quantity != .zero}.sorted{$0.id<$1.id}}
}
public extension RulePack{
    func tier(at notional:Amount)->RiskTier?{riskTiers?.first{$0.upperNotional==nil || notional<=$0.upperNotional!}}
    func initialMargin(notional:Amount,leverage:Int)throws->Amount{
        let requested=try notional/Amount(leverage)
        guard let tier=tier(at:notional) else{return requested}
        return max(requested,try notional*tier.initialRate)
    }
    /// Progressive brackets are continuous at boundaries; no sudden all-notional maintenance jump.
    func maintenanceMargin(notional:Amount)throws->Amount{
        guard let tiers=riskTiers,!tiers.isEmpty else{return try notional*maintenance}
        var lower=Amount.zero,result=Amount.zero
        for tier in tiers{
            let upper=min(notional,tier.upperNotional ?? notional)
            if upper>lower{result=try result+(upper-lower)*tier.maintenanceRate}
            if notional<=upper{return result};lower=upper
        }
        throw TradeError.invalid("風險級距未涵蓋此名目金額")
    }
    func validateRiskTiers()throws{
        if let haircut=collateralFactor{guard haircut > .zero,haircut <= .one else{throw TradeError.invalid("抵押計算比例需大於0且不超過1")}}
        guard let tiers=riskTiers else{return}
        guard !tiers.isEmpty,tiers.count<=20,tiers.last?.upperNotional==nil else{throw TradeError.invalid("階梯保證金須有最後無上限級距，最多20階")}
        var lower=Amount.zero,previousInitial=Amount.zero,previousMaintenance=Amount.zero
        for (n,tier) in tiers.enumerated(){
            guard tier.initialRate > .zero,tier.initialRate <= .one,tier.maintenanceRate >= .zero,tier.maintenanceRate<tier.initialRate,tier.maxLeverage>=1,tier.maxLeverage<=maxLeverage,tier.initialRate>=previousInitial,tier.maintenanceRate>=previousMaintenance else{throw TradeError.invalid("階梯保證金比率或槓桿不合法")}
            if let upper=tier.upperNotional{guard upper>lower,n<tiers.count-1 else{throw TradeError.invalid("階梯名目金額必須遞增")};lower=upper}
            else if n != tiers.count-1{throw TradeError.invalid("只有最後級距可以無上限")}
            previousInitial=tier.initialRate;previousMaintenance=tier.maintenanceRate
        }
        guard let haircut=collateralFactor,haircut > .zero,haircut <= .one else{if collateralFactor==nil{return};throw TradeError.invalid("抵押計算比例需大於0且不超過1")}
    }
}

public struct PositionRiskSnapshot:Sendable{
    public var positionKey:String
    public var currency:String
    public var notional:Amount
    public var collateral:Amount
    public var unrealized:Amount
    public var equity:Amount
    public var maintenanceAndClosingFee:Amount
    public var ratio:Amount?
    public var level:String
}
public struct LiquidationEstimate:Sendable{
    public var lower:Amount?
    public var upper:Amount?
    public var assumptions:String
}
public enum ContractRisk{
    private static func fresh(_ quote:Quote,now:Int64)->Bool{quote.valid && quote.quality == .realtime && now>=quote.time-5 && now-quote.time<=quote.maximumAge && now-quote.receivedAt<=quote.maximumAge && (quote.mark ?? .zero) > .zero}
    public static func evaluate(_ state:AccountState,positionKey:String,now:Int64,candidateMark:Amount?=nil)throws->PositionRiskSnapshot{
        guard let position=state.positions[positionKey],position.quantity != .zero,let instrument=state.instruments.first(where:{$0.id==position.instrumentKey}),instrument.asset.derivative,let quote=state.quotes[instrument.id],fresh(quote,now:now) else{throw TradeError.unavailable("缺少有效風險價格，無法評估保證金；不使用過期或未知期間價格")}
        let mark=candidateMark ?? quote.mark!
        guard mark > .zero else{throw TradeError.invalid("風險價格須大於零")}
        let notional=try mark*position.quantity.magnitude*instrument.rules.multiplier
        let pnl=try (mark-position.average)*position.quantity*instrument.rules.multiplier
        var maintenance=try instrument.rules.maintenanceMargin(notional:notional)+notional*instrument.rules.fees.taker
        var collateral=try position.margin*(instrument.rules.collateralFactor ?? .one),unrealized=pnl
        if position.marginMode == .cross{
            let isolated=try sum(state.positions.values.filter{p in p.marginMode == .isolated && state.instruments.first{$0.id==p.instrumentKey}?.currency==instrument.currency}.map(\.margin))
            var reservations:[String:Amount]=[:]
            for order in state.orders.values where order.status.open && state.instruments.first(where:{$0.id==order.request.instrumentID})?.currency==instrument.currency{let key=order.request.groupID ?? order.id;reservations[key]=max(reservations[key] ?? .zero,order.reserved)}
            collateral=try (state.cash[instrument.currency] ?? .zero)-isolated-sum(reservations.values)
            if collateral > .zero{collateral=try collateral*(instrument.rules.collateralFactor ?? .one)}
            for other in state.positions.values where other.id != position.id && other.marginMode == .cross && other.quantity != .zero{
                guard let otherInstrument=state.instruments.first(where:{$0.id==other.instrumentKey}),otherInstrument.currency==instrument.currency else{continue}
                guard let otherQuote=state.quotes[other.instrumentKey],fresh(otherQuote,now:now) else{throw TradeError.unavailable("同風險群組另有過期價格，暫不宣告完整保證金評估")}
                let otherMark=other.instrumentKey==instrument.id ? mark:otherQuote.mark!
                let otherNotional=try otherMark*other.quantity.magnitude*otherInstrument.rules.multiplier
                unrealized=try unrealized+(otherMark-other.average)*other.quantity*otherInstrument.rules.multiplier
                maintenance=try maintenance+otherInstrument.rules.maintenanceMargin(notional:otherNotional)+otherNotional*otherInstrument.rules.fees.taker
            }
        }
        let equity=try collateral+unrealized,ratio=equity > .zero ? try maintenance/equity:nil
        let level=equity<=maintenance ? "需風險處理":equity <= (try maintenance*Amount(2)) ? "高風險":"正常"
        return PositionRiskSnapshot(positionKey:position.id,currency:instrument.currency,notional:notional,collateral:collateral,unrealized:unrealized,equity:equity,maintenanceAndClosingFee:maintenance,ratio:ratio,level:level)
    }
    public static func liquidationEstimate(_ state:AccountState,positionKey:String,now:Int64)throws->LiquidationEstimate{
        let current=try evaluate(state,positionKey:positionKey,now:now)
        guard let position=state.positions[positionKey],let instrument=state.instruments.first(where:{$0.id==position.instrumentKey}),let mark=state.quotes[instrument.id]?.mark else{throw TradeError.invalid("找不到風險部位")}
        func unsafe(_ price:Amount)throws->Bool{let r=try evaluate(state,positionKey:positionKey,now:now,candidateMark:price);return r.equity<=r.maintenanceAndClosingFee}
        if current.equity<=current.maintenanceAndClosingFee{return LiquidationEstimate(lower:mark,upper:mark,assumptions:"目前已達本機風險處理條件；實際處理仍需有效報價。")}
        var lower:Amount?,upper:Amount?
        var safePrice=mark,candidate=mark
        for _ in 0..<48{
            candidate=try candidate/Amount(2)
            let tick=instrument.rules.tick(at:candidate)
            if candidate<tick{candidate=tick}
            if try unsafe(candidate){var lo=candidate,hi=safePrice;for _ in 0..<48{if try hi-lo<=tick{break};let mid=try (lo+hi)/Amount(2);if try unsafe(mid){lo=mid}else{hi=mid}};lower=try instrument.rules.roundedPrice(hi,.up);break}
            safePrice=candidate;if candidate==tick{break}
        }
        safePrice=mark;candidate=mark
        for _ in 0..<48{
            guard let next=try? candidate*Amount(2),next>candidate else{break};candidate=next
            guard let result=try? unsafe(candidate) else{break}
            if result{var lo=safePrice,hi=candidate;let tick=instrument.rules.tick(at:candidate);for _ in 0..<48{if try hi-lo<=tick{break};let mid=try (lo+hi)/Amount(2);if try unsafe(mid){hi=mid}else{lo=mid}};upper=try instrument.rules.roundedPrice(lo,.down);break}
            safePrice=candidate
        }
        return LiquidationEstimate(lower:lower,upper:upper,assumptions:"本機估計，包含階梯維持保證金、抵押折扣、未結委託保留與平倉費。假設其他商品價格固定，同標的雙向部位同步變動；不含未來資金費、跳空或額外滑價。")
    }
}

public extension ContractRisk{
    static func projected(_ state:AccountState,request:OrderRequest,price:Amount,now:Int64)throws->(PositionRiskSnapshot,LiquidationEstimate)?{
        guard let instrument=state.instruments.first(where:{$0.id==request.instrumentID}),instrument.asset.derivative,price > .zero,request.quantity > .zero else{return nil}
        var projected=state
        let key=state.positionKey(for:request,instrument:instrument)
        var position=state.positions[key] ?? Position(id:key)
        if key != instrument.id{position.instrumentID=instrument.id;position.side=request.positionSide}
        let old=position.quantity,delta=try request.quantity*request.side.sign
        let closing=old.sign != 0 && old.sign != delta.sign ? min(old.magnitude,request.quantity):.zero
        if request.reduceOnly{guard closing==request.quantity else{throw TradeError.invalid("預估平倉數量超過可平部位")}}
        let next=try old+delta,opening=try request.quantity-closing
        let realized=try (price-position.average)*closing*Amount(old.sign)*instrument.rules.multiplier
        if old == .zero || old.sign==delta.sign{position.average=try (position.average*old.magnitude+price*request.quantity)/next.magnitude}
        else if next == .zero{position.average = .zero}else if next.sign != old.sign{position.average=price}
        let released=old == .zero ? .zero:try position.margin*closing/old.magnitude
        position.margin=try position.margin-released+instrument.rules.initialMargin(notional:opening*price*instrument.rules.multiplier,leverage:request.leverage)
        if opening > .zero{position.margin=max(position.margin,try instrument.rules.initialMargin(notional:next.magnitude*price*instrument.rules.multiplier,leverage:request.leverage));position.leverage=request.leverage;position.marginMode=request.marginMode}
        position.quantity=next;projected.positions[key]=position
        let fee=try instrument.rules.fees.cumulative(notional:price*request.quantity*instrument.rules.multiplier,maker:request.postOnly)
        projected.cash[instrument.currency]=try (state.cash[instrument.currency] ?? .zero)+realized-fee
        if next == .zero{return nil}
        if var quote=projected.quotes[instrument.id]{quote.mark=price;projected.quotes[instrument.id]=quote}
        return (try evaluate(projected,positionKey:key,now:now),try liquidationEstimate(projected,positionKey:key,now:now))
    }
}
