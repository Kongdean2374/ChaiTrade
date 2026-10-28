import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

@Test func archivedDividendsRetainEveryPendingObligationAndPayExactlyOnceAcrossRestore()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let repository=try AccountRepository(root:root,mode:.online),context=AccountContext(mode:.online)
    let instrument=Instrument(id:"LIFE",symbol:"LIFE",name:"合成分頁驗證商品",asset:.usStock,currency:"USD",rules:RulePack(tick:try Amount("0.01"),quantityStep:.one),initialPrice:try Amount(100))
    var initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount(10000),time:1000);initial.instruments=[instrument]
    let engine=try TradingEngine(context:context,repository:repository,initial:initial)
    try await engine.ingest(Quote(instrumentID:instrument.id,source:"synthetic-lifecycle-test",time:1000,sequence:1,last:try Amount(100),bids:[Level(try Amount(99),try Amount(1000))],asks:[Level(try Amount(100),try Amount(1000))]),now:1000,context:context)
    _=try await engine.submit(OrderRequest(instrumentID:instrument.id,side:.buy,kind:.market,quantity:try Amount(10)),time:1000,context:context)
    let baseline=try #require(await engine.snapshot().cash["USD"])
    for n in 1...240{try await engine.corporateAction(CorporateAction(id:"dividend-\(n)",instrumentID:instrument.id,kind:.dividend,time:1000+Int64(n),cashPerUnit:.one,paymentTime:2000,source:"合成股息測試"),context:context)}
    let pending=await engine.snapshot()
    #expect(pending.lifecycle?.settlements.count==240);#expect(pending.lifecycle?.actions.count==100)
    #expect(pending.history?.lifecycleCounts==["settlements":240,"carry":0,"actions":240]);#expect(pending.cash["USD"]==baseline)
    try await engine.processDueEvents(time:2000,context:context)
    let hot=await engine.snapshot(),full=try await engine.fullSnapshot(context:context)
    #expect(hot.lifecycle?.settlements.count==100);#expect(full.lifecycle?.settlements.count==240 && full.lifecycle?.actions.count==240)
    #expect(try full.cash["USD"]==baseline+Amount(2400))
    var cursor:Int64?,seen=Set<String>()
    repeat{
        let page=try await engine.lifecyclePage(kind:.settlements,limit:20,before:cursor,context:context)
        for row in page{#expect(seen.insert(row.id).inserted)}
        cursor=page.count==20 ? page.last?.cursor:nil
    }while cursor != nil
    #expect(seen.count==240)
    let next=AccountContext(mode:.online),restarted=try TradingEngine(context:next,repository:repository,initial:#require(try repository.load()))
    try await restarted.corporateAction(CorporateAction(id:"dividend-1",instrumentID:instrument.id,kind:.dividend,time:3000,cashPerUnit:try Amount(999),paymentTime:4000,source:"不得重複入帳"),context:next)
    try await restarted.processDueEvents(time:3000,context:next)
    #expect(await restarted.snapshot().cash==full.cash)
    let backup=try BackupService.export(full,password:nil,time:3000),restored=try BackupService.validate(backup,expectedMode:.online,password:nil)
    #expect(restored.lifecycle?.settlements.count==240 && restored.lifecycle?.actions.count==240)
    let other=try AccountRepository(root:root.appendingPathComponent("restore"),mode:.online),restoreContext=AccountContext(mode:.online)
    let restoredEngine=try TradingEngine(context:restoreContext,repository:other,initial:restored)
    try await restoredEngine.processDueEvents(time:4000,context:restoreContext)
    #expect(await restoredEngine.snapshot().cash==full.cash)
    await #expect(throws:TradeError.self){try await restoredEngine.lifecyclePage(kind:.actions,context:AccountContext(mode:.offline))}
    #expect(try repository.lifecyclePage(kind:.actions,limit:20).count==20)
    var forged=hot;forged.lifecycle!.settlements[0].completedAt=nil
    #expect(throws:TradeError.self){try repository.save(forged)}
    #expect(throws:TradeError.self){try repository.save(hot,replacing:true)}
    let copy=root.appendingPathComponent("copy/account.sqlite");try repository.createArchiveSnapshot(at:copy)
    _=try SQLiteArchiveDatabase.verify(copy,mode:.online)
    var db:OpaquePointer?;#expect(sqlite3_open(copy.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"UPDATE lifecycle_history SET ordinal=9999 WHERE kind='actions' AND ordinal=1",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(copy,mode:.online)}
    #expect(try repository.load()?.cash==full.cash)
}

@Test func schemaEightLifecycleMigrationAndInterruptedMigrationPreserveOriginalHistory()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    var original=try TradingEngine.initial(mode:.online,capital:Amount(1000),time:1000),life=LifecycleState()
    let id=original.instruments[0].id
    for n in 0..<240{
        life.actions.append(CorporateAction(id:"action-\(n)",instrumentID:id,kind:.halt,time:1000+Int64(n),source:"合成舊版歷史"))
        life.carry.append(CarryEvent(id:"carry-\(n)",instrumentID:id,time:1000+Int64(n),rate:.zero,mark:.one,amount:.zero,kind:"funding",source:"合成舊版歷史"))
        life.settlements.append(SettlementEvent(id:"settlement-\(n)",currency:"TWD",due:1000+Int64(n),receivable:.zero,payable:.zero,completedAt:2000))
    };original.lifecycle=life
    let path=root.appendingPathComponent("accounts/\(Mode.online.accountID)/account.sqlite").path
    do{let repository=try AccountRepository(root:root,mode:.online);_=try repository.save(original)}
    let raw=String(decoding:try AccountRepository.encode(original),as:UTF8.self).replacingOccurrences(of:"'",with:"''")
    var db:OpaquePointer?;#expect(sqlite3_open(path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"DELETE FROM lifecycle_history; UPDATE account_state SET payload='\(raw)'; PRAGMA user_version=8; CREATE TRIGGER interrupt_lifecycle BEFORE INSERT ON lifecycle_history BEGIN SELECT RAISE(ABORT,'synthetic migration interruption'); END",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    #expect(throws:TradeError.self){try AccountRepository(root:root,mode:.online)}
    let reader=try AccountRepository.archiveReader(URL(fileURLWithPath:path),mode:.online)
    #expect(try reader.load()?.lifecycle?.carry.count==240)
    #expect(try reader.withArchiveConnection{try SQLiteArchiveDatabase.strings($0,"PRAGMA user_version")}==["8"])
    #expect(sqlite3_open(path,&db)==SQLITE_OK);#expect(sqlite3_exec(db,"DROP TRIGGER interrupt_lifecycle; DROP TABLE lifecycle_history",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    _=try SQLiteArchiveDatabase.verify(URL(fileURLWithPath:path),mode:.online,expectedVersion:8)
    let migrated=try AccountRepository(root:root,mode:.online),hot=try #require(try migrated.load()),full=try #require(try migrated.fullSnapshot())
    #expect(hot.lifecycle?.carry.count==100 && hot.lifecycle?.actions.count==100 && hot.lifecycle?.settlements.count==100)
    #expect(throws:TradeError.self){try BackupService.export(hot,password:nil,time:3000)}
    #expect(full.lifecycle?.carry.count==240 && full.lifecycle?.actions.count==240 && full.lifecycle?.settlements.count==240)
    #expect(full.cash==original.cash);#expect(try AccountRepository.encode(full.lifecycle)==AccountRepository.encode(original.lifecycle))
    let point=root.appendingPathComponent("point/account.sqlite");try migrated.createArchiveSnapshot(at:point);_=try SQLiteArchiveDatabase.verify(point,mode:.online,expectedVersion:9)
    var altered=hot;altered.lifecycle!.carry[0].amount = .one
    #expect(throws:TradeError.self){try migrated.save(altered)}
    #expect(try migrated.fullSnapshot()?.cash==original.cash)
}
