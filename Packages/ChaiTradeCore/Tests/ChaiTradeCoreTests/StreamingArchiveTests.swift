import Foundation
import Testing
@testable import ChaiTradeCore

private struct StreamRig:Sendable{
    let root:URL
    let original:AccountRepository
    let snapshotRoot:URL
    init()throws{
        root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        original=try AccountRepository(root:root.appendingPathComponent("original"),mode:.online)
        var state=try TradingEngine.initial(mode:.online,capital:Amount(5000),time:1000)
        for n in 0..<50{state.journals.append(JournalEntry(id:"journal-\(n)",text:String(repeating:"A",count:32000),tags:"synthetic-streaming-archive",time:1000))}
        let instrument=state.instruments[0]
        state.quotes[instrument.id]=Quote(instrumentID:instrument.id,source:"synthetic-cache-that-must-not-export",time:1000,sequence:1000,last:.one,bids:[],asks:[])
        _=try original.save(state)
        snapshotRoot=root.appendingPathComponent("snapshot")
        try original.createArchiveSnapshot(at:snapshotRoot.appendingPathComponent("accounts/\(Mode.online.accountID)/account.sqlite"))
    }
    func output(_ name:String)->URL{root.appendingPathComponent(name)}
}
private func streamWord(_ value:Int)->Data{var n=UInt32(value).bigEndian;return withUnsafeBytes(of:&n){Data($0)}}
private func streamInt(_ data:Data,_ offset:Int)->Int{data[offset..<offset+4].reduce(0){($0<<8)|Int($1)}}
private func streamFrames(_ data:Data)->(headerEnd:Int,ranges:[Range<Int>]){
    let end=StreamingArchiveService.magic.count+4+streamInt(data,StreamingArchiveService.magic.count)
    var offset=end,ranges:[Range<Int>]=[]
    while offset<data.count{let next=offset+4+streamInt(data,offset);ranges.append(offset..<next);offset=next}
    return(end,ranges)
}
@Test(arguments:[false,true])
func streamingArchiveRoundtripPreservesJournalsCapitalAndExcludesACache(encrypted:Bool)throws{
    let r=try StreamRig(),url=r.output("roundtrip.chaitradearchive"),password=encrypted ? "streaming-password":nil
    try StreamingArchiveService.export(snapshotRoot:r.snapshotRoot,mode:.online,to:url,password:password,time:1000)
    #expect(try StreamingArchiveService.recognizes(url))
    let bytes=try Data(contentsOf:url),frames=streamFrames(bytes)
    #expect(frames.ranges.count>=3)
    let restored=try StreamingArchiveService.validate(url,stagingRoot:r.output("restore"),expectedMode:.online,password:password)
    #expect(try restored.state.cash["TWD"]==Amount(5000));#expect(restored.state.journals.count==50)
    #expect(restored.state.quotes.isEmpty && restored.state.consumed.isEmpty)
    #expect(try r.original.load()?.quotes.isEmpty==false)
    if encrypted{#expect(throws:(any Error).self){try StreamingArchiveService.validate(url,stagingRoot:r.output("wrong-password"),expectedMode:.online,password:"incorrect-password")}}
    #expect(throws:(any Error).self){try StreamingArchiveService.validate(url,stagingRoot:r.output("wrong-account"),expectedMode:.offline,password:password)}
}
@Test func streamingArchiveRejectsTruncationReorderDuplicateCorruptionAndTrailingBytes()throws{
    let r=try StreamRig(),url=r.output("valid.chaitradearchive")
    try StreamingArchiveService.export(snapshotRoot:r.snapshotRoot,mode:.online,to:url,password:nil,time:1000)
    let data=try Data(contentsOf:url),layout=streamFrames(data),a=layout.ranges[0],b=layout.ranges[1]
    var corrupt=data;corrupt[a.lowerBound+40]^=1
    let variants=[Data(data.dropLast(3)),Data(data.prefix(a.lowerBound))+Data(data[b])+Data(data[a])+Data(data.suffix(from:b.upperBound)),Data(data.prefix(a.upperBound))+Data(data[a])+Data(data.suffix(from:a.upperBound)),corrupt,data+Data([1])]
    for (n,bytes) in variants.enumerated(){
        let bad=r.output("bad-\(n)"),stage=r.output("bad-stage-\(n)");try bytes.write(to:bad)
        #expect(throws:(any Error).self){try StreamingArchiveService.validate(bad,stagingRoot:stage,expectedMode:.online,password:nil)}
        #expect(!FileManager.default.fileExists(atPath:stage.path));#expect(try r.original.load()?.cash["TWD"]==Amount(5000))
    }
}
@Test func streamingArchiveBoundsUntrustedExpansionBeforeAllocatingAndRejectsWrongTag()throws{
    let r=try StreamRig(),url=r.output("valid.chaitradearchive")
    try StreamingArchiveService.export(snapshotRoot:r.snapshotRoot,mode:.online,to:url,password:nil,time:1000)
    let data=try Data(contentsOf:url),layout=streamFrames(data),first=layout.ranges[0],body=Data(data[(first.lowerBound+4+28)..<first.upperBound]),length=streamInt(body,0)
    var meta=try #require(JSONSerialization.jsonObject(with:body[4..<4+length]) as? [String:Any]);meta["expandedBytes"]=1_048_577
    let encoded=try JSONSerialization.data(withJSONObject:meta,options:[.sortedKeys]),newBody=streamWord(encoded.count)+encoded+Data(body.dropFirst(4+length))
    let bomb=Data(data.prefix(first.lowerBound))+streamWord(newBody.count+28)+Data(repeating:0,count:28)+newBody+Data(data.suffix(from:first.upperBound))
    let bad=r.output("bomb");try bomb.write(to:bad)
    do{_=try StreamingArchiveService.validate(bad,stagingRoot:r.output("bomb-stage"),expectedMode:.online,password:nil);Issue.record("Expanded chunk bomb was accepted")}
    catch{#expect(error.localizedDescription.contains("展開大小"))}
    let encrypted=r.output("encrypted");try StreamingArchiveService.export(snapshotRoot:r.snapshotRoot,mode:.online,to:encrypted,password:"streaming-password",time:1000)
    var cipher=try Data(contentsOf:encrypted);let frame=streamFrames(cipher).ranges[0];cipher[frame.lowerBound+4+12]^=1
    let forged=r.output("wrong-tag");try cipher.write(to:forged)
    #expect(throws:(any Error).self){try StreamingArchiveService.validate(forged,stagingRoot:r.output("tag-stage"),expectedMode:.online,password:"streaming-password")}
}
@Test func canceledStreamingExportLeavesNoPartialOrDestinationAndKeepsOriginal()async throws{
    let r=try StreamRig(),url=r.output("cancelled.chaitradearchive")
    let task=Task.detached{try StreamingArchiveService.export(snapshotRoot:r.snapshotRoot,mode:.online,to:url,password:nil,time:1000,progress:{_ in withUnsafeCurrentTask{$0?.cancel()}})}
    await #expect(throws:CancellationError.self){try await task.value}
    #expect(!FileManager.default.fileExists(atPath:url.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath:r.root.path).allSatisfy{!$0.hasPrefix(".partial-")})
    #expect(try r.original.load()?.cash["TWD"]==Amount(5000));#expect(try r.original.load()?.journals.count==50)
}
