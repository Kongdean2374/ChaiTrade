import Foundation

/// Runtime-only indexed lookup. The encoded null is deliberately independent of
/// repository identity; old JSON states decode it as absent and backups contain full IDs.
@propertyWrapper struct RuntimeAppliedLookup:Codable,Sendable{
    var wrappedValue:(@Sendable(String)throws->Bool)?
    init(wrappedValue:(@Sendable(String)throws->Bool)?=nil){self.wrappedValue=wrappedValue}
    init(from decoder:Decoder)throws{wrappedValue=nil}
    func encode(to encoder:Encoder)throws{var container=encoder.singleValueContainer();try container.encodeNil()}
}
extension KeyedDecodingContainer{
    func decode(_ type:RuntimeAppliedLookup.Type,forKey key:Key)throws->RuntimeAppliedLookup{try decodeIfPresent(type,forKey:key) ?? RuntimeAppliedLookup()}
}
extension AccountRepository{
    func createAppliedEventSchema()throws{try exec("CREATE TABLE IF NOT EXISTS applied_event_ids(id TEXT PRIMARY KEY,account_id TEXT NOT NULL)")}
    func appliedEventCountUnlocked()throws->Int{guard let count=Int(try scalar("SELECT count(*) FROM applied_event_ids") ?? ""),count>=0,try scalar("SELECT coalesce(min(rowid),0) FROM applied_event_ids")==String(count==0 ? 0:1),try scalar("SELECT coalesce(max(rowid),0) FROM applied_event_ids")==String(count) else{throw TradeError.corrupt("冪等事件索引無法核對")};return count}
    func appliedIDsUnlocked(limit:Int?=nil)throws->Set<String>{
        var ids=Set<String>();try visit("SELECT id FROM applied_event_ids ORDER BY id"+(limit.map{" DESC LIMIT \($0)"} ?? "")){ids.insert($0)};return ids
    }
    public func appliedEventExists(_ id:String,throughOrdinal:Int?=nil)throws->Bool{
        lock.lock();defer{lock.unlock()};var result=""
        try visit("SELECT EXISTS(SELECT 1 FROM applied_event_ids WHERE id=? AND account_id=? AND rowid<=?)",values:[id,mode.accountID,String(throughOrdinal ?? Int.max)]){result=$0}
        guard result=="0" || result=="1" else{throw TradeError.corrupt("冪等事件索引讀取中斷")};return result=="1"
    }
    func saveAppliedEventsUnlocked(_ state:AccountState,replacing:Bool)throws{
        if !replacing,let count=state.history?.appliedEventCount{
            guard try appliedEventCountUnlocked()>=count else{throw TradeError.corrupt("冪等事件寫入來源已過期，整筆交易已回滾")}
            // An identical deterministic replay may meet an already committed suffix.
            // Every suffix identity must also exist in this proposed timeline.
            try visit("SELECT id FROM applied_event_ids WHERE rowid>?",values:[String(count)]){id in guard state.appliedEvents.contains(id) else{throw TradeError.corrupt("冪等事件分支不同，整筆交易已回滾")}}
        }
        guard state.appliedEvents.allSatisfy({!$0.isEmpty && $0.utf8.count<=1024}) else{throw TradeError.corrupt("冪等事件識別超過範圍")}
        try batch("INSERT OR IGNORE INTO applied_event_ids(id,account_id) VALUES(?,?)",rows:state.appliedEvents.sorted().map{[$0,state.accountID]})
    }
    func verifyAppliedEventsUnlocked(_ state:AccountState)throws{
        guard let count=state.history?.appliedEventCount else{return}
        guard try appliedEventCountUnlocked()==count,try appliedIDsUnlocked(limit:100)==state.appliedEvents else{throw TradeError.corrupt("冪等事件投影不符")}
        var invalid=""
        try visit("SELECT count(*) FROM applied_event_ids WHERE account_id<>? OR id='' OR length(CAST(id AS BLOB))>1024",values:[state.accountID]){invalid=$0}
        guard invalid=="0" else{throw TradeError.corrupt("冪等事件帳戶或識別不符")}
    }
}
