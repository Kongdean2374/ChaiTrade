import Foundation
import Testing
@testable import ChaiTradeCore

@Test func closedCyclesDoNotCountPartialExitsAsIndependentWins()throws{
    let state=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1),id=state.instruments[0].id
    func fill(_ key:String,_ time:Int64,_ side:Side,_ quantity:String,_ realized:String,_ fee:String)throws->Fill{
        Fill(id:key,accountID:state.accountID,orderID:key,instrumentID:id,side:side,quantity:try Amount(quantity),price:try Amount("100"),fee:try Amount(fee),tax:.zero,time:time,quoteTime:time,source:"synthetic-cycle-fixture",grade:.E1,estimatedExecution:false,liquidityEventID:key,ruleVersion:"fixture",realized:try Amount(realized))
    }
    let fills=try [fill("a",10,.buy,"10","0","1"),fill("b",20,.sell,"4","40","0.4"),fill("c",30,.sell,"6","60","0.6"),fill("d",40,.sell,"5","0","1"),fill("e",50,.buy,"10","-50","2"),fill("f",60,.sell,"5","25","1")]
    var accumulator=PerformanceAccumulator(state:state,from:0,until:100)
    try accumulator.include(fills[0]);try accumulator.include(fills[1])
    #expect(accumulator.report.cycles.isEmpty)
    for f in fills.dropFirst(2){try accumulator.include(f)}
    let report=accumulator.report,stats=try #require(report.cycles["USD"])
    #expect(stats.closed==3);#expect(stats.wins==2);#expect(stats.losses==1)
    #expect(try stats.gains==Amount("121"));#expect(try stats.lossAmounts==Amount("52"))
    #expect(try stats.averageWin==Amount("60.5"));#expect(try stats.averageLoss==Amount("52"))
    #expect(try stats.profitFactor==Amount("2.326923076923"))
    #expect(report.currencies["USD"]?.count==6)
    #expect(try report.currencies["USD"]?.fees==Amount("6"))
    #expect(report.recentCycles.map(\.openedAt)==[10,40,50])
    var range=PerformanceAccumulator(state:state,from:31,until:61)
    for f in fills{try range.include(f)}
    #expect(range.report.currencies["USD"]?.count==3);#expect(range.report.cycles["USD"]?.closed==2)
    #expect(PerformanceAccumulator(state:state,from:0,until:100).report.cycles.isEmpty)
}

@Test func drawdownIncludesDeficitsAndChartsDoNotBridgeMissingValuations()throws{
    #expect(Analytics.maximumDrawdown([1,0,-0.5])==1.5)
    let points=[EquityPoint(time:1,value:try Amount("100"),flow:.zero),EquityPoint(time:2,value:nil,flow:.zero),EquityPoint(time:3,value:try Amount("90"),flow:.zero)]
    let series=Analytics.equitySeries(points)
    #expect(series.map(\.segment)==[0,1])
    let nav=Analytics.timeWeighted([EquityPoint(time:1,value:try Amount("100"),flow:.zero),EquityPoint(time:2,value:try Amount("-50"),flow:.zero),EquityPoint(time:3,value:try Amount("-100"),flow:.zero)])
    #expect(nav[1] == -0.5);#expect(nav[2]==nil)
}
