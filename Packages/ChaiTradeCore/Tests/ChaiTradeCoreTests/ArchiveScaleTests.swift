import Foundation
import Testing
import CZlib
#if canImport(Darwin)
import Darwin
#endif
@testable import ChaiTradeCore

private func residentPeakBytes()->Int64{
    #if canImport(Darwin)
    var usage=rusage();guard getrusage(RUSAGE_SELF,&usage)==0 else{return 0};return Int64(usage.ru_maxrss)
    #else
    guard let text=try? String(contentsOfFile:"/proc/self/status",encoding:.utf8),let line=text.split(separator:"\n").first(where:{$0.hasPrefix("VmHWM:")}),let number=Int64(line.split(whereSeparator:{$0==" " || $0=="\t"})[1]) else{return 0};return number*1024
    #endif
}
private func scalePNG()->Data{
    let base=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII=")!
    // A valid private ancillary chunk creates a reproducible, poorly compressible image fixture.
    var payload=Data(count:1_800_000),seed:UInt64=0x1d25e31d99a0557
    payload.withUnsafeMutableBytes{buffer in
        for n in stride(from:0,to:buffer.count,by:8){seed ^= seed<<13;seed ^= seed>>7;seed ^= seed<<17;buffer.storeBytes(of:seed,toByteOffset:n,as:UInt64.self)}
    }
    func word(_ n:UInt32)->Data{var big=n.bigEndian;return withUnsafeBytes(of:&big){Data($0)}}
    var chunk=Data("npAd".utf8);chunk.append(payload)
    let checksum=chunk.withUnsafeBytes{crc32(0,$0.bindMemory(to:UInt8.self).baseAddress,uInt(chunk.count))}
    return Data(base.dropLast(12))+word(UInt32(payload.count))+chunk+word(UInt32(checksum))+Data(base.suffix(12))
}

