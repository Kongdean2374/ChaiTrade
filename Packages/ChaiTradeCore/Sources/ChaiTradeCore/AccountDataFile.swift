import Foundation

public enum AccountDataFormat:String,CaseIterable,Sendable{case json,fills,orders,ledger
    public var fileExtension:String{self == .json ? "json":"csv"}
    public var label:String{switch self{case .json:"完整JSON";case .fills:"成交CSV";case .orders:"委託CSV";case .ledger:"資金帳本CSV"}}
}
/// Exports an owned, frozen SQLite snapshot, retaining every original row and attachment.
public enum AccountDataFileService{
    public static func export(snapshotRoot:URL,mode:Mode,format:AccountDataFormat,to destination:URL,time:Int64,maximumBytes:Int64=24*1024*1024*1024,progress:(@Sendable(Double)->Void)?=nil)throws{
        try Task.checkCancellation()
        guard destination.isFileURL,time>=0,maximumBytes>0,maximumBytes<=24*1024*1024*1024,!FileManager.default.fileExists(atPath:destination.path) else{throw TradeError.invalid("資料匯出目的地或上限無效，不覆蓋原檔")}
        let repository=try AccountRepository(root:snapshotRoot,mode:mode);try repository.prepareArchiveFile()
        let source=URL(fileURLWithPath:repository.path),verified=try SQLiteArchiveDatabase.verify(source,mode:mode)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let partial=destination.deletingLastPathComponent().appendingPathComponent(".partial-"+UUID().uuidString)
        try Data().write(to:partial,options:.withoutOverwriting)
        var complete=false;defer{if !complete{try? FileManager.default.removeItem(at:partial)}}
        let output=try FileHandle(forWritingTo:partial);defer{try? output.close()}
        var bytes:Int64=0
        func write(_ data:Data)throws{try Task.checkCancellation();guard Int64(data.count)<=maximumBytes-bytes else{throw TradeError.invalid("資料匯出超過檔案上限；原帳戶保留")};try output.write(contentsOf:data);bytes+=Int64(data.count)}
        try repository.writeDataFile(format:format,time:time,write:write,progress:progress)
        guard try ArchiveDigest.file(source)==verified.digest else{throw TradeError.corrupt("匯出快照已變更，不產生完成檔；原帳戶保留")}
        try Task.checkCancellation();try output.synchronize();try output.close();try FileManager.default.moveItem(at:partial,to:destination);complete=true;progress?(1)
    }
}
extension AccountRepository{
    private func visitImpactGroupsUnlocked(_ body:(SimulationImpact)throws->Void)throws{
        var pending:SimulationImpact?
        try visit("SELECT json_extract(payload,'$.simulationImpact') FROM fills WHERE json_extract(payload,'$.simulationImpact') IS NOT NULL ORDER BY json_extract(payload,'$.simulationImpact.volumeTime'),json_extract(payload,'$.simulationImpact.groupID'),rowid"){text in
            let next=try JSONDecoder().decode(SimulationImpact.self,from:Data(text.utf8))
            if var old=pending,old.groupID==next.groupID{
                guard old.instrumentID==next.instrumentID,old.volumeTime==next.volumeTime,old.startsAt==next.startsAt,old.endsAt==next.endsAt else{throw TradeError.corrupt("歷史交易衝擊身份不符")}
                old.amplitude=try old.amplitude+next.amplitude;old.volume=try old.volume+next.volume;pending=old
            }else{if let pending{try body(pending)};pending=next}
        };if let pending{try body(pending)}
    }
    func writeDataFile(format:AccountDataFormat,time:Int64,write:(Data)throws->Void,progress:(@Sendable(Double)->Void)?)throws{
        lock.lock();defer{lock.unlock()}
        try exec("BEGIN DEFERRED");var committed=false;defer{if !committed{try? exec("ROLLBACK")}}
        guard let raw=try scalar("SELECT payload FROM account_state LIMIT 1") else{throw TradeError.corrupt("帳戶不存在")}
        var state=try JSONDecoder().decode(AccountState.self,from:Data(raw.utf8));try Self.validate(state,mode:mode)
        if mode == .online{state.quotes=[:];state.consumed=[:]}
        let total=Int64(try scalar("SELECT (SELECT count(*) FROM fills)+(SELECT count(*) FROM orders)+(SELECT count(*) FROM ledger)+(SELECT count(*) FROM events)+(SELECT count(*) FROM equity)+(SELECT count(*) FROM financial_flows)+(SELECT count(*) FROM journal_entries)+(SELECT count(*) FROM applied_event_ids)+(SELECT count(*) FROM lifecycle_history)") ?? "0") ?? 0
        var completed:Int64=0,lastProgress=0.0
        func tick(){completed+=1;let value=min(0.99,Double(completed)/Double(max(1,total)));if value-lastProgress>=0.005{lastProgress=value;progress?(value)}}
        if format != .json{
            try writeCSVUnlocked(kind:format.rawValue,time:time){data in try write(data);if data != Data([13,10]){tick()}}
            try Task.checkCancellation();try exec("COMMIT");committed=true;return
        }
        func text(_ value:String)throws{try write(Data(value.utf8))}
        func value(_ object:Any)throws{try write(JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes,.fragmentsAllowed]))}
        func array(sql:String,values:[String]=[],transform:((String)throws->Data)?=nil)throws{
            try text("[\n");var first=true
            try visit(sql,values:values){raw in
                if !first{try text(",\n")};first=false
                if let transform{try write(transform(raw))}else{try text(raw)};tick()
            };try text("\n]")
        }
        func object(_ base:[String:Any],special:Set<String>,field:(String)throws->Void)throws{
            try text("{\n");var first=true
            for key in Set(base.keys).union(special).sorted(){
                try Task.checkCancellation();if !first{try text(",\n")};first=false
                try write(Self.encode(key));try text(":")
                if special.contains(key){try field(key)}else{try value(base[key]!)}
            };try text("\n}")
        }
        guard var base=try JSONSerialization.jsonObject(with:Self.encode(state)) as? [String:Any] else{throw TradeError.corrupt("資料匯出缺少帳戶欄位")}
        base.removeValue(forKey:"history")
        let specials=Set(["orders","fills","events","ledger","equity","financialFlows","journals","appliedEvents"]).union(state.lifecycle==nil ? []:["lifecycle"]).union(state.simulation==nil ? []:["simulation"])
        try object(base,special:specials){key in
            switch key{
            case "orders":
                try text("{\n");var first=true
                try visit("SELECT payload FROM orders ORDER BY id"){raw in let order=try JSONDecoder().decode(Order.self,from:Data(raw.utf8));if !first{try text(",\n")};first=false;try write(Self.encode(order.id));try text(":"+raw);tick()};try text("\n}")
            case "fills":try array(sql:"SELECT payload FROM fills ORDER BY rowid")
            case "events":try array(sql:"SELECT payload FROM events ORDER BY sequence")
            case "ledger":try array(sql:"SELECT payload FROM ledger ORDER BY ordinal")
            case "equity":try array(sql:"SELECT payload FROM equity ORDER BY ordinal")
            case "financialFlows":try array(sql:"SELECT payload FROM financial_flows ORDER BY rowid")
            case "appliedEvents":try array(sql:"SELECT id FROM applied_event_ids ORDER BY id",transform:{try Self.encode($0)})
            case "journals":try array(sql:"SELECT payload FROM journal_entries ORDER BY rowid",transform:{raw in let entry=try JSONDecoder().decode(JournalEntry.self,from:Data(raw.utf8));return try Self.encode(self.fullJournalUnlocked(entry))})
            case "lifecycle":
                guard var life=base["lifecycle"] as? [String:Any] else{throw TradeError.corrupt("帳務事件欄位遺失")}
                for kind in LifecycleHistoryKind.allCases{life.removeValue(forKey:kind.rawValue)}
                try object(life,special:Set(LifecycleHistoryKind.allCases.map(\.rawValue))){kind in try array(sql:"SELECT payload FROM lifecycle_history WHERE kind=? ORDER BY ordinal",values:[kind])}
            case "simulation":
                guard var simulation=base["simulation"] as? [String:Any] else{throw TradeError.corrupt("模擬狀態遺失")}
                simulation.removeValue(forKey:"impactArchiveCutoff")
                let hasImpacts=try scalar("SELECT EXISTS(SELECT 1 FROM fills WHERE json_extract(payload,'$.simulationImpact') IS NOT NULL)")=="1"
                let keys:Set<String>=hasImpacts || simulation["impactGroups"] != nil ? ["impactGroups"]:[]
                try object(simulation,special:keys){_ in
                    try text("[\n");var first=true
                    try visitImpactGroupsUnlocked{impact in if !first{try text(",\n")};first=false;try write(Self.encode(impact))};try text("\n]")
                }
            default:throw TradeError.invalid("未知完整資料欄位")
            }
        }
        try Task.checkCancellation();try exec("COMMIT");committed=true
    }
}
