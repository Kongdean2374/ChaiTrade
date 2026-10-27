import Foundation
import UserNotifications
import ChaiTradeCore

private final class NoticePresenter:NSObject,UNUserNotificationCenterDelegate,@unchecked Sendable{
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification)async->UNNotificationPresentationOptions{[.banner,.list]}
}
@MainActor final class LocalNotifications {
    private let center=UNUserNotificationCenter.current()
    private let presenter=NoticePresenter()
    init(){center.delegate=presenter}
    func requestPermission()async throws->Bool{try await center.requestAuthorization(options:[.alert,.sound,.badge])}
    func deliver(_ notices:[LocalNotice],context:AccountContext)async throws->Set<String>{
        let authorized:Bool=await withCheckedContinuation{c in center.getNotificationSettings{settings in c.resume(returning:settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)}}
        guard authorized else{return Set(notices.map(\.id))}
        let delivered:Set<String>=await withCheckedContinuation{c in center.getDeliveredNotifications{values in c.resume(returning:Set(values.map{$0.request.identifier}))}}
        let pending:Set<String>=await withCheckedContinuation{c in center.getPendingNotificationRequests{values in c.resume(returning:Set(values.map(\.identifier)))}}
        var acknowledged=Set<String>()
        for notice in notices where !notice.delivered && notice.accountID==context.accountID{
            if !delivered.contains(notice.id) && !pending.contains(notice.id){
                let content=UNMutableNotificationContent()
                content.title=notice.discoveredDuringCatchup ? "ChaiTrade · 補算發現（模擬）":"ChaiTrade · 模擬交易"
                content.body="\(notice.event.message)\n\(context.mode.label) · 事件時間 \(notice.event.time)"
                content.threadIdentifier=context.accountID
                content.userInfo=["account":context.accountID,"event":notice.event.id]
                try await center.add(UNNotificationRequest(identifier:notice.id,content:content,trigger:nil))
            }
            acknowledged.insert(notice.id)
        }
        return acknowledged
    }
}
