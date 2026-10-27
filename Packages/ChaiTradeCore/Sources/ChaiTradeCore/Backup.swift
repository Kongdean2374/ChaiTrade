import Foundation
import CZlib
#if canImport(CryptoKit)
import CryptoKit
import CommonCrypto
import Security
#else
import COpenSSL
#endif

public struct BackupEnvelope: Codable, Sendable {
    public var format = "ChaiTrade 模擬交易備份"
    public var version = 1
    public var mode: Mode
    public var createdAt: Int64
    public var algorithm: String
    public var iterations: Int
    public var salt: Data
    public var nonce: Data
    public var tag: Data
    public var payload: Data
    public var checksum: String
    public var compression: String?
    public var expandedSize: Int?
}
public struct AccountBackupBundle: Codable, Sendable {
    public var format = "ChaiTrade 雙帳戶模擬交易備份"
    public var version = 1
    public var createdAt: Int64
    public var accounts: [Data]
    public var checksums: [String]
}
public enum BackupService {
    private static let expandedLimit = 512_000_000
    private static func compress(_ data:Data)throws->Data{
        var size=compressBound(uLong(data.count)),out=Data(count:Int(compressBound(uLong(data.count))))
        let status=out.withUnsafeMutableBytes{dst in data.withUnsafeBytes{src in compress2(dst.bindMemory(to:UInt8.self).baseAddress,&size,src.bindMemory(to:UInt8.self).baseAddress,uLong(data.count),Z_BEST_SPEED)}}
        guard status==Z_OK else{throw TradeError.corrupt("備份壓縮失敗")};out.count=Int(size);return out
    }
    private static func expand(_ data:Data,size:Int)throws->Data{
        guard size>0,size<=expandedLimit else{throw TradeError.corrupt("備份展開大小超過安全上限")}
        var count=uLongf(size),out=Data(count:size)
        let status=out.withUnsafeMutableBytes{dst in data.withUnsafeBytes{src in uncompress(dst.bindMemory(to:UInt8.self).baseAddress,&count,src.bindMemory(to:UInt8.self).baseAddress,uLong(data.count))}}
        guard status==Z_OK,count==size else{throw TradeError.corrupt("備份壓縮資料或展開長度不符")};return out
    }
    public static func exportBoth(_ accounts: [AccountState],password: String?,time: Int64) throws -> Data {
        guard accounts.count==2,Set(accounts.map(\.mode)).count==2 else{throw TradeError.invalid("完整備份須包含獨立的 A、B 帳戶")}
        let payloads=try accounts.sorted{$0.mode.rawValue<$1.mode.rawValue}.map{try export($0,password:password,time:time)}
        let data=try AccountRepository.encode(AccountBackupBundle(createdAt:time,accounts:payloads,checksums:payloads.map(digest)))
        guard data.count<=100_000_000 else{throw TradeError.invalid("雙帳戶備份超過目前安全容量，未匯出；請勿因此重設帳戶")}
        return data
    }
    public static func importAccount(_ data: Data,expectedMode: Mode,password: String?) throws -> AccountState {
        guard data.count<=100_000_000 else{throw TradeError.corrupt("備份超過安全大小限制")}
        if let bundle=try? JSONDecoder().decode(AccountBackupBundle.self,from:data){
            guard bundle.version==1,bundle.format=="ChaiTrade 雙帳戶模擬交易備份",bundle.accounts.count==2,bundle.checksums.count==2 else{throw TradeError.corrupt("雙帳戶備份結構不合法")}
            var result: AccountState?,modes=Set<Mode>()
            for n in bundle.accounts.indices {
                let payload=bundle.accounts[n]
                guard digest(payload)==bundle.checksums[n] else{throw TradeError.corrupt("雙帳戶備份校驗碼不符")}
                let header=try JSONDecoder().decode(BackupEnvelope.self,from:payload)
                guard modes.insert(header.mode).inserted else{throw TradeError.corrupt("雙帳戶備份模式重複")}
                let validated=try validate(payload,expectedMode:header.mode,password:password)
                if header.mode==expectedMode{result=validated}
            }
            guard let result else{throw TradeError.wrongAccount};return result
        }
        return try validate(data,expectedMode:expectedMode,password:password)
    }
    public static func digest(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        #else
        var bytes = [UInt8](repeating:0,count:32)
        data.withUnsafeBytes { ptr in _ = SHA256(ptr.bindMemory(to:UInt8.self).baseAddress,data.count,&bytes) }
        return bytes.map { String(format:"%02x",$0) }.joined()
        #endif
    }
    private static func random(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating:0,count:count)
        #if canImport(CryptoKit)
        guard SecRandomCopyBytes(kSecRandomDefault,count,&bytes) == errSecSuccess else { throw TradeError.unavailable("安全亂數不可用") }
        #else
        guard RAND_bytes(&bytes,Int32(count)) == 1 else { throw TradeError.unavailable("安全亂數不可用") }
        #endif
        return Data(bytes)
    }
    private static func derive(_ password: String, salt: Data, iterations: Int) throws -> Data {
        guard password.utf8.count >= 8, password.utf8.count <= 1024, iterations == 600_000, salt.count == 16 else { throw TradeError.invalid("備份密碼至少 8 個 UTF-8 位元組，或加密參數不合法") }
        let bytes = Array(password.utf8); var key = [UInt8](repeating:0,count:32)
        #if canImport(CryptoKit)
        let result = bytes.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),p.baseAddress?.assumingMemoryBound(to:CChar.self),bytes.count,s.bindMemory(to:UInt8.self).baseAddress,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),UInt32(iterations),&key,32)
        }}
        guard result == kCCSuccess else { throw TradeError.corrupt("密碼衍生失敗") }
        #else
        let result = bytes.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            PKCS5_PBKDF2_HMAC(p.baseAddress?.assumingMemoryBound(to:CChar.self),Int32(bytes.count),s.bindMemory(to:UInt8.self).baseAddress,Int32(salt.count),Int32(iterations),EVP_sha256(),32,&key)
        }}
        guard result == 1 else { throw TradeError.corrupt("密碼衍生失敗") }
        #endif
        return Data(key)
    }
    private static func crypt(_ input: Data, key: Data, nonce: Data, tag: inout Data, encrypt: Bool) throws -> Data {
        #if canImport(CryptoKit)
        if encrypt {
            let box = try AES.GCM.seal(input,using:SymmetricKey(data:key),nonce:AES.GCM.Nonce(data:nonce))
            tag = box.tag; return box.ciphertext
        }
        do { return try AES.GCM.open(AES.GCM.SealedBox(nonce:AES.GCM.Nonce(data:nonce),ciphertext:input,tag:tag),using:SymmetricKey(data:key)) }
        catch { throw TradeError.corrupt("密碼錯誤或備份已損毀；原資料不變") }
        #else
        var output = [UInt8](repeating:0,count:input.count+16), auth = [UInt8](tag)
        let result = key.withUnsafeBytes { k in nonce.withUnsafeBytes { n in input.withUnsafeBytes { i in
            chai_gcm(encrypt ? 1:0,k.bindMemory(to:UInt8.self).baseAddress,n.bindMemory(to:UInt8.self).baseAddress,i.bindMemory(to:UInt8.self).baseAddress,Int32(input.count),&output,&auth)
        }}}
        guard result == 1 else { throw TradeError.corrupt("密碼錯誤或備份已損毀；原資料不變") }
        tag = Data(auth); return Data(output.prefix(input.count))
        #endif
    }
    public static func export(_ state: AccountState, password: String?, time: Int64) throws -> Data {
        try AccountRepository.validate(state,mode:state.mode)
        guard state.history.map({$0.fills==0 && $0.ledger==0 && $0.events==0}) ?? true else{throw TradeError.invalid("備份必須先取得完整歷史，不可匯出分頁投影")}
        var clean = state
        clean.history=nil
        // Provider data/cache and credentials are never exported. Offline state is the owned synthetic world.
        if state.mode == .online { clean.quotes = [:]; clean.consumed = [:] }
        let raw = try AccountRepository.encode(clean)
        guard raw.count<=expandedLimit else{throw TradeError.invalid("完整帳戶超過 512 MB 展開上限，未匯出；請保留原帳戶")}
        let payload = raw.count>65_536 ? try compress(raw):raw
        guard payload.count<=32_000_000 else{throw TradeError.invalid("帳戶超過目前 32 MB 備份容量，未產生不可還原的檔案；請保留原帳戶，不要重設或重裝")}
        var envelope = BackupEnvelope(mode:state.mode,createdAt:time,algorithm:"none",iterations:0,salt:Data(),nonce:Data(),tag:Data(),payload:payload,checksum:digest(payload))
        if raw.count>65_536{envelope.compression="zlib-1";envelope.expandedSize=raw.count}
        if let password, !password.isEmpty {
            envelope.algorithm = "AES-256-GCM/PBKDF2-HMAC-SHA256"; envelope.iterations = 600_000
            envelope.salt = try random(16); envelope.nonce = try random(12); envelope.tag = Data(repeating:0,count:16)
            let key = try derive(password,salt:envelope.salt,iterations:envelope.iterations)
            envelope.payload = try crypt(payload,key:key,nonce:envelope.nonce,tag:&envelope.tag,encrypt:true)
        }
        return try AccountRepository.encode(envelope)
    }
    public static func validate(_ data: Data, expectedMode: Mode, password: String?) throws -> AccountState {
        guard data.count <= 50_000_000 else { throw TradeError.corrupt("備份超過 50 MB 安全限制") }
        let e = try JSONDecoder().decode(BackupEnvelope.self,from:data)
        guard e.format == "ChaiTrade 模擬交易備份", e.version == 1, e.mode == expectedMode, e.payload.count <= 32_000_000 else { throw TradeError.corrupt("備份版本、模式或大小不符") }
        var payload = e.payload
        if e.algorithm != "none" {
            guard e.algorithm == "AES-256-GCM/PBKDF2-HMAC-SHA256",e.nonce.count == 12,e.tag.count == 16,let password else { throw TradeError.corrupt("請輸入密碼，或備份加密版本不相容") }
            let key = try derive(password,salt:e.salt,iterations:e.iterations); var tag = e.tag
            payload = try crypt(e.payload,key:key,nonce:e.nonce,tag:&tag,encrypt:false)
        } else { guard e.iterations == 0,e.salt.isEmpty,e.nonce.isEmpty,e.tag.isEmpty else { throw TradeError.corrupt("備份加密標頭不合法") } }
        guard digest(payload) == e.checksum else { throw TradeError.corrupt("備份校驗碼不符，原資料不變") }
        if let compression=e.compression{guard compression=="zlib-1",let size=e.expandedSize else{throw TradeError.corrupt("備份壓縮格式不符")};payload=try expand(payload,size:size)}
        else{guard e.expandedSize==nil else{throw TradeError.corrupt("備份展開標頭不合法")}}
        let state = try JSONDecoder().decode(AccountState.self,from:payload)
        guard state.history==nil else{throw TradeError.corrupt("備份不可缺少封存歷史")}
        try AccountRepository.validate(state,mode:expectedMode)
        return state
    }
}