private func verifyJSONImagesOneRecordAtATime(_ url:URL,expectedHash:String)throws->Int{
    let input=try FileHandle(forReadingFrom:url);defer{try? input.close()}
    var buffer=Data(),seen=Set<String>()
    func inspect(_ bytes:Data)throws{
        var line=bytes;if line.last==44{line.removeLast()}
        guard line.first==123,let entry=try? JSONDecoder().decode(JournalEntry.self,from:line),entry.id.hasPrefix("scale-") else{return}
        try #require(seen.insert(entry.id).inserted);try #require(entry.screenshot.map(BackupService.digest)==expectedHash)
    }
    while let chunk=try ArchiveMemory.read(input,upToCount:1_048_576),!chunk.isEmpty{
        buffer.append(chunk)
        while let end=buffer.firstIndex(of:10){try ArchiveMemory.scoped{try inspect(Data(buffer[..<end]))};buffer.removeSubrange(...end)}
        try #require(buffer.count<4_000_000)
    }
    if !buffer.isEmpty{try ArchiveMemory.scoped{try inspect(buffer)}}
    try #require(seen==Set((0..<320).map{"scale-\($0)"}));return seen.count
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["CHAI_ARCHIVE_SCALE"]=="1"))
func archiveOver512MBPreservesEveryAttachmentWithBoundedWorkingMemory()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("archive-scale-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let repository=try AccountRepository(root:root.appendingPathComponent("live"),mode:.online),context=AccountContext(mode:.online)
    let initial=try TradingEngine.initial(mode:.online,capital:Amount(2500),time:1000),engine=try TradingEngine(context:context,repository:repository,initial:initial)
    let image=scalePNG(),imageHash=BackupService.digest(image),clock=ContinuousClock(),started=clock.now
    for n in 0..<320{
        var entry=JournalEntry(id:"scale-\(n)",text:"大型歷史原始日誌 \(n)",tags:"synthetic-scale",time:Int64(1000+n));entry.screenshot=image
        try await engine.recordJournal(entry,context:context)
    }
    let hot=await engine.snapshot();try #require(hot.history?.journalCount==320 && hot.journals.count==20 && hot.journals.allSatisfy{$0.screenshot==nil})
    let snapshot=root.appendingPathComponent("snapshot"),database=snapshot.appendingPathComponent("accounts/\(Mode.online.accountID)/account.sqlite")
    let token=try await engine.beginFileMaintenance(snapshotAt:database,context:context);try await engine.endMaintenance(token:token,context:context)
    let size=try #require(try FileManager.default.attributesOfItem(atPath:database.path)[.size] as? NSNumber).int64Value
    try #require(size>512_000_000)
    var legacyRejectedBeforeMaterializing=false
    do{_=try repository.fullSnapshot(maximumExpandedBytes:BackupService.legacyExpandedLimit)}catch{legacyRejectedBeforeMaterializing=error.localizedDescription.contains("完整檔案封存")}
    try #require(legacyRejectedBeforeMaterializing)
    let baseline=residentPeakBytes(),archive=root.appendingPathComponent("complete.chaitradearchive")
    try StreamingArchiveService.export(snapshotRoot:snapshot,mode:.online,to:archive,password:"large-file-password",time:1500)
    let stage=root.appendingPathComponent("restored"),verified=try StreamingArchiveService.validate(archive,stagingRoot:stage,expectedMode:.online,password:"large-file-password")
    try #require(verified.state.history?.journalCount==320 && verified.state.cash==initial.cash && verified.state.ledger.map(\.eventID)==initial.ledger.map(\.eventID))
    let restored=try AccountRepository(root:stage,mode:.online)
    var cursor:Int64?,count=0
    repeat{
        let page=try restored.journalPage(limit:31,before:cursor);if page.isEmpty{break}
        for row in page{let original=try #require(try restored.journal(id:row.id));try #require(original.screenshot.map(BackupService.digest)==imageHash);count+=1}
        cursor=page.last?.cursor
    }while true
    try #require(count==320)
    let jsonFile=root.appendingPathComponent("complete.json")
    try AccountDataFileService.export(snapshotRoot:snapshot,mode:.online,format:.json,to:jsonFile,time:1500)
    let jsonBytes=try #require(try FileManager.default.attributesOfItem(atPath:jsonFile.path)[.size] as? NSNumber).int64Value
    try #require(jsonBytes>512_000_000)
    let jsonImages=try verifyJSONImagesOneRecordAtATime(jsonFile,expectedHash:imageHash)
    let peak=residentPeakBytes();let memoryPass=baseline>0 && peak>0 && peak-baseline<128*1024*1024
    let cancelled=root.appendingPathComponent("cancelled.chaitradearchive")
    let work=Task.detached{try StreamingArchiveService.export(snapshotRoot:snapshot,mode:.online,to:cancelled,password:nil,time:1500,progress:{_ in withUnsafeCurrentTask{$0?.cancel()}})}
    var cancelledCorrectly=false
    do{try await work.value}catch is CancellationError{cancelledCorrectly=true}
    try #require(cancelledCorrectly)
    try #require(!FileManager.default.fileExists(atPath:cancelled.path));try #require(try repository.journal(id:"scale-0")?.screenshot==image && repository.load()?.cash==initial.cash)
    let report:[String:Any]=["databaseBytes":size,"archiveBytes":try FileManager.default.attributesOfItem(atPath:archive.path)[.size] as Any,"journals":count,"jsonBytes":jsonBytes,"jsonImagesVerified":jsonImages,"hotJournals":hot.journals.count,"baselinePeakBytes":baseline,"peakBytes":peak,"additionalPeakBytes":peak-baseline,"elapsedSeconds":Double(started.duration(to:clock.now).components.seconds),"passed":memoryPass,"note":"Synthetic encrypted SQLite/PNG archive plus complete streamed JSON; not iPhone memory, launch or UI performance acceptance"]
    let json=try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]);print("ARCHIVE_SCALE_METRICS",String(decoding:json,as:UTF8.self))
    if let directory=ProcessInfo.processInfo.environment["CHAI_REPORT_DIR"]{try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true);try json.write(to:URL(fileURLWithPath:directory).appendingPathComponent("archive-scale-metrics.json"),options:.atomic)}
    try #require(memoryPass)
}
