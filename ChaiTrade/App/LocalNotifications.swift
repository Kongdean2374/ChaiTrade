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
        let settings=await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else{return Set(notices.map(\.id))}
        let delivered=Set(await center.deliveredNotifications().map{ $0.request.identifier })
        let pending=Set(await center.pendingNotificationRequests().map(\.identifier))
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
