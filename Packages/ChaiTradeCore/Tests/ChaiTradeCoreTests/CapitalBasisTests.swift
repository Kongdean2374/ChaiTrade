import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

private struct CapitalRig{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let context=AccountContext(mode:.online)
    let repository:AccountRepository
    let engine:TradingEngine
    init()throws{
        repository=try AccountRepository(root:root,mode:.online)
        engine=try TradingEngine(context:context,repository:repository,initial:TradingEngine.initial(mode:.online,capital:Amount(1000),time:1000))
    }
    func rate(_ value:Int,time:Int64)async throws{try await engine.setFX(FXRate(currency:"USD",base:"TWD",rate:Amount(value),time:time,source:"合成歷史匯率驗證",kind:.userDefined),context:context)}
}
@Test func historicalCapitalBasisPreservesFXGainAfterForeignCapitalIsFullyWithdrawn()async throws{
    let r=try CapitalRig(),ctx=r.context
    try await r.rate(30,time:1001);try await r.engine.cashFlow(currency:"USD",amount:Amount(100),time:1002,eventID:"foreign-in",context:ctx)
    #expect(try Analytics.valuation(await r.engine.snapshot(),now:1002).tradingPnL == .zero)
    try await r.rate(32,time:1003)
    #expect(try Analytics.valuation(await r.engine.snapshot(),now:1003).tradingPnL == Amount(200))
    try await r.engine.cashFlow(currency:"USD",amount:Amount(-100),time:1004,eventID:"foreign-out",context:ctx)
    try await r.engine.cashFlow(currency:"USD",amount:Amount(-100),time:1004,eventID:"foreign-out",context:ctx)
    let full=try await r.engine.fullSnapshot(context:ctx),value=try Analytics.valuation(full,now:200000)
    #expect(full.cash["USD"] == .zero);#expect(value.complete);#expect(try value.tradingPnL==Amount(200));#expect(value.performanceMissing.isEmpty)
    #expect(try full.capitalBasis?.knownBase==Amount(800))
    let event=try #require(full.events.first{$0.id=="foreign-in"})
    #expect(try event.capitalFlow?.baseAmount==Amount(3000));#expect(try event.capitalFlow?.rate?.rate==Amount(30))
    let restored=try BackupService.validate(BackupService.export(full,password:"basis-password",time:1005),expectedMode:.online,password:"basis-password")
    #expect(restored.capitalBasis==full.capitalBasis);#expect(try Analytics.valuation(restored,now:200000).tradingPnL==Amount(200))
}
@Test func missingHistoricalFXIsNotBackfilledByALaterRateAndTamperedBasisIsRejected()async throws{
    let r=try CapitalRig(),ctx=r.context
    try await r.engine.cashFlow(currency:"USD",amount:Amount(100),time:1001,context:ctx)
    try await r.rate(30,time:1002)
    var full=try await r.engine.fullSnapshot(context:ctx)
    let value=try Analytics.valuation(full,now:1002)
    #expect(value.complete);#expect(value.tradingPnL==nil);#expect(!value.performanceMissing.isEmpty);#expect(full.capitalBasis?.unvaluedCount==1)
    full.capitalBasis!.knownBase=try Amount(4000)
    #expect(throws:TradeError.self){try BackupService.export(full,password:nil,time:1002)}
}
@Test func legacyForeignRoundtripWithZeroNetFlowRetainsAnExplicitHistoricalGap()async throws{
    let r=try CapitalRig(),ctx=r.context
    try await r.rate(30,time:1001);try await r.engine.cashFlow(currency:"USD",amount:Amount(100),time:1002,context:ctx)
    try await r.rate(32,time:1003);try await r.engine.cashFlow(currency:"USD",amount:Amount(-100),time:1004,context:ctx)
    var old=try await r.engine.fullSnapshot(context:ctx);old.capitalBasis=nil
    for n in old.events.indices{old.events[n].capitalFlow=nil}
    let legacy=try BackupService.validate(BackupService.export(old,password:nil,time:1005),expectedMode:.online,password:nil)
    #expect(legacy.cash==old.cash);#expect(legacy.netFlows["USD"] == .zero);#expect(legacy.capitalBasis?.unvaluedCount==2)
    let value=try Analytics.valuation(legacy,now:200000)
    #expect(value.complete);#expect(value.tradingPnL==nil)
}
@Test func schemaFiveArchivedCapitalMigrationIsAtomicAndDoesNotChangeLedgerOrCash()async throws{
    let r=try CapitalRig(),ctx=r.context
    for n in 1...140{try await r.engine.cashFlow(currency:"TWD",amount:.one,time:1000+Int64(n),eventID:"extra-\(n)",context:ctx)}
    let before=try await r.engine.fullSnapshot(context:ctx)
    var db:OpaquePointer?;#expect(sqlite3_open(r.repository.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"UPDATE account_state SET payload=json_remove(payload,'$.capitalBasis'); PRAGMA user_version=5",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    let migrated=try AccountRepository(root:r.root,mode:.online),hot=try #require(try migrated.load()),full=try #require(try migrated.fullSnapshot())
    #expect((hot.history?.ledger ?? 0)>0);#expect(try hot.capitalBasis?.knownBase==Amount(1140));#expect(full.cash==before.cash)
    #expect(try AccountRepository.encode(full.ledger)==AccountRepository.encode(before.ledger));#expect(try AccountRepository.encode(full.events)==AccountRepository.encode(before.events))
    #expect(try Analytics.valuation(hot,now:2000).tradingPnL == .zero)
}
