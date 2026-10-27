import Foundation

/// Immutable external-capital valuation at the time of the local deposit/withdrawal.
/// A later FX quote may value today's assets, but cannot rewrite this historical cost.
public struct CapitalFlowValuation:Codable,Equatable,Sendable{
    public var currency:String
    public var amount:Amount
    public var baseCurrency:String
    public var baseAmount:Amount?
    public var time:Int64
    public var rate:FXRate?
    public init(currency:String,amount:Amount,baseCurrency:String,time:Int64,rate:FXRate?)throws{
        self.currency=currency;self.amount=amount;self.baseCurrency=baseCurrency;self.time=time
        if currency==baseCurrency{self.baseAmount=amount;self.rate=nil}
        else if let rate,rate.currency==currency,rate.base==baseCurrency,rate.usable(at:time){self.rate=rate;self.baseAmount=try amount*rate.rate}
        else{self.rate=nil;self.baseAmount=nil}
    }
    public func validate()throws{
        guard time>=0,!currency.isEmpty,!baseCurrency.isEmpty else{throw TradeError.corrupt("外部資金估值身份不合法")}
        let expected=try CapitalFlowValuation(currency:currency,amount:amount,baseCurrency:baseCurrency,time:time,rate:rate)
        guard baseAmount==expected.baseAmount,(rate==nil)==(expected.rate==nil) else{throw TradeError.corrupt("外部資金歷史匯率與入帳成本不符")}
    }
}
public struct CapitalBasis:Codable,Equatable,Sendable{
    public var knownBase=Amount.zero
    public var unvaluedCount=0
    @CanonicalStringSet public var unvaluedCurrencies:Set<String>=[]
    public var contributions:[String:Amount]=[:]
    public init(){}
    public static func ==(lhs:Self,rhs:Self)->Bool{lhs.knownBase==rhs.knownBase && lhs.unvaluedCount==rhs.unvaluedCount && lhs.unvaluedCurrencies==rhs.unvaluedCurrencies && lhs.contributions==rhs.contributions}
    public mutating func include(_ flow:CapitalFlowValuation)throws{
        try flow.validate()
        contributions[flow.currency]=try (contributions[flow.currency] ?? .zero)+flow.amount
        if let value=flow.baseAmount{knownBase=try knownBase+value}
        else if flow.amount != .zero{unvaluedCount+=1;unvaluedCurrencies.insert(flow.currency)}
    }
    public func matches(_ netFlows:[String:Amount])->Bool{contributions.filter{$0.value != .zero}==netFlows.filter{$0.value != .zero}}
    /// Legacy foreign flows have no trustworthy historical FX. Never substitute today's quote.
    static func legacyProjection(_ state:AccountState)->Self{
        var result=Self();result.knownBase=state.netFlows[state.baseCurrency] ?? .zero;result.contributions=state.netFlows
        result.unvaluedCurrencies=Set(state.netFlows.keys.filter{$0 != state.baseCurrency})
        result.unvaluedCount=result.unvaluedCurrencies.count;return result
    }
    static func reconstruct(_ state:AccountState)throws->Self{
        guard (state.history?.ledger ?? 0)==0 else{throw TradeError.invalid("重建歷史資金成本需要完整帳本")}
        var events:[String:CapitalFlowValuation]=[:]
        for event in state.events{if let flow=event.capitalFlow{guard events[event.id]==nil else{throw TradeError.corrupt("資金估值事件重複")};events[event.id]=flow}}
        var result=Self(),seen=Set<String>()
        for entry in state.ledger where entry.account=="external-capital"{
            guard seen.insert(entry.eventID).inserted else{throw TradeError.corrupt("外部資金事件重複")}
            try result.include(try checkedFlow(entry:entry,metadata:events[entry.eventID],base:state.baseCurrency))
        }
        guard result.matches(state.netFlows) else{throw TradeError.corrupt("歷史外部資金與淨投入不符")}
        return result
    }
    static func checkedFlow(entry:LedgerEntry,metadata:CapitalFlowValuation?,base:String)throws->CapitalFlowValuation{
        if let metadata{
            guard metadata.currency==entry.currency,metadata.amount==entry.amount.negated,metadata.time==entry.time,metadata.baseCurrency==base else{throw TradeError.corrupt("資金估值與原始帳本不符")}
            return metadata
        }
        return try CapitalFlowValuation(currency:entry.currency,amount:entry.amount.negated,baseCurrency:base,time:entry.time,rate:nil)
    }
}
