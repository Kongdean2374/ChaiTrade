import Foundation

extension AccountRepository{
    /// A conservative lower bound from canonical fields that must appear in full JSON.
    /// This only rejects provably oversized legacy backups; it does not reduce their cap.
    func legacyJSONLowerBoundUnlocked()throws->Int64{
        let tables=["events","fills","orders","ledger","equity","financial_flows","journal_entries"]
        let parts=tables.map{"SELECT coalesce(sum(length(CAST(payload AS BLOB))),0) AS bytes FROM \($0)"}+["SELECT coalesce(sum(((length(bytes)+2)/3)*4),0) AS bytes FROM journal_images"]
        guard let count=Int64(try scalar("SELECT sum(bytes) FROM ("+parts.joined(separator:" UNION ALL ")+")") ?? ""),count>=0 else{throw TradeError.corrupt("無法估算舊格式備份容量；原帳戶保留")}
        return count
    }
}
