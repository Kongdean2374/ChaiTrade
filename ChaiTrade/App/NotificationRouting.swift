import SwiftUI
import ChaiTradeCore

@MainActor final class NoticeTapMailbox:ObservableObject{
    static let shared=NoticeTapMailbox()
    @Published var pending:NoticeLink?
}
extension AppModel{
    func handleNoticeLink(_ link:NoticeLink)async{
        guard let engine,let context else{settings.pendingNotice=link;saveSettings();return}
        guard context.accountID==link.accountID else{requestedAccountNotice=link;return}
        do{
            let destination=try await engine.noticeDestination(link,context:context)
            guard self.context==context else{return}
            settings.pendingNotice=nil;saveSettings()
            if let instrument=destination.instrument{selectProduct(instrument)}
            openedNotice=destination
        }catch{self.error=error.localizedDescription}
    }
    func queueNoticeAccountSwitch(_ link:NoticeLink){
        settings.pendingMode=link.mode == settings.activeMode ? nil:link.mode
        settings.pendingNotice=link;saveSettings();requestedAccountNotice=nil
        notice="已記錄通知目的地；完整關閉再啟動後才切換獨立帳戶。"
    }
}
struct AccountInboxView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{
        Section{Text("只顯示目前帳戶最近的成交、價格提醒、保證金風險與監控事件。系統通知未授權仍可在這裡查看；不保證背景即時監控。").font(.footnote).foregroundStyle(.secondary)}
        if (model.state?.inbox ?? []).isEmpty{ContentUnavailableView("目前沒有通知",systemImage:"bell",description:Text("可在商品頁建立到價或百分比提醒。"))}
        ForEach(Array((model.state?.inbox ?? []).reversed())){notice in Button{
            guard let link=try? NoticeLink(accountID:notice.accountID,eventID:notice.event.id) else{return};Task{await model.handleNoticeLink(link)}
        }label:{VStack(alignment:.leading,spacing:6){
            Text(notice.event.message).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
            Text((notice.discoveredDuringCatchup ? "補算發現 · ":"")+Date(timeIntervalSince1970:TimeInterval(notice.event.time)).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
        }}}
    }.navigationTitle("通知中心")}
}
struct NoticeDetailView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    let destination:NoticeDestination
    var body:some View{List{
        Text("本機模擬帳戶事件").font(.caption).foregroundStyle(.orange)
        Text(destination.event.message).textSelection(.enabled)
        LabeledContent("事件時間",value:Date(timeIntervalSince1970:TimeInterval(destination.event.time)).formatted())
        LabeledContent("事件 ID",value:destination.event.id).font(.caption)
        if let order=destination.event.orderID{Text("委託："+order).font(.caption.monospaced());Button("查看委託與成交"){model.tab=3;dismiss()}}
        if let instrument=destination.instrument{Button("查看 "+instrument.name){model.selectProduct(instrument);dismiss()}}
    }.navigationTitle("通知詳情").toolbar{Button("完成"){dismiss()}}}
}
