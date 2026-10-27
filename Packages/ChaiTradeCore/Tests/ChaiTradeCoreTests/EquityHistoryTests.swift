import Foundation
import Testing
@testable import ChaiTradeCore

@Test func equityArchivalPreservesFlowsReturnsDrawdownAndEveryPoint()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),repo=try AccountRepository(root:root,mode:.online)
    var state=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    for n in 1..<5000{
        var flow=Amount.zero
        if n==1500{state.cash["TWD"]=try Amount("80000");state.post(event:"synthetic-loss",currency:"TWD",debit:"cash",credit:"synthetic-pnl",amount:try Amount("-20000"),time:Int64(n+1000));state.audit("fixture","synthetic loss",time:Int64(n+1000))}
        if n==1600{flow=try Amount("10000");state.cash["TWD"]=try Amount("90000");state.netFlows["TWD"]=try Amount("110000");state.post(event:"synthetic-deposit",currency:"TWD",debit:"cash",credit:"external-capital",amount:flow,time:Int64(n+1000));state.audit("fixture","synthetic deposit",time:Int64(n+1000))}
        if n==1700{state.cash["TWD"]=try Amount("99000");state.post(event:"synthetic-gain",currency:"TWD",debit:"cash",credit:"synthetic-pnl",amount:try Amount("9000"),time:Int64(n+1000));state.audit("fixture","synthetic gain",time:Int64(n+1000))}
        state.equity.append(EquityPoint(time:Int64(n+1000),value:state.cash["TWD"],flow:flow))
    }
    let hot=try repo.save(state),metrics=Analytics.equityMetrics(hot)
    #expect(hot.equity.count==1000);#expect(hot.history?.equityOffset==4000)
    #expect(abs((metrics.unit ?? 0)-0.88)<1e-12);#expect(abs((metrics.drawdown ?? 0)-0.2)<1e-12)
    let archived=try #require(try repo.equityPage(limit:1,before:1602).first)
    #expect(archived.cursor==1601);#expect(abs((archived.metrics.plottedUnit ?? 0)-0.8)<1e-12)
    let full=try #require(try repo.fullSnapshot())
    #expect(full.equity==state.equity);#expect(abs((Analytics.equityMetrics(full).unit ?? 0)-0.88)<1e-12)
    #expect(throws:TradeError.self){try BackupService.export(hot,password:nil,time:6000)}
    let data=try BackupService.export(full,password:nil,time:6000)
    #expect(try BackupService.validate(data,expectedMode:.online,password:nil).equity==full.equity)
    var invalid=hot;invalid.equity[0].value=try Amount("1")
    #expect(throws:TradeError.self){try repo.save(invalid)}
    #expect(try repo.load()?.equity.first?.value==Amount("99000"))
}
@Test func initialOfflineFundingUsesTheAuthoritativeSimulationClock()throws{
    let state=try TradingEngine.initial(mode:.offline,capital:Amount("1000"),time:1_793_089_800)
    #expect(state.equity.first?.time==state.simulation?.time)
    #expect(state.ledger.allSatisfy{$0.time==state.simulation?.time})
    #expect(state.events.allSatisfy{$0.time==state.simulation?.time})
}
