import Foundation
import CSQLite

public enum LifecycleHistoryKind:String,CaseIterable,Sendable{case settlements,carry,actions
    public var label:String{switch self{case .settlements:"交割";case .carry:"持有費";case .actions:"股務事件"}}
}
public enum LifecycleRecord:Sendable{
    case settlement(SettlementEvent),carry(CarryEvent),action(CorporateAction)
    public var id:String{switch self{case .settlement(let e):e.id;case .carry(let e):e.id;case .action(let e):e.id}}
    var time:Int64{switch self{case .settlement(let e):e.due;case .carry(let e):e.time;case .action(let e):e.time}}
    var pending:Bool{if case .settlement(let e)=self{return e.completedAt==nil};return false}
    func encoded()throws->Data{switch self{case .settlement(let e):try AccountRepository.encode(e);case .carry(let e):try AccountRepository.encode(e);case .action(let e):try AccountRepository.encode(e)}}
    static func decode(_ text:String,kind:LifecycleHistoryKind)throws->Self{
        let data=Data(text.utf8),decoder=JSONDecoder()
        switch kind{case .settlements:return .settlement(try decoder.decode(SettlementEvent.self,from:data));case .carry:return .carry(try decoder.decode(CarryEvent.self,from:data));case .actions:return .action(try decoder.decode(CorporateAction.self,from:data))}
    }
}
public struct LifecycleHistoryRow:Sendable,Identifiable{
    public let cursor:Int64
    public let record:LifecycleRecord
    public var id:String{record.id}
}
extension AccountRepository{
    func createLifecycleSchema()throws{
        try exec("CREATE TABLE IF NOT EXISTS lifecycle_history(kind TEXT NOT NULL,id TEXT NOT NULL,ordinal INTEGER NOT NULL,account_id TEXT NOT NULL,time INTEGER NOT NULL,pending INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,id),UNIQUE(kind,ordinal)); CREATE INDEX IF NOT EXISTS lifecycle_pending ON lifecycle_history(kind,pending,ordinal)")
    }
    static func lifecycleRecords(_ life:LifecycleState?,kind:LifecycleHistoryKind)->[LifecycleRecord]{
        switch kind{case .settlements:return (life?.settlements ?? []).map{.settlement($0)};case .carry:return (life?.carry ?? []).map{.carry($0)};case .actions:return (life?.actions ?? []).map{.action($0)}}
    }
    static func validateLifecycle(_ life:LifecycleState?,instrumentIDs:Set<String>)throws{
        for kind in LifecycleHistoryKind.allCases{
            let records=lifecycleRecords(life,kind:kind)
            guard Set(records.map(\.id)).count==records.count else{throw TradeError.corrupt("帳務歷史身份重複")}
            for record in records{try validateLifecycleRecord(record,instrumentIDs:instrumentIDs)}
        }
    }
    private static func validateLifecycleRecord(_ record:LifecycleRecord,instrumentIDs:Set<String>)throws{
        guard !record.id.isEmpty,record.id.utf8.count<=1024,record.time>=0 else{throw TradeError.corrupt("帳務歷史身份或時間不合法")}
        switch record{
        case .settlement(let e):guard !e.currency.isEmpty,e.receivable >= .zero,e.payable >= .zero,e.completedAt==nil || e.completedAt!>=e.due else{throw TradeError.corrupt("交割金額或完成時間不合法")}
        case .carry(let e):guard instrumentIDs.contains(e.instrumentID),e.mark > .zero,e.rate.magnitude <= .one,!e.kind.isEmpty,!e.source.isEmpty else{throw TradeError.corrupt("持有費商品、標記價或來源不合法")}
        case .action(let e):
            guard instrumentIDs.contains(e.instrumentID),!e.source.isEmpty else{throw TradeError.corrupt("股務事件商品或來源不合法")}
            switch e.kind{
            case .split:guard (e.ratio ?? .zero) > .zero else{throw TradeError.corrupt("分割比例不合法")}
            case .dividend:guard let cash=e.cashPerUnit,cash >= .zero,let payment=e.paymentTime,payment>=e.time else{throw TradeError.corrupt("配息金額或付款時間不合法")}
            case .rename:guard let symbol=e.newSymbol,!symbol.isEmpty else{throw TradeError.corrupt("新代碼遺失")}
            case .cashLiquidation:guard let price=e.cashPerUnit,price >= .zero else{throw TradeError.corrupt("現金清算價格不合法")}
            case .halt,.resume:break
            }
        }
    }
    func lifecycleCountsUnlocked()throws->[String:Int]{
        var result:[String:Int]=[:]
        for kind in LifecycleHistoryKind.allCases{
            var value="";try visit("SELECT count(*) FROM lifecycle_history WHERE kind=?",values:[kind.rawValue]){value=$0}
            guard let count=Int(value),count>=0 else{throw TradeError.corrupt("帳務歷史筆數無法核對")};result[kind.rawValue]=count
        };return result
    }
    func lifecycleProjectionUnlocked(_ original:LifecycleState?,full:Bool=false)throws->LifecycleState?{
        let tail=full ? "":" AND (pending=1 OR ordinal IN (SELECT ordinal FROM lifecycle_history WHERE kind=? AND pending=0 ORDER BY ordinal DESC LIMIT 100))"
        func rows<T:Decodable>(_ type:T.Type,_ kind:LifecycleHistoryKind)throws->[T]{try readRows(type,sql:"SELECT payload FROM lifecycle_history WHERE kind=?"+tail+" ORDER BY ordinal",values:full ? [kind.rawValue]:[kind.rawValue,kind.rawValue])}
        var life=original ?? LifecycleState()
        life.settlements=try rows(SettlementEvent.self,.settlements);life.carry=try rows(CarryEvent.self,.carry);life.actions=try rows(CorporateAction.self,.actions)
        return original != nil || !life.settlements.isEmpty || !life.carry.isEmpty || !life.actions.isEmpty ? life:nil
    }
    func saveLifecycleUnlocked(_ state:AccountState,replacing:Bool)throws{
        let counts=try lifecycleCountsUnlocked()
        for kind in LifecycleHistoryKind.allCases{
            let records=Self.lifecycleRecords(state.lifecycle,kind:kind),ids=Set(records.map(\.id))
            var count=counts[kind.rawValue]!
            if !replacing{
                let boundary=state.history?.lifecycleCounts?[kind.rawValue] ?? 0
                guard count>=boundary else{throw TradeError.corrupt("帳務歷史來源已過期，交易已回滾")}
                try visit("SELECT id FROM lifecycle_history WHERE kind=? AND ordinal>?",values:[kind.rawValue,String(boundary)]){id in guard ids.contains(id) else{throw TradeError.corrupt("帳務事件時間線不同，交易已回滾")}}
            }
            for record in records{
                let payload=String(decoding:try record.encoded(),as:UTF8.self)
                var old:String?;try visit("SELECT payload FROM lifecycle_history WHERE kind=? AND id=?",values:[kind.rawValue,record.id]){old=$0}
                if let old{
                    if old==payload{continue}
                    guard case .settlement(var prior)=try LifecycleRecord.decode(old,kind:kind),case .settlement(let next)=record,prior.completedAt==nil,next.completedAt != nil else{throw TradeError.corrupt("不可改寫已歸檔的帳務事件")}
                    prior.completedAt=next.completedAt
                    guard try Self.encode(prior)==Self.encode(next) else{throw TradeError.corrupt("交割完成不可變更原金額或到期日")}
                    try insert("UPDATE lifecycle_history SET pending=0,payload=? WHERE kind=? AND id=?",[payload,kind.rawValue,record.id])
                }else{
                    count+=1
                    try insert("INSERT INTO lifecycle_history(kind,id,ordinal,account_id,time,pending,payload) VALUES(?,?,?,?,?,?,?)",[kind.rawValue,record.id,String(count),state.accountID,String(record.time),record.pending ? "1":"0",payload])
                }
            }
        }
    }
    func verifyLifecycleUnlocked(_ state:AccountState)throws{
        guard let counts=state.history?.lifecycleCounts else{return}
        guard try counts==lifecycleCountsUnlocked(),Set(counts.keys)==Set(LifecycleHistoryKind.allCases.map(\.rawValue)) else{throw TradeError.corrupt("帳務歷史檢查點不符")}
        let ids=Set(state.instruments.map(\.id))
        var invalid="";try visit("SELECT count(*) FROM lifecycle_history WHERE account_id<>? OR kind NOT IN ('settlements','carry','actions') OR id IS NOT json_extract(payload,'$.id') OR time IS NOT coalesce(json_extract(payload,'$.due'),json_extract(payload,'$.time')) OR pending IS NOT (kind='settlements' AND json_extract(payload,'$.completedAt') IS NULL)",values:[state.accountID]){invalid=$0}
        guard invalid=="0" else{throw TradeError.corrupt("帳務歷史列身份、帳戶或狀態不符")}
        for kind in LifecycleHistoryKind.allCases{
            var ordinal=0
            try visit("SELECT json_object('ordinal',ordinal,'payload',json(payload)) FROM lifecycle_history WHERE kind=? ORDER BY ordinal",values:[kind.rawValue]){text in
                let raw=try JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any]
                guard let raw,let number=raw["ordinal"] as? Int,number==ordinal+1,let payload=raw["payload"] else{throw TradeError.corrupt("帳務歷史序號不連續")}
                let data=try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),record=try LifecycleRecord.decode(String(decoding:data,as:UTF8.self),kind:kind)
                try Self.validateLifecycleRecord(record,instrumentIDs:ids);ordinal+=1
            }
            guard ordinal==counts[kind.rawValue] else{throw TradeError.corrupt("帳務完整歷史筆數不符")}
        }
        guard try Self.encode(lifecycleProjectionUnlocked(state.lifecycle))==Self.encode(state.lifecycle) else{throw TradeError.corrupt("帳務歷史熱資料投影不符")}
    }
    public func lifecyclePage(kind:LifecycleHistoryKind,limit:Int=20,before:Int64?=nil)throws->[LifecycleHistoryRow]{
        guard (1...100).contains(limit),before==nil || before!>0 else{throw TradeError.invalid("帳務歷史分頁參數不合法")}
        lock.lock();defer{lock.unlock()}
        var statement:OpaquePointer?;guard sqlite3_prepare_v2(db,"SELECT ordinal,payload FROM lifecycle_history WHERE kind=? AND ordinal<? ORDER BY ordinal DESC LIMIT ?",-1,&statement,nil)==SQLITE_OK else{throw TradeError.corrupt("帳務歷史分頁無法準備")};defer{sqlite3_finalize(statement)}
        _=kind.rawValue.withCString{sqlite3_bind_text(statement,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))};sqlite3_bind_int64(statement,2,before ?? Int64.max);sqlite3_bind_int(statement,3,Int32(limit))
        var rows:[LifecycleHistoryRow]=[],status=sqlite3_step(statement)
        while status==SQLITE_ROW{guard let text=sqlite3_column_text(statement,1) else{throw TradeError.corrupt("帳務歷史遺失")};rows.append(LifecycleHistoryRow(cursor:sqlite3_column_int64(statement,0),record:try LifecycleRecord.decode(String(cString:text),kind:kind)));status=sqlite3_step(statement)}
        guard status==SQLITE_DONE else{throw TradeError.corrupt("帳務歷史分頁中斷")};return rows
    }
}
