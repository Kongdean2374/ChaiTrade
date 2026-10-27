import Foundation

/// Exchange-local calendar boundaries. A month is never a fixed 30-day duration.
public enum CandleCalendar {
    private static func calendar(_ zone:String)->Calendar{
        var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:zone) ?? .gmt;c.firstWeekday=2;c.minimumDaysInFirstWeek=4;return c
    }
    public static func start(_ time:Int64,interval:Int64,zone:String)->Int64{
        guard interval>=86400 else{return Int64(floor(Double(time)/Double(interval)))*interval}
        let c=calendar(zone),date=Date(timeIntervalSince1970:TimeInterval(time))
        let component:Calendar.Component=interval==604800 ? .weekOfYear:interval==2592000 ? .month:.day
        return Int64(c.dateInterval(of:component,for:date)!.start.timeIntervalSince1970)
    }
    public static func next(_ start:Int64,interval:Int64,zone:String,offset:Int=1)->Int64{
        guard interval>=86400 else{return start+Int64(offset)*interval}
        let component:Calendar.Component=interval==604800 ? .weekOfYear:interval==2592000 ? .month:.day
        return Int64(calendar(zone).date(byAdding:component,value:offset,to:Date(timeIntervalSince1970:TimeInterval(start)))!.timeIntervalSince1970)
    }
    public static func aggregate(_ candles:[Candle],interval:Int64,zone:String,now:Int64)->[Candle]{
        var result:[Candle]=[]
        for c in candles.sorted(by:{$0.time<$1.time}) where c.time<=now{
            let bucket=start(c.time,interval:interval,zone:zone),end=next(bucket,interval:interval,zone:zone)
            if result.last?.time==bucket{
                var x=result.removeLast();x.high=max(x.high,c.high);x.low=min(x.low,c.low);x.close=c.close
                x.volume=x.volume.flatMap{a in c.volume.map{a+$0}};x.complete=x.complete && c.complete && end<=now;result.append(x)
            }else{result.append(Candle(time:bucket,open:c.open,high:c.high,low:c.low,close:c.close,volume:c.volume,complete:c.complete && end<=now))}
        }
        return result
    }
}
