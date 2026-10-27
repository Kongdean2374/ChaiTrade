import Foundation

/// Freshness is evaluated when the complete response arrives, including quota
/// waiting and optional statistics. A later source timestamp is not compared
/// against the earlier request-start wall clock.
struct QuoteRequestClock: Sendable {
    let wall: Int64
    let uptime: TimeInterval
    func receivedAt(uptime end: TimeInterval) throws -> Int64 {
        let elapsed=max(0,(end-uptime).rounded(.down))
        guard elapsed.isFinite,elapsed<Double(Int64.max) else{throw TradeError.invalid("行情請求時間無效")}
        let (received,overflow)=wall.addingReportingOverflow(Int64(elapsed))
        guard !overflow,received<=Int64.max-5 else{throw TradeError.invalid("行情接收時間超出範圍")}
        return received
    }
}
