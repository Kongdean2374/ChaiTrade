import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

private func archiveFixture(capital:Int=1000,journals:Int=0)throws->(URL,AccountRepository){
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),repository=try AccountRepository(root:root,mode:.online)
    var state=try TradingEngine.initial(mode:.online,capital:Amount(capital),time:1000)
    for _ in 0..<journals{state.journals.append(JournalEntry(text:String(repeating:"A",count:32000),tags:"synthetic-archive-size",time:1000))}
    _=try repository.save(state);return (root,repository)
}
@Test func localRecoveryStagesOwnedCopyExcludesACacheAndPreservesOriginalPoint()throws{
    let (root,repository)=try archiveFixture()
    var state=try #require(try repository.load()),instrument=try #require(state.instruments.first)
    state.quotes[instrument.id]=Quote(instrumentID:instrument.id,source:"synthetic-recovery-fixture",time:1000,sequence:1000,last:try Amount(100),bids:[Level(try Amount(99),.one)],asks:[Level(try Amount(100),.one)])
    _=try repository.save(state)
    let point=root.appendingPathComponent("snapshots/point/account.sqlite")
    try repository.createArchiveSnapshot(at:point)
    let before=try ArchiveDigest.file(point)
    let staged=try LocalRecoveryService.stagePoint(point,stagingRoot:root.appendingPathComponent("staged"),mode:.online)
    #expect(staged.state.quotes.isEmpty && staged.state.consumed.isEmpty)
    #expect(staged.state.cash==state.cash)
    #expect(try ArchiveDigest.file(point)==before)
    #expect(try repository.load()?.quotes[instrument.id] != nil)
    #expect(throws:TradeError.self){try LocalRecoveryService.stagePoint(point,stagingRoot:root.appendingPathComponent("wrong-mode"),mode:.offline)}
}
@Test func fileMaintenanceDoesNotLoadFullStateAndRestoreRejectsEveryOldEpochMutation()async throws{
    let (root,repository)=try archiveFixture(),ctx=AccountContext(mode:.online)
    let engine=try TradingEngine(context:ctx,repository:repository,initial:#require(try repository.load())),url=root.appendingPathComponent("recovery/account.sqlite")
    let token=try await engine.beginFileMaintenance(snapshotAt:url,context:ctx)
    await #expect(throws:TradeError.self){try await engine.cashFlow(currency:"TWD",amount:.one,time:1001,context:ctx)}
    let verified=try SQLiteArchiveDatabase.verify(url,mode:.online)
    await #expect(throws:TradeError.self){try await engine.restoreVerifiedDatabase(verified,maintenanceToken:UUID(),context:ctx)}
    try await engine.restoreVerifiedDatabase(verified,maintenanceToken:token,context:ctx)
    await #expect(throws:TradeError.self){try await engine.cashFlow(currency:"TWD",amount:.one,time:1001,context:ctx)}
    try await engine.retire(context:ctx);try await engine.retire(context:ctx)
    #expect(try await engine.snapshot().cash["TWD"]==Amount(1000))
    let next=AccountContext(mode:.online),rebound=try TradingEngine(context:next,repository:repository,initial:#require(try repository.load()))
    try await rebound.cashFlow(currency:"TWD",amount:.one,time:1002,context:next)
    #expect(try await rebound.snapshot().cash["TWD"]==Amount(1001))
}
@Test func fileArchiveVerifiesRealLocalFillsArchivedFlowsAndAtomicReplacement()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.online),repository=try AccountRepository(root:root,mode:.online)
    var initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount(1000),time:1000)
    let btc=try #require(initial.instruments.first{$0.symbol=="BTC-USD"});initial.instruments=[btc]
    let engine=try TradingEngine(context:context,repository:repository,initial:initial)
    let quote=Quote(instrumentID:btc.id,source:"synthetic-archive-fixture",time:1000,sequence:1000,last:try Amount(100),bids:[Level(try Amount(99),try Amount(100))],asks:[Level(try Amount(100),try Amount(100))])
    try await engine.ingest(quote,now:1000,context:context)
    _=try await engine.submit(OrderRequest(instrumentID:btc.id,side:.buy,kind:.market,quantity:try Amount("0.1")),time:1000,context:context)
    _=try await engine.submit(OrderRequest(instrumentID:btc.id,side:.sell,kind:.market,quantity:try Amount("0.05")),time:1000,context:context)
    for n in 1...130{try await engine.cashFlow(currency:"USD",amount:.one,time:1000+Int64(n),eventID:"archive-extra-\(n)",context:context)}
    let full=try await engine.fullSnapshot(context:context),url=root.appendingPathComponent("archive/account.sqlite")
    #expect(full.fills.count==2);#expect((await engine.snapshot().history?.ledger ?? 0)>0)
    try repository.createArchiveSnapshot(at:url)
    let verified=try SQLiteArchiveDatabase.verify(url,mode:.online),(_,target)=try archiveFixture()
    let restored=try target.installArchiveSnapshot(verified)
    #expect(restored.cash==full.cash);#expect(restored.capitalBasis==full.capitalBasis)
    #expect(try AccountRepository.encode(target.fullSnapshot()?.ledger)==AccountRepository.encode(full.ledger))
    #expect(try target.performance().economicNet==repository.performance().economicNet)
}
@Test func consistentFileSnapshotIsVerifiedWithoutFullHistoryAndChangesNoOriginalRows()throws{
    let (root,repository)=try archiveFixture()
    let before=try #require(try repository.fullSnapshot()),url=root.appendingPathComponent("archive/account.sqlite")
    try repository.createArchiveSnapshot(at:url)
    let header=try FileHandle(forReadingFrom:url);defer{try? header.close()}
    let bytes=try #require(try header.read(upToCount:100))
    #expect(bytes.count==100 && bytes[18]==1 && bytes[19]==1)
    #expect(!FileManager.default.fileExists(atPath:url.path+"-wal"))
    #expect(!FileManager.default.fileExists(atPath:url.path+"-shm"))
    #expect(try repository.withArchiveConnection{try SQLiteArchiveDatabase.strings($0,"PRAGMA journal_mode")}==["wal"])
    let copy=try SQLiteArchiveDatabase.verify(url,mode:.online)
    #expect(copy.state.cash==before.cash);#expect(copy.state.capitalBasis==before.capitalBasis)
    #expect(try ArchiveDigest.file(url)==copy.digest)
    #expect(try AccountRepository.encode(repository.fullSnapshot())==AccountRepository.encode(before))
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(url,mode:.offline)}
    #expect(throws:TradeError.self){try repository.createArchiveSnapshot(at:url)}
}
@Test func archiveRejectsExtraTriggerAndTamperedCashBeforeAnyLiveAccountReplacement()throws{
    let (root,repository)=try archiveFixture(),url=root.appendingPathComponent("archive/account.sqlite")
    try repository.createArchiveSnapshot(at:url)
    var db:OpaquePointer?;#expect(sqlite3_open(url.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"CREATE TRIGGER unexpected AFTER INSERT ON events BEGIN DELETE FROM ledger; END",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(url,mode:.online)}
    #expect(sqlite3_open(url.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"DROP TRIGGER unexpected; UPDATE account_state SET payload=json_set(payload,'$.cash.TWD','999999')",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(url,mode:.online)}
    #expect(try repository.load()?.cash["TWD"]==Amount(1000))
}
@Test func interruptedSQLiteBackupRollsBackDestinationAndVerifiedFileCannotChangeAfterReview()throws{
    let (root,source)=try archiveFixture(capital:2000,journals:50),(_,target)=try archiveFixture(capital:1000)
    var steps=0
    #expect(throws:TradeError.self){
        try source.withArchiveConnection{from in try target.withArchiveConnection{to in try SQLiteArchiveDatabase.copy(source:from,target:to,interrupt:{steps+=1;if steps==2{throw TradeError.unavailable("synthetic mid-copy interruption")}})}}
    }
    #expect(steps==2);#expect(try target.load()?.cash["TWD"]==Amount(1000));#expect(try target.load()?.journals.isEmpty==true)
    let url=root.appendingPathComponent("verified/account.sqlite");try source.createArchiveSnapshot(at:url)
    let verified=try SQLiteArchiveDatabase.verify(url,mode:.online)
    let handle=try FileHandle(forWritingTo:url);try handle.seekToEnd();try handle.write(contentsOf:Data([0]));try handle.close()
    #expect(throws:TradeError.self){try target.installArchiveSnapshot(verified)}
    #expect(try target.load()?.cash["TWD"]==Amount(1000))
}

