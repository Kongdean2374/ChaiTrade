import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

private struct DataFileRig{
    let root:URL,repository:AccountRepository,engine:TradingEngine,context:AccountContext,instrument:Instrument
    init(mode:Mode) throws{
        root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);context=AccountContext(mode:mode)
        var initial=try TradingEngine.initial(mode:mode,baseCurrency:"USD",capital:Amount(1000000),time:1000)
        instrument=try #require(initial.instruments.first{$0.symbol=="BTC-USD"});initial.instruments=[instrument]
        if mode == .offline{initial.simulation!.newsFrom=nil;initial.simulation!.newsAccountingFrom=nil}
        repository=try AccountRepository(root:root.appendingPathComponent("live"),mode:mode);engine=try TradingEngine(context:context,repository:repository,initial:initial)
    }
    func snapshot()async throws->URL{
        let stage=root.appendingPathComponent("snapshot-"+UUID().uuidString)
        let token=try await engine.beginFileMaintenance(snapshotAt:stage.appendingPathComponent("accounts/\(context.accountID)/account.sqlite"),context:context);try await engine.endMaintenance(token:token,context:context);return stage
    }
}

@Test(arguments:Mode.allCases)
func streamedJSONAndCSVRetainCompleteArchivedRecordsImagesAndOfflineImpacts(mode:Mode)async throws{
    let r=try DataFileRig(mode:mode);defer{try? FileManager.default.removeItem(at:r.root)}
    if mode == .online{try await r.engine.ingest(Quote(instrumentID:r.instrument.id,source:"synthetic-data-export",time:1000,sequence:1,last:try Amount(100),bids:[Level(try Amount(99),try Amount(100))],asks:[Level(try Amount(100),try Amount(100))]),now:1000,context:r.context)}
    else{try await r.engine.initializeQuotes(context:r.context)}
    let start=await r.engine.snapshot().simulation?.time ?? 1000
    _=try await r.engine.submit(OrderRequest(instrumentID:r.instrument.id,side:.buy,kind:.market,quantity:try Amount("0.01")),time:start,context:r.context)
    if mode == .offline{while await r.engine.snapshot().simulation!.time<start+600{_=try await r.engine.advance(to:start+600,context:r.context)}}
    let now=await r.engine.snapshot().simulation?.time ?? 1000
    let png=try #require(Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII="))
    for n in 0..<120{
        try await r.engine.cashFlow(currency:"USD",amount:.one,time:now,eventID:"data-flow-\(n)",context:r.context)
        var entry=JournalEntry(id:"data-journal-\(n)",text:"合成匯出中文、逗號,與\"引號\"\n第二行 \(n)",tags:"synthetic-export",time:now)
        if n%19==0{entry.screenshot=png};try await r.engine.recordJournal(entry,context:r.context)
        try await r.engine.corporateAction(CorporateAction(id:"data-dividend-\(n)",instrumentID:r.instrument.id,kind:.dividend,time:now,cashPerUnit:.one,paymentTime:now,source:"合成檔案匯出測試"),context:r.context)
    }
    try await r.engine.processDueEvents(time:now,context:r.context)
    let hot=await r.engine.snapshot();#expect(hot.journals.count==20 && hot.lifecycle?.actions.count==100 && hot.lifecycle?.settlements.count==100)
    var expected=try await r.engine.fullSnapshot(context:r.context)
    if mode == .offline{#expect(hot.simulation?.impactGroups?.isEmpty==true);#expect(expected.simulation?.impactGroups?.isEmpty==false)}
    else{expected.quotes=[:];expected.consumed=[:]}
    let stage=try await r.snapshot(),json=r.root.appendingPathComponent("complete.json")
    try AccountDataFileService.export(snapshotRoot:stage,mode:mode,format:.json,to:json,time:now)
    let decoded=try JSONDecoder().decode(AccountState.self,from:Data(contentsOf:json))
    #expect(try AccountRepository.encode(decoded)==AccountRepository.encode(expected))
    #expect(decoded.journals.count==120 && decoded.journals.filter{$0.screenshot != nil}.count==7)
    #expect(decoded.lifecycle?.actions.count==120 && decoded.lifecycle?.settlements.count==120)
    #expect(decoded.history==nil)
    let fills=r.root.appendingPathComponent("fills.csv"),ledger=r.root.appendingPathComponent("ledger.csv"),orders=r.root.appendingPathComponent("orders.csv")
    for (format,url) in [(AccountDataFormat.fills,fills),(.ledger,ledger),(.orders,orders)]{try AccountDataFileService.export(snapshotRoot:stage,mode:mode,format:format,to:url,time:now)}
    #expect(try String(contentsOf:fills,encoding:.utf8)==Analytics.fillsCSV(expected,time:now))
    #expect(try String(contentsOf:ledger,encoding:.utf8)==Analytics.ledgerCSV(expected,time:now))
    #expect(try String(contentsOf:orders,encoding:.utf8)==Analytics.ordersCSV(expected,time:now))
    #expect(try AccountRepository.encode(await r.engine.fullSnapshot(context:r.context).journals)==AccountRepository.encode(decoded.journals))
    #expect(await r.engine.snapshot().cash==expected.cash)
}

@Test func dataFileCancelLimitAndDamagedArchivedRowsLeaveNoCompletedOrPartialFile()async throws{
    let r=try DataFileRig(mode:.online);defer{try? FileManager.default.removeItem(at:r.root)}
    for n in 0..<35{try await r.engine.recordJournal(JournalEntry(id:"data-\(n)",text:String(repeating:"synthetic",count:1000),tags:"fixture",time:1000),context:r.context)}
    let stage=try await r.snapshot(),cancelled=r.root.appendingPathComponent("cancelled.json")
    let work=Task.detached{try AccountDataFileService.export(snapshotRoot:stage,mode:.online,format:.json,to:cancelled,time:1000,progress:{value in if value<1{withUnsafeCurrentTask{$0?.cancel()}}})}
    await #expect(throws:CancellationError.self){try await work.value}
    #expect(!FileManager.default.fileExists(atPath:cancelled.path))
    let limited=r.root.appendingPathComponent("limited.json")
    #expect(throws:TradeError.self){try AccountDataFileService.export(snapshotRoot:stage,mode:.online,format:.json,to:limited,time:1000,maximumBytes:100)}
    #expect(!FileManager.default.fileExists(atPath:limited.path))
    let existing=r.root.appendingPathComponent("existing.json");try Data([1,2,3]).write(to:existing)
    #expect(throws:TradeError.self){try AccountDataFileService.export(snapshotRoot:stage,mode:.online,format:.json,to:existing,time:1000)}
    #expect(try Data(contentsOf:existing)==Data([1,2,3]))
    let database=stage.appendingPathComponent("accounts/\(Mode.online.accountID)/account.sqlite")
    var db:OpaquePointer?;#expect(sqlite3_open(database.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"UPDATE journal_entries SET payload=json_set(payload,'$.instrumentID','unknown') WHERE id='data-0'",nil,nil,nil)==SQLITE_OK);sqlite3_close(db)
    let damaged=r.root.appendingPathComponent("damaged.json")
    #expect(throws:TradeError.self){try AccountDataFileService.export(snapshotRoot:stage,mode:.online,format:.json,to:damaged,time:1000)}
    #expect(!FileManager.default.fileExists(atPath:damaged.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath:r.root.path).allSatisfy{!$0.hasPrefix(".partial-")})
    #expect(try r.repository.fullSnapshot()?.journals.count==35)
}
