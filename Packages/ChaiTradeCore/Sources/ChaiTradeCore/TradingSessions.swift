import Foundation

public struct TradingSession:Codable,Equatable,Sendable{
    public var openMinute:Int
    public var closeMinute:Int
    /// Calendar weekdays of the session's start date (Sunday=1), including overnight sessions.
    public var weekdays:[Int]?
    public init(openMinute:Int,closeMinute:Int,weekdays:[Int]?=nil){self.openMinute=openMinute;self.closeMinute=closeMinute;self.weekdays=weekdays?.sorted()}
}
public enum TradingSessions{
    static func calendar(_ rules:RulePack)->Calendar{var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:rules.timeZone) ?? .gmt;return calendar}
    static func key(_ date:Date,calendar:Calendar)->String{let p=calendar.dateComponents([.year,.month,.day],from:date);return String(format:"%04d-%02d-%02d",p.year!,p.month!,p.day!)}
    public static func intervals(anchorDay:Date,rules:RulePack)->[(start:Int64,end:Int64)]{
        let calendar=calendar(rules),date=calendar.startOfDay(for:anchorDay),key=key(date,calendar:calendar)
        guard !rules.holidays.contains(key) else{return []}
        let sessions=rules.sessionOverrides?[key] ?? rules.sessions ?? [TradingSession(openMinute:rules.openMinute,closeMinute:rules.closeMinute)]
        let weekday=calendar.component(.weekday,from:date)
        var result:[(Int64,Int64)]=[]
        for session in sessions{
            if let weekdays=session.weekdays{if !weekdays.contains(weekday){continue}}else if rules.weekdaysOnly && [1,7].contains(weekday){continue}
            guard (0..<1440).contains(session.openMinute),(0...1440).contains(session.closeMinute),session.openMinute != session.closeMinute else{continue}
            guard let open=calendar.date(bySettingHour:session.openMinute/60,minute:session.openMinute%60,second:0,of:date,matchingPolicy:.nextTime,repeatedTimePolicy:.first,direction:.forward) else{continue}
            let nextDay=calendar.date(byAdding:.day,value:1,to:date)!
            let close:Date
            if session.closeMinute==1440{close=nextDay}else{
                let target=session.closeMinute<session.openMinute ? nextDay:date
                guard let value=calendar.date(bySettingHour:session.closeMinute/60,minute:session.closeMinute%60,second:0,of:target,matchingPolicy:.nextTime,repeatedTimePolicy:.last,direction:.forward) else{continue};close=value
            }
            let end=min(Int64(close.timeIntervalSince1970),rules.expiry ?? Int64.max),start=Int64(open.timeIntervalSince1970)
            if end>start{result.append((start,end))}
        }
        return result.sorted{$0.0<$1.0}
    }
    public static func isOpen(_ rules:RulePack,at time:Int64)->Bool{
        if let expiry=rules.expiry,time>=expiry{return false}
        let calendar=calendar(rules),date=Date(timeIntervalSince1970:TimeInterval(time))
        for offset in [0,-1]{
            let anchor=calendar.date(byAdding:.day,value:offset,to:date)!
            if intervals(anchorDay:anchor,rules:rules).contains(where:{$0.start<=time && time<$0.end}){return true}
        }
        return false
    }
    public static func previousOpen(before:Int64,rules:RulePack)throws->Int64?{
        let calendar=calendar(rules),cursor=min(before-Simulation.step,rules.expiry.map{$0-Simulation.step} ?? Int64.max)
        var day=calendar.startOfDay(for:Date(timeIntervalSince1970:TimeInterval(cursor)))
        for _ in 0..<3700{
            try Task.checkCancellation()
            let previous=calendar.date(byAdding:.day,value:-1,to:day)!
            let candidates=(intervals(anchorDay:day,rules:rules)+intervals(anchorDay:previous,rules:rules)).compactMap{interval->Int64? in
                let value=min(cursor,interval.end-Simulation.step)
                return value>=interval.start ? value:nil
            }
            if let result=candidates.max(){return result}
            day=previous
        }
        return nil
    }
    public static func validate(_ rules:RulePack)throws{
        let all=(rules.sessions ?? [])+(rules.sessionOverrides ?? [:]).values.flatMap{$0}
        guard (rules.sessions?.count ?? 0)<=8,(rules.sessionOverrides?.count ?? 0)<=3660,all.allSatisfy({(0..<1440).contains($0.openMinute) && (0...1440).contains($0.closeMinute) && $0.openMinute != $0.closeMinute && ($0.weekdays.map{!$0.isEmpty && Set($0).count==$0.count && $0.allSatisfy{(1...7).contains($0)}} ?? true)}) else{throw TradeError.invalid("市場交易時段設定不合法")}
        let calendar=calendar(rules)
        for day in Array((rules.sessionOverrides ?? [:]).keys)+rules.holidays+(rules.settlementHolidays ?? []){
            let fields=day.split(separator:"-").compactMap{Int($0)}
            guard day.range(of:#"^\d{4}-\d{2}-\d{2}$"#,options:.regularExpression) != nil,fields.count==3,let date=calendar.date(from:DateComponents(year:fields[0],month:fields[1],day:fields[2])),key(date,calendar:calendar)==day else{throw TradeError.invalid("特殊交易日或假日日期不合法")}
        }
    }
}
