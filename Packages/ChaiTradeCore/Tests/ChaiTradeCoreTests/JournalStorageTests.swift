import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

private let journalPNG=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII=")!

@Test func journalHistoryPagesWithoutAttachmentsAndLoadsEveryOriginalOnDemand()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let repo=try AccountRepository(root:root,mode:.offline),context=AccountContext(mode:.offline)
    var initial=try TradingEngine.initial(mode:.offline,capital:Amount(1000),time:1000)
    for n in 0..<125{var journal=JournalEntry(id:"journal-\(n)",text:"原始中文日誌 \(n)",tags:"strategy",time:Int64(1000+n));journal.screenshot=journalPNG;initial.journals.append(journal)}
    let engine=try TradingEngine(context:context,repository:repo,initial:initial),hot=await engine.snapshot()
    #expect(hot.journals.count==20 && hot.history?.journalCount==125)
    #expect(hot.journals.allSatisfy{$0.screenshot==nil && $0.screenshotSHA256==BackupService.digest(journalPNG)})
    var cursor:Int64?,ids:[String]=[]
    repeat{let page=try await engine.journalPage(limit:17,before:cursor,context:context);if page.isEmpty{break};#expect(page.allSatisfy{$0.entry.screenshot==nil});ids+=page.map(\.id);cursor=page.last?.cursor}while true
    #expect(ids.count==125 && Set(ids).count==125)
    for n in [0,19,104,124]{let entry=try await engine.journal(id:"journal-\(n)",context:context);#expect(entry?.screenshot==journalPNG && entry?.text=="原始中文日誌 \(n)")}
    var edited=try #require(try await engine.journal(id:"journal-0",context:context));edited.text="修改舊日誌，附件保留"
    try await engine.recordJournal(edited,context:context);try await engine.recordJournal(edited,context:context)
    #expect(await engine.snapshot().history?.journalCount==125)
    #expect(try await engine.journal(id:"journal-0",context:context)?.text==edited.text)
    let full=try await engine.fullSnapshot(context:context);#expect(full.journals.count==125 && full.journals.allSatisfy{$0.screenshot==journalPNG})
    let restored=try BackupService.validate(BackupService.export(full,password:nil,time:1200),expectedMode:.offline,password:nil)
    #expect(restored.journals.count==125 && restored.journals.allSatisfy{$0.screenshot==journalPNG})
    #expect(throws:TradeError.self){try BackupService.export(hot,password:nil,time:1200)}
    let reopened=try AccountRepository(root:root,mode:.offline);#expect(try reopened.load()?.history?.journalCount==125);#expect(try reopened.journal(id:"journal-0")?.screenshot==journalPNG)
}

@Test func schemaSixJournalsMigrateAdditivelyAndInvalidAttachmentRollsBack()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    var original=try TradingEngine.initial(mode:.online,capital:Amount(2500),time:1000)
    var entry=JournalEntry(id:"old-journal",text:"遷移前日誌",tags:"old",time:1000);entry.screenshot=journalPNG;original.journals=[entry]
    let path=root.appendingPathComponent("accounts/\(Mode.online.accountID)/account.sqlite").path
    do{let repo=try AccountRepository(root:root,mode:.online);_=try repo.save(original)}
    var database:OpaquePointer?;#expect(sqlite3_open(path,&database)==SQLITE_OK)
    let raw=String(decoding:try AccountRepository.encode(original),as:UTF8.self).replacingOccurrences(of:"'",with:"''")
    #expect(sqlite3_exec(database,"PRAGMA foreign_keys=OFF; DELETE FROM journal_images; DROP TABLE journal_images; DROP TABLE journal_entries; UPDATE account_state SET payload='\(raw)'; PRAGMA user_version=6",nil,nil,nil)==SQLITE_OK);sqlite3_close(database)
    let migrated=try AccountRepository(root:root,mode:.online),hot=try #require(try migrated.load())
    #expect(hot.cash==original.cash && hot.ledger.map(\.eventID)==original.ledger.map(\.eventID));#expect(hot.history?.journalCount==1 && hot.journals.first?.screenshot==nil)
    #expect(try migrated.journal(id:entry.id)?.screenshot==journalPNG)
    var invalid=hot;invalid.journals[0].screenshotSHA256=String(repeating:"a",count:64)
    #expect(throws:TradeError.self){try migrated.save(invalid)}
    #expect(try migrated.journal(id:entry.id)?.screenshot==journalPNG);#expect(try AccountRepository.encode(migrated.load())==AccountRepository.encode(hot))
}
