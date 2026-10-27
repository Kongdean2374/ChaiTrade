import Foundation

/// Economic P&L not already represented by a Fill. Capital transfers and settlement
/// payment of an existing receivable are deliberately excluded to avoid double counting.
public struct FinancialFlow:Codable,Identifiable,Sendable,Equatable{
    public var id:String
    public var accountID:String
    public var instrumentID:String
    public var positionKey:String
    public var currency:String
    public var time:Int64
    public var sequence:Int64
    public var kind:String
    public var amount:Amount
    public var closesPosition:Bool
    public var quantityRatio:Amount?
    public var newBasis:Amount?
    public var source:String
    public init(id:String,accountID:String,instrumentID:String,positionKey:String,currency:String,time:Int64,sequence:Int64,kind:String,amount:Amount,closesPosition:Bool=false,quantityRatio:Amount?=nil,newBasis:Amount?=nil,source:String){self.id=id;self.accountID=accountID;self.instrumentID=instrumentID;self.positionKey=positionKey;self.currency=currency;self.time=time;self.sequence=sequence;self.kind=kind;self.amount=amount;self.closesPosition=closesPosition;self.quantityRatio=quantityRatio;self.newBasis=newBasis;self.source=source}
}
public extension AccountState{
    mutating func recordFinancialFlow(id:String,instrument:Instrument,positionKey:String?=nil,time:Int64,kind:String,amount:Amount,closesPosition:Bool=false,quantityRatio:Amount?=nil,newBasis:Amount?=nil,source:String){
        if financialFlows==nil{financialFlows=[]}
        financialFlows!.append(FinancialFlow(id:id,accountID:accountID,instrumentID:instrument.id,positionKey:positionKey ?? instrument.id,currency:instrument.currency,time:time,sequence:sequence+1,kind:kind,amount:amount,closesPosition:closesPosition,quantityRatio:quantityRatio,newBasis:newBasis,source:source))
    }
}
/// Reconstructs old economic flows from immutable ledger entries and original
/// lifecycle metadata; it never changes a cash balance, fill or ledger entry.
public enum FinancialFlowMigration{
    public static func reconstruct(_ state:AccountState)throws->[FinancialFlow]{
        var result=state.financialFlows ?? [],known=Set(result.map(\.id))
        let instruments=Dictionary(uniqueKeysWithValues:state.instruments.map{($0.id,$0)})
        let events=Dictionary(uniqueKeysWithValues:state.events.map{($0.id,$0)})
        let ledger=Dictionary(grouping:state.ledger,by:\.eventID)
        func append(id:String,instrument:Instrument,key:String?=nil,time:Int64,kind:String,amount:Amount,closes:Bool=false,ratio:Amount?=nil,basis:Amount?=nil,source:String){
            guard known.insert(id).inserted else{return}
            result.append(FinancialFlow(id:id,accountID:state.accountID,instrumentID:instrument.id,positionKey:key ?? instrument.id,currency:instrument.currency,time:time,sequence:events[id]?.sequence ?? 0,kind:kind,amount:amount,closesPosition:closes,quantityRatio:ratio,newBasis:basis,source:source))
        }
        for event in state.lifecycle?.carry ?? []{if let instrument=instruments[event.instrumentID]{append(id:event.id,instrument:instrument,key:event.positionKey,time:event.time,kind:event.kind,amount:event.amount.negated,source:event.source)}}
        for action in state.lifecycle?.actions ?? []{
            guard let instrument=instruments[action.instrumentID] else{continue}
            if action.kind == .dividend{let amount=try sum((ledger[action.id] ?? []).filter{$0.account=="receivable"}.map(\.amount));append(id:action.id,instrument:instrument,time:action.time,kind:"dividend",amount:amount,source:action.source)}
            if action.kind == .split{append(id:action.id,instrument:instrument,time:action.time,kind:"split",amount:.zero,ratio:action.ratio,source:action.source)}
            if action.kind == .cashLiquidation{append(id:action.id,instrument:instrument,time:action.time,kind:"cashLiquidationReconstruct",amount:.zero,closes:true,basis:action.cashPerUnit,source:action.source)}
        }
        let filledOrderIDs=Set(state.fills.map(\.orderID))
        for event in state.events where event.kind=="futureSettlement" || event.kind=="liquidation"{
            if event.kind=="liquidation",filledOrderIDs.contains(event.id){continue}
            let instrument=state.instruments.first{event.message.hasPrefix($0.id+" ") || event.message.hasPrefix($0.symbol+" ") || event.id.hasPrefix("liquidation-"+$0.id+"-")}
            guard let instrument else{continue}
            let amount=try sum((ledger[event.id] ?? []).filter{$0.account=="cash"}.map(\.amount))
            append(id:event.id,instrument:instrument,time:event.time,kind:event.kind,amount:amount,closes:event.kind=="liquidation" || event.message.contains("到期現金結算"),source:"既有不可變帳本／事件遷移")
        }
        return result.sorted{($0.time,$0.sequence,$0.id)<($1.time,$1.sequence,$1.id)}
    }
}
