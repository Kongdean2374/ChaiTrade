import Foundation
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
}
public enum BackupService {
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
        var clean = state
        // Provider data/cache and credentials are never exported. Offline state is the owned synthetic world.
        if state.mode == .online { clean.quotes = [:]; clean.consumed = [:] }
        let payload = try AccountRepository.encode(clean)
        var envelope = BackupEnvelope(mode:state.mode,createdAt:time,algorithm:"none",iterations:0,salt:Data(),nonce:Data(),tag:Data(),payload:payload,checksum:digest(payload))
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
        let state = try JSONDecoder().decode(AccountState.self,from:payload)
        try AccountRepository.validate(state,mode:expectedMode)
        return state
    }
}
