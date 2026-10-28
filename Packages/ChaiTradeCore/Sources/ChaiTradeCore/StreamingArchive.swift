import Foundation

public struct ArchiveLimits:Sendable{
    public var maximumExpandedBytes:Int64
    public var maximumArchiveBytes:Int64
    public init(maximumExpandedBytes:Int64=16*1024*1024*1024,maximumArchiveBytes:Int64=24*1024*1024*1024){self.maximumExpandedBytes=maximumExpandedBytes;self.maximumArchiveBytes=maximumArchiveBytes}
}
struct ArchiveFileHeader:Codable{
    var version=1
    var mode:Mode
    var databaseSchema=8
    var expandedBytes:Int64
    var chunkBytes=1_048_576
    var algorithm:String
    var iterations:Int
    var salt:Data
    var createdAt:Int64
}
private struct ArchiveFrame:Codable{
    var index:Int
    var expandedBytes:Int
    var previous:String
    var header:String
    var isFinal:Bool
    var fileDigest:String?
}
/// A distinct bounded-memory format; legacy JSON backup limits and compatibility stay unchanged.
public enum StreamingArchiveService{
    static let magic=Data("CHAIFILE1\n".utf8)
    private static let maximumFrame=1_100_000
    private static func word(_ value:UInt32)->Data{var big=value.bigEndian;return withUnsafeBytes(of:&big){Data($0)}}
    private static func integer(_ bytes:Data)throws->Int{guard bytes.count==4 else{throw TradeError.corrupt("封存長度遺失")};return bytes.reduce(0){($0<<8)|Int($1)}}
    private static func read(_ handle:FileHandle,count:Int)throws->Data{
        guard count>=0,count<=maximumFrame else{throw TradeError.corrupt("封存區塊超過安全上限")}
        var result=Data();result.reserveCapacity(count)
        while result.count<count{guard let bytes=try ArchiveMemory.read(handle,upToCount:count-result.count),!bytes.isEmpty else{throw TradeError.corrupt("封存已截斷，原帳戶未變")};result.append(bytes)}
        return result
    }
    public static func recognizes(_ url:URL)throws->Bool{
        let input=try FileHandle(forReadingFrom:url);defer{try? input.close()};return try ArchiveMemory.read(input,upToCount:magic.count)==magic
    }
    private static func size(_ url:URL)throws->Int64{guard let number=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber else{throw TradeError.unavailable("無法讀取封存大小")};return number.int64Value}
    private static func writeFrame(_ frame:ArchiveFrame,payload:Data,key:Data,to handle:FileHandle)throws->String{
        let metadata=try AccountRepository.encode(frame)
        guard metadata.count<=8192 else{throw TradeError.invalid("封存標頭過長")}
        var plaintext=word(UInt32(metadata.count));plaintext.append(metadata);plaintext.append(payload)
        let nonce=key.isEmpty ? Data(repeating:0,count:12):try BackupService.random(12)
        var tag=Data(repeating:0,count:16)
        let content=key.isEmpty ? plaintext:try BackupService.crypt(plaintext,key:key,nonce:nonce,tag:&tag,encrypt:true)
        guard content.count+28<=maximumFrame else{throw TradeError.invalid("封存區塊超過安全上限")}
        try handle.write(contentsOf:word(UInt32(content.count+28)));try handle.write(contentsOf:nonce);try handle.write(contentsOf:tag);try handle.write(contentsOf:content)
        return BackupService.digest(plaintext)
    }
    public static func export(snapshotRoot:URL,mode:Mode,to destination:URL,password:String?,time:Int64,limits:ArchiveLimits=ArchiveLimits(),progress:(@Sendable(Double)->Void)?=nil)throws{
        try Task.checkCancellation()
        guard destination.isFileURL,time>=0,limits.maximumExpandedBytes>0,limits.maximumExpandedBytes<=16*1024*1024*1024,limits.maximumArchiveBytes>0,!FileManager.default.fileExists(atPath:destination.path) else{throw TradeError.invalid("封存目的地、上限或時間無效；不覆蓋原檔")}
        let repository=try AccountRepository(root:snapshotRoot,mode:mode)
        guard var state=try repository.load() else{throw TradeError.corrupt("檔案快照沒有帳戶")}
        if mode == .online{state.quotes=[:];state.consumed=[:];_=try repository.save(state)}
        try repository.prepareArchiveFile()
        let source=URL(fileURLWithPath:repository.path),length=try size(source)
        guard length>0,length<=limits.maximumExpandedBytes,limits.maximumExpandedBytes>0 else{throw TradeError.invalid("帳戶檔案超過大型封存上限；原帳戶保留")}
        let salt=password==nil || password=="" ? Data():try BackupService.random(16)
        let header=ArchiveFileHeader(mode:mode,expandedBytes:length,algorithm:salt.isEmpty ? "none":"AES-256-GCM/PBKDF2-HMAC-SHA256/chunks-1",iterations:salt.isEmpty ? 0:600_000,salt:salt,createdAt:time)
        let key=salt.isEmpty ? Data():try BackupService.derive(password!,salt:salt,iterations:600_000)
        let encoded=try AccountRepository.encode(header),headerDigest=BackupService.digest(encoded)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let partial=destination.deletingLastPathComponent().appendingPathComponent(".partial-"+UUID().uuidString)
        try Data().write(to:partial,options:.withoutOverwriting)
        var committed=false;defer{if !committed{try? FileManager.default.removeItem(at:partial)}}
        let input=try FileHandle(forReadingFrom:source),output=try FileHandle(forWritingTo:partial);defer{try? input.close();try? output.close()}
        try output.write(contentsOf:magic);try output.write(contentsOf:word(UInt32(encoded.count)));try output.write(contentsOf:encoded)
        let digest=try ArchiveDigest();var bytes:Int64=0,index=0,previous=headerDigest
        while let block=try ArchiveMemory.read(input,upToCount:header.chunkBytes),!block.isEmpty{
            try ArchiveMemory.scoped{
            try Task.checkCancellation();bytes+=Int64(block.count);guard bytes<=length else{throw TradeError.corrupt("檔案快照在封存期間發生變更")}
            try digest.update(block)
            previous=try writeFrame(ArchiveFrame(index:index,expandedBytes:block.count,previous:previous,header:headerDigest,isFinal:false),payload:BackupService.compress(block),key:key,to:output)
            index+=1;guard try output.offset()<=limits.maximumArchiveBytes else{throw TradeError.invalid("大型封存超過檔案上限")};progress?(Double(bytes)/Double(length))
            }
        }
        try Task.checkCancellation();guard bytes==length else{throw TradeError.corrupt("檔案快照長度不符")}
        _=try writeFrame(ArchiveFrame(index:index,expandedBytes:0,previous:previous,header:headerDigest,isFinal:true,fileDigest:digest.finish()),payload:Data(),key:key,to:output)
        try output.synchronize();try output.close();try Task.checkCancellation();try FileManager.default.moveItem(at:partial,to:destination);committed=true
    }
    public static func validate(_ source:URL,stagingRoot:URL,expectedMode:Mode,password:String?,limits:ArchiveLimits=ArchiveLimits(),progress:(@Sendable(Double)->Void)?=nil)throws->VerifiedAccountDatabase{
        try Task.checkCancellation()
        guard stagingRoot.isFileURL,limits.maximumExpandedBytes>0,limits.maximumExpandedBytes<=16*1024*1024*1024,limits.maximumArchiveBytes>0,!FileManager.default.fileExists(atPath:stagingRoot.path),try size(source)<=limits.maximumArchiveBytes else{throw TradeError.invalid("封存大小或還原暫存目錄不符")}
        let input=try FileHandle(forReadingFrom:source);defer{try? input.close()}
        guard try read(input,count:magic.count)==magic else{throw TradeError.corrupt("不是ChaiTrade大型封存")}
        let headerLength=try integer(read(input,count:4));guard (1...16384).contains(headerLength) else{throw TradeError.corrupt("封存標頭長度無效")}
        let rawHeader=try read(input,count:headerLength),header=try JSONDecoder().decode(ArchiveFileHeader.self,from:rawHeader),headerDigest=BackupService.digest(rawHeader)
        guard header.version==1,(6...8).contains(header.databaseSchema),header.mode==expectedMode,header.chunkBytes==1_048_576,header.expandedBytes>0,header.expandedBytes<=limits.maximumExpandedBytes,header.createdAt>=0 else{throw TradeError.corrupt("封存版本、帳戶或展開大小不符")}
        let key:Data
        if header.algorithm=="none"{guard header.iterations==0,header.salt.isEmpty else{throw TradeError.corrupt("封存加密參數不合法")};key=Data()}
        else{guard header.algorithm=="AES-256-GCM/PBKDF2-HMAC-SHA256/chunks-1",let password else{throw TradeError.corrupt("需要此大型封存的密碼")};key=try BackupService.derive(password,salt:header.salt,iterations:header.iterations)}
        try FileManager.default.createDirectory(at:stagingRoot,withIntermediateDirectories:true)
        var complete=false;defer{if !complete{try? FileManager.default.removeItem(at:stagingRoot)}}
        if let free=try FileManager.default.attributesOfFileSystem(forPath:stagingRoot.path)[.systemFreeSize] as? NSNumber{guard free.int64Value>=header.expandedBytes*2+64*1024*1024 else{throw TradeError.unavailable("可用空間不足以驗證及整理完整帳戶；請先釋出空間，原帳戶未變")}}
        let database=stagingRoot.appendingPathComponent("accounts/\(expectedMode.accountID)/account.sqlite")
        try FileManager.default.createDirectory(at:database.deletingLastPathComponent(),withIntermediateDirectories:true);try Data().write(to:database,options:.withoutOverwriting)
        let output=try FileHandle(forWritingTo:database);defer{try? output.close()}
        let digest=try ArchiveDigest();var expanded:Int64=0,index=0,previous=headerDigest
        var finished=false
        while !finished{
            try ArchiveMemory.scoped{
            try Task.checkCancellation()
            let length=try integer(read(input,count:4));guard (29...maximumFrame).contains(length) else{throw TradeError.corrupt("封存區塊長度無效")}
            let frame=try read(input,count:length),nonce=Data(frame.prefix(12));var tag=Data(frame.dropFirst(12).prefix(16))
            if key.isEmpty{guard nonce==Data(repeating:0,count:12),tag==Data(repeating:0,count:16) else{throw TradeError.corrupt("未加密封存含未知加密欄位")}}
            let body=key.isEmpty ? Data(frame.dropFirst(28)):try BackupService.crypt(Data(frame.dropFirst(28)),key:key,nonce:nonce,tag:&tag,encrypt:false)
            guard body.count>=4 else{throw TradeError.corrupt("封存區塊遺失")}
            let metadataLength=try integer(Data(body.prefix(4)));guard metadataLength>0,metadataLength<=8192,metadataLength<=body.count-4 else{throw TradeError.corrupt("封存區塊標頭無效")}
            let metadata=try JSONDecoder().decode(ArchiveFrame.self,from:Data(body.dropFirst(4).prefix(metadataLength))),payload=Data(body.dropFirst(4+metadataLength))
            guard metadata.header==headerDigest,metadata.index==index,metadata.previous==previous else{throw TradeError.corrupt("封存區塊順序、身份或校驗鏈不符")}
            if metadata.isFinal{
                guard metadata.expandedBytes==0,payload.isEmpty,expanded==header.expandedBytes,try digest.finish()==metadata.fileDigest,try ArchiveMemory.read(input,upToCount:1)?.isEmpty != false else{throw TradeError.corrupt("封存結尾、總量或校驗碼不符")};finished=true;return
            }
            let required=Int(min(Int64(header.chunkBytes),header.expandedBytes-expanded))
            guard metadata.fileDigest==nil,metadata.expandedBytes==required,metadata.expandedBytes>0,expanded+Int64(metadata.expandedBytes)<=header.expandedBytes else{throw TradeError.corrupt("封存區塊展開大小超過上限或不是完整分塊")}
            let block=try BackupService.expand(payload,size:metadata.expandedBytes);try digest.update(block);try output.write(contentsOf:block)
            expanded+=Int64(block.count);index+=1;previous=BackupService.digest(body);progress?(Double(expanded)/Double(header.expandedBytes)*0.85)
            }
        }
        try output.synchronize();try output.close();progress?(0.87)
        let verified=try SQLiteArchiveDatabase.verify(database,mode:expectedMode,expectedVersion:header.databaseSchema)
        if expectedMode == .online{guard verified.state.quotes.isEmpty,verified.state.consumed.isEmpty else{throw TradeError.corrupt("真實行情封存不得攜帶報價／撮合快取")}}
        let repository=try AccountRepository(root:stagingRoot,mode:expectedMode)
        guard let migrated=try repository.load() else{throw TradeError.corrupt("封存遷移後缺少帳戶")}
        try repository.rebuildArchiveReports(migrated);progress?(0.95);try repository.prepareArchiveFile()
        guard let state=try repository.load() else{throw TradeError.corrupt("已驗證封存缺少帳戶")}
        let result=try VerifiedAccountDatabase(mode:expectedMode,url:database,digest:ArchiveDigest.file(database),state:state)
        complete=true;progress?(1);return result
    }
}
