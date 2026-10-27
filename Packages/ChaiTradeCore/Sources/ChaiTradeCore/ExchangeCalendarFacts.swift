import Foundation

/// Published calendar facts; fixed in the offline binary, never downloaded by B.
/// TWSE: https://www.twse.com.tw/rwd/zh/holidaySchedule/holidaySchedule?response=json
/// NYSE: https://www.nyse.com/markets/hours-calendars
/// Only the declared years are verified; other years retain explicit custom simulation calendars.
public enum ExchangeCalendarFacts{
    public static let taiwanTradingHolidays=["2026-01-01", "2026-02-12", "2026-02-13", "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-27", "2026-02-28", "2026-04-03", "2026-04-04", "2026-04-05", "2026-04-06", "2026-05-01", "2026-06-19", "2026-09-25", "2026-09-28", "2026-10-09", "2026-10-10", "2026-10-25", "2026-10-26", "2026-12-25"]
    public static let taiwanSettlementHolidays=["2026-01-01", "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-27", "2026-02-28", "2026-04-03", "2026-04-04", "2026-04-05", "2026-04-06", "2026-05-01", "2026-06-19", "2026-09-25", "2026-09-28", "2026-10-09", "2026-10-10", "2026-10-25", "2026-10-26", "2026-12-25"]
    public static let usTradingHolidays=["2025-01-01", "2025-01-20", "2025-02-17", "2025-04-18", "2025-05-26", "2025-06-19", "2025-07-04", "2025-09-01", "2025-11-27", "2025-12-25", "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19", "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25", "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18", "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24"]
    public static func applyTaiwan(to rules:inout RulePack){
        rules.holidays=taiwanTradingHolidays;rules.settlementHolidays=taiwanSettlementHolidays;rules.calendarYears=[2026]
        rules.source+="；TWSE2026交易／交割假日分列，其他年度與臨時休市須另行核對"
    }
    public static func applyUS(to rules:inout RulePack){
        rules.holidays=usTradingHolidays;rules.calendarYears=[2025,2026,2027]
        let half=TradingSession(openMinute:570,closeMinute:780)
        rules.sessionOverrides=Dictionary(uniqueKeysWithValues:["2025-07-03","2025-11-28","2025-12-24","2026-11-27","2026-12-24","2027-11-26"].map{($0,[half])})
        rules.source+="；NYSE2025–2027一般／提前收盤日曆；交割採本機營業日模型，非DTC完整日曆"
    }
}
