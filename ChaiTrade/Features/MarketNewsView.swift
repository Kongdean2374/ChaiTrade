import SwiftUI
import ChaiTradeCore

extension AppModel{
    var filteredNews:[MarketNewsStory]{
        let eligible=Set((state?.instruments ?? []).filter{$0.market==market && (market != .crypto || (currentBrowsing.category == "合約" ? $0.asset == .perpetual:$0.asset == .crypto))}.map(\.id))
        return marketNews.filter{story in
            guard story.publishedAt<=now,story.markets.contains(market),story.origin == (state?.mode == .offline ? .simulated:.real) else{return false}
            if !story.instrumentIDs.isEmpty && eligible.isDisjoint(with:story.instrumentIDs){return false}
            if currentBrowsing.newsFavoritesOnly{return !Set(state?.watchlist ?? []).intersection(story.instrumentIDs).isEmpty}
            return true
        }
    }
}
struct MarketNewsCard:View{
    let story:MarketNewsStory
    var body:some View{MarketCard{
        Text(story.label).font(.caption.weight(.bold)).foregroundStyle(story.origin == .simulated ? Color.orange:Color.secondary)
        Text(story.title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
        Text(story.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
        HStack{Text(story.source);Spacer();Text(Date(timeIntervalSince1970:TimeInterval(story.publishedAt)).formatted(date:.abbreviated,time:.shortened))}.font(.caption2).foregroundStyle(.secondary)
    }.accessibilityElement(children:.combine)}
}
struct MarketNewsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{ScrollView{LazyVStack(alignment:.leading,spacing:16){
        Text(model.market.label+"新聞").font(.largeTitle.bold())
        Toggle("只看自選相關",isOn:Binding(get:{model.currentBrowsing.newsFavoritesOnly},set:{v in model.editBrowsing(model.market){$0.newsFavoritesOnly=v}})).accessibilityIdentifier("newsFavorites")
        if model.state?.mode == .offline{Text("模擬情境，非真實新聞。依本機種子與模擬時間產生；未發布的事件不會預先顯示。").font(.footnote).foregroundStyle(.orange)}else{Text("來源提供的標題與摘要，點入可看原文。官方總體新聞與自選公司新聞分開標明；無公司新聞授權時不會捏造公告。").font(.footnote).foregroundStyle(.secondary)}
        if model.newsLoading{ProgressView("載入新聞…")}
        if let issue=model.newsIssue{Text(issue).font(.caption).foregroundStyle(.orange)}
        if model.filteredNews.isEmpty && !model.newsLoading{ContentUnavailableView("目前沒有符合的新聞",systemImage:"newspaper",description:Text(model.currentBrowsing.newsFavoritesOnly ? "可關閉自選篩選查看此市場的其他新聞。":"可稍後重試，或前往行情連線查看來源權限。"))}
        ForEach(model.filteredNews){story in NavigationLink{MarketNewsDetail(story:story)}label:{MarketNewsCard(story:story)}.buttonStyle(.plain).accessibilityIdentifier("news-"+story.id)}
        Text("已到新聞列表底部").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity).accessibilityIdentifier("newsBottom")
    }.padding(18)}.background(Color(.systemGroupedBackground)).navigationTitle("新聞").toolbar{Button("重新整理"){Task{await model.loadNews(force:true)}}}.task{await model.loadNews()}}
}
struct MarketNewsDetail:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.openURL) private var openURL
    let story:MarketNewsStory
    @State private var confirmExternal=false
    var body:some View{ScrollView{VStack(alignment:.leading,spacing:20){
        Text(story.label).font(.headline).foregroundStyle(story.origin == .simulated ? Color.orange:Color.secondary)
        Text(story.title).font(.title.bold())
        Text(story.source+" · "+Date(timeIntervalSince1970:TimeInterval(story.publishedAt)).formatted()).font(.caption).foregroundStyle(.secondary)
        Text(story.summary).font(.body).textSelection(.enabled)
        if story.origin == .simulated{
            MarketCard{Text("情境作用與追查").font(.headline);Text("模擬情境，非真實新聞。這不是實際公司公告，事件影響只存在於這個離線帳戶。").font(.subheadline).foregroundStyle(.orange)
                if let ends=story.endsAt{LabeledContent("作用至",value:Date(timeIntervalSince1970:TimeInterval(ends)).formatted())}
                if let factor=story.logPriceImpact{LabeledContent("價格因子幅度",value:String(format:"%+.2f%%",factor*100))}
                if let volume=story.volumeMultiplier{LabeledContent("成交量因子",value:String(format:"%.2f×",volume))}
                if let liquidity=story.liquidityMultiplier{LabeledContent("流動性因子",value:String(format:"%.2f×",liquidity))}
                Text("其他市場因子可能抵銷方向；股息與分割另依事件帳務處理。相關行情、成交及帳務以事件 ID 追查。").font(.caption).foregroundStyle(.secondary)
                Text(story.id).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("newsEventID")
            }
        }else if let url=story.url{Button("閱讀來源原文"){confirmExternal=true}.buttonStyle(.borderedProminent);Text(url.host ?? "").font(.caption).foregroundStyle(.secondary)}
        let related=(model.state?.instruments ?? []).filter{story.instrumentIDs.contains($0.id) && $0.market==model.market}
        if !related.isEmpty{Text("關聯商品").font(.headline);ForEach(Array(related.prefix(12))){i in MarketProductRow(instrument:i,owner:"newsDetail")}}else{Text("總體市場新聞；未指定個別商品。").font(.caption).foregroundStyle(.secondary)}
    }.padding(18)}.background(Color(.systemGroupedBackground)).navigationTitle("新聞詳情").navigationBarTitleDisplayMode(.inline).onDisappear{model.removeVisibleOwner("newsDetail")}
        .confirmationDialog("開啟新聞來源網站？",isPresented:$confirmExternal,titleVisibility:.visible){Button("開啟來源原文"){if let url=story.url{openURL(url)}}}
    }
}
struct MarketCalendarView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    var body:some View{List{
        Section("已公開的市場事件"){
            if model.state?.mode == .offline{Text("模擬情境，非真實新聞。只列已發布的股息／分割與財報情境；不提前揭露未來生成事件。").font(.footnote).foregroundStyle(.orange)}else{Text("真實財報與除息日曆需要合法可用的專門來源；目前未設定授權，不以預測或固定文字代替真實公告。").font(.footnote).foregroundStyle(.secondary)}
            let stories=model.filteredNews.filter{["earnings","dividend","split"].contains($0.kind)}
            if stories.isEmpty{Text("目前沒有已取得的日曆事件").foregroundStyle(.secondary)}
            ForEach(stories){story in NavigationLink{MarketNewsDetail(story:story)}label:{VStack(alignment:.leading,spacing:6){Text(story.label).font(.caption).foregroundStyle(.orange);Text(story.title);Text(Date(timeIntervalSince1970:TimeInterval(story.publishedAt)).formatted()).font(.caption).foregroundStyle(.secondary)}}}
        }
    }.navigationTitle("市場日曆").toolbar{Button("完成"){dismiss()}}.task{await model.loadNews()}}
}
