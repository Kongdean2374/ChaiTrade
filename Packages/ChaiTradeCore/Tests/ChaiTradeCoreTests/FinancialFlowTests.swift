import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

private struct FlowRig{
    let context=AccountContext(mode:.online)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let instrument:Instrument
    let repository:AccountRepository
    let engine:TradingEngine
    init(asset:AssetClass = .usStock,multiplier:String="1")throws{
        var rules=try RulePack(tick:Amount("0.01"),quantityStep:.one);rules.multiplier=try Amount(multiplier);rules.fees.taker=try Amount("0.001")
        instrument=Instrument(id:"FLOW",symbol:"FLOW",name:"合成現金流驗證",asset:asset,currency:"USD",rules:rules,initialPrice:try Amount(100))
        var state=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount(100000),time:1000);state.instruments=[instrument];state.leverageEnabled=true
        repository=try AccountRepository(root:root,mode:.online);engine=try TradingEngine(context:context,repository:repository,initial:state)
    }
    func quote(bid:String="99",ask:String="100",time:Int64=1000)throws->Quote{
        var quote=Quote(instrumentID:"FLOW",source:"synthetic-flow-fixture",time:time,sequence:time,last:try Amount(ask),bids:[Level(try Amount(bid),try Amount(10000))],asks:[Level(try Amount(ask),try Amount(10000))]);quote.mark=try Amount(ask);return quote
    }
    func request(_ side:Side,quantity:Int=10,positionSide:PositionSide?=nil)throws->OrderRequest{var request=OrderRequest(instrumentID:"FLOW",side:side,kind:.market,quantity:try Amount(quantity));request.positionSide=positionSide;return request}
}
@Test func dividendSplitAndExitCyclesIncludeEconomicIncomeWithoutCountingPaymentTwice()async throws{
    let rig=try FlowRig(),ctx=rig.context
    try await rig.engine.ingest(rig.quote(),now:1000,context:ctx);_=try await rig.engine.submit(rig.request(.buy),time:1000,context:ctx)
    try await rig.engine.corporateAction(CorporateAction(id:"split-flow",instrumentID:"FLOW",kind:.split,time:1001,ratio:Amount(2),source:"合成股務測試"),context:ctx)
    try await rig.engine.ingest(rig.quote(bid:"54",ask:"55",time:1002),now:1002,context:ctx)
    try await rig.engine.corporateAction(CorporateAction(id:"dividend-flow",instrumentID:"FLOW",kind:.dividend,time:1003,cashPerUnit:Amount("0.25"),paymentTime:1006,source:"合成股務測試"),context:ctx)
    _=try await rig.engine.submit(rig.request(.sell,quantity:20),time:1004,context:ctx)
    let report=try await rig.engine.performance(from:0,until:2000,context:ctx)
    #expect(report.version==2);#expect(report.cycles["USD"]?.closed==1);#expect(report.recentCycles.first?.net == (try Amount("82.92")))
    #expect(report.cashFlows?["USD"]?["dividend"] == (try Amount(5)));#expect(report.economicNet?["USD"] == (try Amount("82.92")))
    #expect(report.currencies["USD"]?.notional == (try Amount(2080)));#expect(report.currencies["USD"]?.notionalComplete==true)
    let period=try await rig.engine.performance(from:1003,until:1005,context:ctx)
    #expect(period.recentCycles.first?.net == (try Amount("82.92")))
    #expect(period.economicNet?["USD"] == (try Amount("83.92")))
    try await rig.engine.ingest(rig.quote(bid:"54",ask:"55",time:1006),now:1006,context:ctx)
    let after=try await rig.engine.performance(from:0,until:2000,context:ctx)
    #expect(after.economicNet==report.economicNet)
    #expect(await rig.engine.snapshot().cash["USD"] == (try Amount("100082.92")))
}
@Test func hedgeCyclesIncludeFundingDailyAndFinalSettlementWithSeparateWins()async throws{
    let rig=try FlowRig(asset:.future),ctx=rig.context
    try await rig.engine.setPositionMode(.hedge,context:ctx);try await rig.engine.ingest(rig.quote(),now:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(.buy,quantity:5,positionSide:.long),time:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(.sell,quantity:5,positionSide:.short),time:1000,context:ctx)
    try await rig.engine.applyCarry(instrumentID:"FLOW",rate:Amount("0.01"),mark:Amount(100),time:1001,eventID:"funding",kind:"funding",source:"合成資金費",context:ctx)
    try await rig.engine.settleFuture(instrumentID:"FLOW",price:Amount(110),time:1002,eventID:"daily",final:false,context:ctx)
    try await rig.engine.settleFuture(instrumentID:"FLOW",price:Amount(105),time:1003,eventID:"final",final:true,context:ctx)
    let report=try await rig.engine.performance(from:0,until:2000,context:ctx)
    #expect(report.cycles["USD"]?.closed==2);#expect(report.cycles["USD"]?.wins==1);#expect(report.cycles["USD"]?.losses==1)
    #expect(Set(report.recentCycles.map(\.net))==[try Amount("19.5"),try Amount("-25.495")])
    #expect(report.cashFlows?["USD"]?["funding"] == .zero)
    #expect(report.cashFlows?["USD"]?["futureSettlement"] == (try Amount(-5)))
    #expect(report.economicNet?["USD"] == (try Amount("-5.995")))
}
@Test func archivedEconomicFlowsAndLegacyMigrationKeepCashAndPeriodReports()async throws{
    let rig=try FlowRig(asset:.perpetual),ctx=rig.context
    try await rig.engine.ingest(rig.quote(),now:1000,context:ctx);_=try await rig.engine.submit(rig.request(.buy,quantity:5),time:1000,context:ctx)
    for n in 1...220{try await rig.engine.applyCarry(instrumentID:"FLOW",rate:Amount("0.0001"),mark:Amount(100),time:1000+Int64(n),eventID:"carry-\(n)",kind:"funding",source:"合成長期持有費",context:ctx)}
    let hot=await rig.engine.snapshot(),full=try await rig.engine.fullSnapshot(context:ctx),report=try await rig.engine.performance(context:ctx)
    #expect(hot.financialFlows?.count==100);#expect(hot.history?.financialFlowOffset==120);#expect(full.financialFlows?.count==220)
    #expect(report.economicNet?["USD"] == (try Amount("-11.5")))
    #expect(throws:TradeError.self){try BackupService.export(hot,password:nil,time:1300)}
    let backup=try BackupService.export(full,password:nil,time:1300),envelope=try JSONDecoder().decode(BackupEnvelope.self,from:backup)
    #expect(envelope.version==3)
    let restored=try BackupService.validate(backup,expectedMode:.online,password:nil)
    #expect(restored.financialFlows?.count==220 && restored.cash==full.cash)
    // Represent the shipped SQLite-v4 account: no normalized flow index, original immutable ledger and carry metadata retained.
    var db:OpaquePointer?;#expect(sqlite3_open(rig.repository.path,&db)==SQLITE_OK);defer{sqlite3_close(db)}
    let sql="BEGIN IMMEDIATE; DELETE FROM financial_flows; DELETE FROM report_state; DELETE FROM report_checkpoints; UPDATE account_state SET payload=json_remove(payload,'$.financialFlows','$.history.financialFlowOffset'); PRAGMA user_version=4; COMMIT;"
    #expect(sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK)
    let migrated=try AccountRepository(root:rig.root,mode:.online),loaded=try #require(try migrated.fullSnapshot()),migratedReport=try migrated.performance()
    #expect(loaded.cash==full.cash);#expect(loaded.fills.map(\.id)==full.fills.map(\.id));#expect(loaded.ledger.map(\.amount)==full.ledger.map(\.amount))
    #expect(loaded.financialFlows?.count==220);#expect(migratedReport.economicNet==report.economicNet)
    let older=try migrated.performance(from:1100,until:1200)
    #expect(older.cashFlows?["USD"]?["funding"] == (try Amount(-5)))
}
@Test func historicalContractNotionalDoesNotChangeWhenFutureRulesChange()async throws{
    let rig=try FlowRig(asset:.perpetual,multiplier:"10"),ctx=rig.context
    try await rig.engine.ingest(rig.quote(),now:1000,context:ctx);_=try await rig.engine.submit(rig.request(.buy,quantity:2),time:1000,context:ctx)
    try await rig.engine.ingest(rig.quote(bid:"110",ask:"111",time:1001),now:1001,context:ctx);_=try await rig.engine.submit(rig.request(.sell,quantity:2),time:1001,context:ctx)
    var rules=rig.instrument.rules;rules.multiplier=try Amount(100);rules.version="future-rules-only";try await rig.engine.updateRules(instrumentID:"FLOW",rules:rules,context:ctx)
    let report=try await rig.engine.performance(context:ctx)
    #expect(report.currencies["USD"]?.notional == (try Amount(4200)))
    #expect(report.currencies["USD"]?.notionalComplete==true)
    #expect(await rig.engine.snapshot().fills.allSatisfy{$0.multiplier == (try? Amount(10))})
}

@Test func retiredEpochCannotMutateRestoredAccountOrAcceptLateOrderCallbacks()async throws{
    let rig=try FlowRig(),old=rig.context
    try await rig.engine.ingest(rig.quote(),now:1000,context:old)
    let intent=try rig.request(.buy),before=await rig.engine.snapshot()
    try await rig.engine.retire(context:old)
    let newContext=AccountContext(mode:.online),replacement=try TradingEngine(context:newContext,repository:AccountRepository(root:rig.root,mode:.online),initial:before)
    await #expect(throws:TradeError.self){try await rig.engine.submit(intent,time:1000,context:old)}
    await #expect(throws:TradeError.self){try await rig.engine.toggleWatch("FLOW",context:old)}
    await #expect(throws:TradeError.self){try await replacement.submit(intent,time:1000,context:old)}
    #expect(await replacement.snapshot().cash==before.cash);#expect(await replacement.snapshot().fills.isEmpty)
    _=try await replacement.submit(intent,time:1000,context:newContext)
    #expect(await replacement.snapshot().positions["FLOW"]?.quantity == (try Amount(10)))
}
