import SwiftUI
import ChaiTradeCore

struct MarketRefreshStatus:View {
    @EnvironmentObject var model:AppModel
    var instrument:Instrument?=nil
    @State private var refreshing=false
    private var quotes:[Quote]{if let i=instrument{return model.state?.quotes[i.quoteKey(board:i.usesTaiwanBoards ? model.selectedBoard:nil)].map{[$0]} ?? []};return model.visibleQuoteIDs.compactMap{model.state?.quotes[$0]}}
    var body:some View{VStack(alignment:.leading,spacing:6){
        HStack(alignment:.top){VStack(alignment:.leading,spacing:4){
            if model.state?.mode == .offline{Text("離線模擬 · 本地行情").font(.caption.weight(.medium))}
            else if refreshing || model.fetching{Label("正在更新行情",systemImage:"arrow.triangle.2.circlepath").font(.caption)}
            else{Text("自動更新開啟 · 優先目前與可見商品").font(.caption)}
            if let q=quotes.max(by:{$0.receivedAt<$1.receivedAt}){Text("最近成功："+Date(timeIntervalSince1970:TimeInterval(q.receivedAt)).formatted(date:.abbreviated,time:.standard)).font(.caption2).foregroundStyle(.secondary)}
            else{Text("尚未成功載入；各商品下方顯示來源狀態").font(.caption2).foregroundStyle(.secondary)}
        };Spacer();Button(refreshing ? "更新中":"刷新"){guard !refreshing else{return};refreshing=true;Task{await model.fetchQuotes();refreshing=false}}.disabled(refreshing).accessibilityIdentifier("refreshMarketQuotes")}
        if let i=instrument{
            if let q=quotes.first{Text("來源："+(model.state?.mode == .offline ? "ChaiTrade 本機模擬":q.source)+" · "+(model.state?.mode == .offline ? "模擬":q.quality == .realtime ? "即時":q.quality == .delayed ? "延遲":"快照")).font(.caption2).foregroundStyle(.secondary)}
            let status=model.status(for:i,board:i.usesTaiwanBoards ? model.selectedBoard:nil)
            if status != .ready{Text(status.label+"。"+status.nextStep).font(.caption).foregroundStyle(.orange)}
        }
        if model.state?.mode == .offline{Text("刷新只讀取目前模擬狀態，不推進時間或重新產生價格。").font(.caption2).foregroundStyle(.secondary)}
    }.accessibilityElement(children:.contain).accessibilityIdentifier("marketRefreshStatus")}
}
