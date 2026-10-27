import Foundation

public struct CycleStats:Codable,Sendable{
    public var closed=0,wins=0,losses=0,flat=0
    public var gains=Amount.zero,lossAmounts=Amount.zero
    public var holdingSeconds:Int64=0
    public var winRate:Double?{closed>0 ? Double(wins)/Double(closed):nil}
    public var averageHoldingSeconds:Double?{closed>0 ? Double(holdingSeconds)/Double(closed):nil}
    public var averageWin:Amount?{wins>0 ? try? gains/Amount(wins):nil}
    public var averageLoss:Amount?{losses>0 ? try? lossAmounts/Amount(losses):nil}
    public var profitFactor:Amount?{lossAmounts > .zero ? try? gains/lossAmounts:nil}
    mutating func add(_ cycle:ClosedCycle)throws{
        closed+=1;holdingSeconds+=max(0,cycle.closedAt-cycle.openedAt)
        if cycle.net > .zero{wins+=1;gains=try gains+cycle.net}else if cycle.net < .zero{losses+=1;lossAmounts=try lossAmounts+cycle.net.magnitude}else{flat+=1}
    }
}
public struct ClosedCycle:Codable,Identifiable,Sendable{
    public var id:String
    public var instrumentID:String
    public var currency:String
    public var openedAt:Int64
    public var closedAt:Int64
    public var net:Amount
}
public struct PerformanceReport:Codable,Sendable{
    public var accountID:String
    public var mode:Mode
    public var version=2
    public var valuationComplete=false
    public var valuationMissing:[String]=[]
    public var from:Int64
    public var until:Int64
    public var currencies:[String:FillTotals]=[:]
    public var instruments:[String:FillTotals]=[:]
    public var markets:[String:FillTotals]=[:]
    public var cycles:[String:CycleStats]=[:]
    public var recentCycles:[ClosedCycle]=[]
    public var cashFlows:[String:[String:Amount]]?
    public var economicNet:[String:Amount]?
    public var policy="模擬交易；以每一單向或雙向部位從建立至歸零為一個周期，反向成交拆分新周期。周期淨額包含成交費稅、股息應收、資金費、利息、每日／到期結算及強平；應收入帳不重複計收益，外部本金與換匯不計交易勝利。日期區間內結束的周期保留區間前成本。不同幣別分開。新成交固定保存歷史乘數與名目金額；舊資料缺少逐筆乘數時金額標示不完整。"

}
struct OpenCycle:Codable,Sendable{var quantity=Amount.zero,net=Amount.zero;var average:Amount?;var openedAt:Int64}
struct PerformanceCheckpoint:Codable,Sendable{
    var open:[String:OpenCycle]
    @CanonicalStringSet var actions:Set<String>
    var processed:Int
    var lastTime:Int64
    var firstTime:Int64?
    var report:PerformanceReport?
    var version:Int?
    var processedFlows:Int?
    var lastSequence:Int64?
}
struct PerformanceAccumulator{
    private var open:[String:OpenCycle]=[:]
    private var instruments:[String:Instrument]
    private(set) var processed=0
    private(set) var processedFlows=0
    private(set) var lastTime:Int64=0
    private(set) var lastSequence:Int64=0
    private var firstTime:Int64?
    var report:PerformanceReport
    init(state:AccountState,from:Int64,until:Int64,checkpoint:PerformanceCheckpoint?=nil,restoreTotals:Bool=false){
        instruments=Dictionary(uniqueKeysWithValues:state.instruments.map{($0.id,$0)})
        if let checkpoint{open=checkpoint.open;processed=checkpoint.processed;processedFlows=checkpoint.processedFlows ?? 0;lastTime=checkpoint.lastTime;lastSequence=checkpoint.lastSequence ?? 0;firstTime=checkpoint.firstTime}
        report=restoreTotals ? (checkpoint?.report ?? PerformanceReport(accountID:state.accountID,mode:state.mode,from:from,until:until)):PerformanceReport(accountID:state.accountID,mode:state.mode,from:from,until:until)
        let valuation=try? Analytics.valuation(state);report.valuationComplete=valuation?.complete ?? false;report.valuationMissing=valuation?.missing ?? ["估值計算失敗"]
    }
    func checkpoint(totals:Bool)->PerformanceCheckpoint{PerformanceCheckpoint(open:open,actions:[],processed:processed,lastTime:lastTime,firstTime:firstTime,report:totals ? report:nil,version:2,processedFlows:processedFlows,lastSequence:lastSequence)}
    private mutating func cursor(time:Int64,sequence:Int64){lastTime=time;lastSequence=sequence;if firstTime==nil{firstTime=time}}
    private func included(_ time:Int64)->Bool{time>=report.from && time<report.until}
    private mutating func economic(_ amount:Amount,currency:String)throws{if report.economicNet==nil{report.economicNet=[:]};report.economicNet![currency]=try (report.economicNet![currency] ?? .zero)+amount}
    private mutating func close(_ cycle:OpenCycle,id:String,instrument:Instrument,time:Int64)throws{
        guard included(time) else{return}
        let closed=ClosedCycle(id:id,instrumentID:instrument.id,currency:instrument.currency,openedAt:cycle.openedAt,closedAt:time,net:cycle.net)
        var stats=report.cycles[instrument.currency] ?? CycleStats();try stats.add(closed);report.cycles[instrument.currency]=stats
        report.recentCycles.append(closed);if report.recentCycles.count>100{report.recentCycles.removeFirst()}
    }
    mutating func include(_ fill:Fill)throws{
        guard fill.accountID==report.accountID,let instrument=instruments[fill.instrumentID] else{throw TradeError.wrongAccount}
        processed+=1;cursor(time:fill.time,sequence:fill.timelineSequence ?? 0)
        let cost=try fill.fee+fill.tax
        if included(fill.time){
            var c=report.currencies[instrument.currency] ?? FillTotals();try c.include(fill);report.currencies[instrument.currency]=c
            var i=report.instruments[instrument.id] ?? FillTotals();try i.include(fill);report.instruments[instrument.id]=i
            let key=instrument.asset.rawValue+"|"+instrument.currency
            var m=report.markets[key] ?? FillTotals();try m.include(fill);report.markets[key]=m
            try economic(fill.realized-cost,currency:instrument.currency)
        }
        let key=fill.positionKey ?? fill.instrumentID,signed=fill.side == .buy ? fill.quantity:fill.quantity.negated
        var cycle=open[key] ?? OpenCycle(openedAt:fill.time)
        if cycle.quantity == .zero || cycle.quantity.sign==signed.sign{
            let quantity=try cycle.quantity+signed
            cycle.average=try ((cycle.average ?? .zero)*cycle.quantity.magnitude+fill.price*fill.quantity)/quantity.magnitude
            cycle.quantity=quantity;cycle.net=try cycle.net+fill.realized-cost;open[key]=cycle;return
        }
        let closingCost=cost == .zero ? .zero:try cost*(min(cycle.quantity.magnitude,fill.quantity)/fill.quantity)
        cycle.net=try cycle.net+fill.realized-closingCost
        let after=try cycle.quantity+signed
        if after == .zero || after.sign != cycle.quantity.sign{
            try close(cycle,id:fill.id,instrument:instrument,time:fill.time)
            if after == .zero{open.removeValue(forKey:key)}else{open[key]=OpenCycle(quantity:after,net:try (cost-closingCost).negated,average:fill.price,openedAt:fill.time)}
        }else{cycle.quantity=after;open[key]=cycle}
    }
    mutating func include(_ flow:FinancialFlow)throws{
        guard flow.accountID==report.accountID,let instrument=instruments[flow.instrumentID] else{throw TradeError.wrongAccount}
        processedFlows+=1;cursor(time:flow.time,sequence:flow.sequence)
        var cycle=open[flow.positionKey]
        var amount=flow.amount
        if flow.kind=="cashLiquidationReconstruct",let cycle,let price=flow.newBasis{amount=try (price-(cycle.average ?? .zero))*cycle.quantity*instrument.rules.multiplier}
        if included(flow.time){
            if report.cashFlows==nil{report.cashFlows=[:]}
            var currency=report.cashFlows![flow.currency] ?? [:];currency[flow.kind]=try (currency[flow.kind] ?? .zero)+amount;report.cashFlows![flow.currency]=currency
            try economic(amount,currency:flow.currency)
        }
        guard var value=cycle else{return}
        value.net=try value.net+amount
        if let ratio=flow.quantityRatio{value.quantity=try value.quantity*ratio;value.average=try value.average.map{try $0/ratio}}
        else if let basis=flow.newBasis{value.average=basis}
        if flow.closesPosition{try close(value,id:flow.id,instrument:instrument,time:flow.time);open.removeValue(forKey:flow.positionKey)}else{open[flow.positionKey]=value}
    }
}

enum PerformanceInput{
    case fill(Fill),flow(FinancialFlow)
    var time:Int64{switch self{case .fill(let f):f.time;case .flow(let f):f.time}}
    var sequence:Int64{switch self{case .fill(let f):f.timelineSequence ?? 0;case .flow(let f):f.sequence}}
    func include(in accumulator:inout PerformanceAccumulator)throws{switch self{case .fill(let f):try accumulator.include(f);case .flow(let f):try accumulator.include(f)}}
}
