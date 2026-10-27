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
    public var version=1
    public var valuationComplete=false
    public var valuationMissing:[String]=[]
    public var from:Int64
    public var until:Int64
    public var currencies:[String:FillTotals]=[:]
    public var instruments:[String:FillTotals]=[:]
    public var markets:[String:FillTotals]=[:]
    public var cycles:[String:CycleStats]=[:]
    public var recentCycles:[ClosedCycle]=[]
    public var policy="模擬交易；由首次建倉至同商品部位歸零為一個周期，反向成交拆分新周期；部分成交不重複計為勝利。已結束周期的成本包含區間開始前的建倉費。周期淨額扣成交費稅，不包含股息、持有費、每日結算及標記價強平現金流。不同幣別不相加。聚合 notional 為價格×數量；舊合約缺少逐筆歷史乘數時不可當作名目本金，介面不顯示該合約金額。"
}
struct OpenCycle:Codable,Sendable{var quantity=Amount.zero,net=Amount.zero;var openedAt:Int64}
struct PerformanceCheckpoint:Codable,Sendable{
    var open:[String:OpenCycle]
    @CanonicalStringSet var actions:Set<String>
    var processed:Int
    var lastTime:Int64
    var firstTime:Int64?
    var report:PerformanceReport?
}
struct PerformanceAccumulator{
    private var open:[String:OpenCycle]=[:]
    private var instruments:[String:Instrument]
    private var actions:[CorporateAction]
    private var processedActions:Set<String>=[]
    private(set) var processed=0
    private(set) var lastTime:Int64=0
    private var firstTime:Int64?
    var report:PerformanceReport
    init(state:AccountState,from:Int64,until:Int64,checkpoint:PerformanceCheckpoint?=nil,restoreTotals:Bool=false){
        instruments=Dictionary(uniqueKeysWithValues:state.instruments.map{($0.id,$0)})
        actions=(state.lifecycle?.actions ?? []).sorted{$0.time<$1.time}
        if let checkpoint{open=checkpoint.open;processedActions=checkpoint.actions;processed=checkpoint.processed;lastTime=checkpoint.lastTime;firstTime=checkpoint.firstTime}
        report=restoreTotals ? (checkpoint?.report ?? PerformanceReport(accountID:state.accountID,mode:state.mode,from:from,until:until)):PerformanceReport(accountID:state.accountID,mode:state.mode,from:from,until:until)
        let valuation=try? Analytics.valuation(state);report.valuationComplete=valuation?.complete ?? false;report.valuationMissing=valuation?.missing ?? ["估值計算失敗"]
    }
    func checkpoint(totals:Bool)->PerformanceCheckpoint{PerformanceCheckpoint(open:open,actions:processedActions,processed:processed,lastTime:lastTime,firstTime:firstTime,report:totals ? report:nil)}
    mutating func include(_ fill:Fill)throws{
        guard fill.accountID==report.accountID,let instrument=instruments[fill.instrumentID] else{throw TradeError.wrongAccount}
        processed+=1;lastTime=fill.time;if firstTime==nil{firstTime=fill.time}
        for action in actions where action.time<=fill.time && !processedActions.contains(action.id){
            processedActions.insert(action.id)
            if action.kind == .split,let ratio=action.ratio,var cycle=open[action.instrumentID]{cycle.quantity=try cycle.quantity*ratio;open[action.instrumentID]=cycle}
        }
        if fill.time>=report.from && fill.time<report.until{
            var c=report.currencies[instrument.currency] ?? FillTotals();try c.include(fill);report.currencies[instrument.currency]=c
            var i=report.instruments[instrument.id] ?? FillTotals();try i.include(fill);report.instruments[instrument.id]=i
            let key=instrument.asset.rawValue+"|"+instrument.currency
            var m=report.markets[key] ?? FillTotals();try m.include(fill);report.markets[key]=m
        }
        let signed=fill.side == .buy ? fill.quantity:fill.quantity.negated,cost=try fill.fee+fill.tax
        var cycle=open[fill.instrumentID] ?? OpenCycle(openedAt:fill.time)
        if cycle.quantity == .zero || cycle.quantity.sign==signed.sign{
            cycle.quantity=try cycle.quantity+signed;cycle.net=try cycle.net+fill.realized-cost;open[fill.instrumentID]=cycle;return
        }
        let closingCost=cost == .zero ? .zero:try cost*(min(cycle.quantity.magnitude,fill.quantity)/fill.quantity)
        cycle.net=try cycle.net+fill.realized-closingCost
        let after=try cycle.quantity+signed
        if after == .zero || after.sign != cycle.quantity.sign{
            let closed=ClosedCycle(id:fill.id,instrumentID:fill.instrumentID,currency:instrument.currency,openedAt:cycle.openedAt,closedAt:fill.time,net:cycle.net)
            if fill.time>=report.from && fill.time<report.until{
                var stats=report.cycles[instrument.currency] ?? CycleStats();try stats.add(closed);report.cycles[instrument.currency]=stats
                report.recentCycles.append(closed);if report.recentCycles.count>100{report.recentCycles.removeFirst()}
            }
            if after == .zero{open.removeValue(forKey:fill.instrumentID)}else{open[fill.instrumentID]=OpenCycle(quantity:after,net:try (cost-closingCost).negated,openedAt:fill.time)}
        }else{cycle.quantity=after;open[fill.instrumentID]=cycle}
    }
}