@Test func archiveRejectsFilledOrderWithoutCanonicalFillsAndHotOrderWithoutCanonicalRow() throws {
    func orderFixture(filled:Bool)throws->(URL,AccountRepository){
        let (root,repository)=try archiveFixture()
        var state=try #require(try repository.fullSnapshot())
        let instrument=try #require(state.instruments.first)
        let request=OrderRequest(instrumentID:instrument.id,side:.buy,kind:.market,quantity:.one)
        var order=Order(id:request.requestID,accountID:state.accountID,request:request,referencePrice:try Amount(100),createdAt:1000,updatedAt:1000,ruleVersion:"synthetic-archive-validation")
        if filled{order.status = .filled;order.filled = .one}
        state.orders[order.id]=order
        _=try repository.save(state)
        return (root,repository)
    }
    let (firstRoot,first)=try orderFixture(filled:true),firstURL=firstRoot.appendingPathComponent("copy/account.sqlite")
    try first.createArchiveSnapshot(at:firstURL)
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(firstURL,mode:.online)}
    let (secondRoot,second)=try orderFixture(filled:false),secondURL=secondRoot.appendingPathComponent("copy/account.sqlite")
    try second.createArchiveSnapshot(at:secondURL)
    var db:OpaquePointer?;#expect(sqlite3_open(secondURL.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"DELETE FROM orders",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(secondURL,mode:.online)}
    #expect(try first.load()?.orders.count==1);#expect(try second.load()?.orders.count==1)
}
