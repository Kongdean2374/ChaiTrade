import SwiftUI
import UIKit
import ChaiTradeCore

private struct TradePickerFilter {
    var query="",category="全部",exchange="全部",asset="全部",currency="全部",availability="全部"
    var collection="全部"
}
struct TradeProductPicker:View {
    let onSelection:(Instrument)->Void
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var searching:Bool
    @State private var domain=MarketDomain.stocks
    @State private var filters:[MarketDomain:TradePickerFilter]=[:]
    @State private var initialized=false
    @State private var page=40
    private var defaults:TradePickerFilter{var f=TradePickerFilter();f.category=domain == .crypto ? "現貨":"全部";return f}
    private var current:TradePickerFilter{filters[domain] ?? defaults}
    private func value(_ key:WritableKeyPath<TradePickerFilter,String>)->Binding<String>{Binding(get:{current[keyPath:key]},set:{v in var f=current;f[keyPath:key]=v;filters[domain]=f;page=40})}
    private var pool:[Instrument]{(model.state?.instruments ?? []).filter{$0.market==domain && $0.asset != .index}}
    private var categories:[String]{domain == .stocks ? ["全部","台股","美股","ETF"]:domain == .crypto ? ["現貨","合約"]:["全部","外匯","期貨"]}
    private var recent:[String]{model.browsing[domain]?.recent ?? []}
    private var matching:[Instrument]{pool.filter{i in
        let f=current,query=f.query.trimmingCharacters(in:.whitespacesAndNewlines)
        if !query.isEmpty && ![i.name,i.symbol,i.id,i.identity?.exchange ?? ""].contains(where:{$0.localizedCaseInsensitiveContains(query)}){return false}
        let category:String=switch i.asset{case .taiwanStock:"台股";case .usStock:"美股";case .etf:"ETF";case .crypto:"現貨";case .perpetual:"合約";case .forex:"外匯";case .future:"期貨";case .index:"指數"}
        if f.category != "全部" && f.category != category{return false}
        if f.exchange != "全部" && f.exchange != (i.identity?.exchange ?? "自訂"){return false}
        if f.asset != "全部" && f.asset != i.asset.rawValue{return false}
        if f.currency != "全部" && f.currency != i.currency{return false}
        if f.collection == "自選" && model.state?.watchlist.contains(i.id) != true{return false}
        if f.collection == "最近查看" && !recent.contains(i.id){return false}
        if f.availability == "目前可交易" && !model.canTrade(i,board:i.usesTaiwanBoards ? .oddLot:nil){return false}
        if f.availability == "暫不可交易" && model.canTrade(i,board:i.usesTaiwanBoards ? .oddLot:nil){return false}
        return true
    }.sorted{a,b in
        if current.collection == "最近查看"{return (recent.firstIndex(of:a.id) ?? Int.max)<(recent.firstIndex(of:b.id) ?? Int.max)}
        return (a.identity?.legacy == true ? 1:0,a.symbol,a.id)<(b.identity?.legacy == true ? 1:0,b.symbol,b.id)
    }}
    var body:some View{List{
        Section{
            Picker("市場",selection:$domain){ForEach(MarketDomain.allCases,id:\.self){Text($0.label)}}.accessibilityIdentifier("tradePickerMarket")
            TextField("搜尋名稱、代碼或交易所",text:value(\.query)).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searching).submitLabel(.search).onSubmit{searching=false}.accessibilityIdentifier("tradePickerSearch")
            if !searching{Picker("分類",selection:value(\.category)){ForEach(categories,id:\.self){Text($0)}}.accessibilityIdentifier("tradePickerCategory")
            Picker("商品集合",selection:value(\.collection)){ForEach(["全部","自選","最近查看"],id:\.self){Text($0)}}
            DisclosureGroup("更多篩選"){
                Picker("交易所",selection:value(\.exchange)){ForEach(["全部"]+Set(pool.map{$0.identity?.exchange ?? "自訂"}).sorted(),id:\.self){Text($0)}}
                Picker("商品類型",selection:value(\.asset)){Text("全部").tag("全部");ForEach(AssetClass.allCases.filter{a in pool.contains{$0.asset==a}},id:\.self){Text($0.label).tag($0.rawValue)}}
                Picker("報價幣別",selection:value(\.currency)){ForEach(["全部"]+Set(pool.map(\.currency)).sorted(),id:\.self){Text($0)}}
                Picker("可交易狀態",selection:value(\.availability)){ForEach(["全部","目前可交易","暫不可交易"],id:\.self){Text($0)}}
            }.accessibilityIdentifier("tradePickerFilters")}
            HStack{Text("符合 \(matching.count) 個商品").accessibilityIdentifier("tradePickerCount");Spacer();Button("清除篩選"){filters[domain]=defaults;page=40}.accessibilityIdentifier("tradePickerClear")}.font(.subheadline)
            if searching{Button("顯示搜尋結果"){searching=false}.accessibilityIdentifier("tradePickerFinishSearch")}
            if !searching{Text("選取商品只更新表單；不會切換 A／B 帳戶或自動送單。行情權限與開市狀態會再次檢查。").font(.caption).foregroundStyle(.secondary)}
        }
        Section{
            if matching.isEmpty{ContentUnavailableView("沒有符合的商品",systemImage:"magnifyingglass",description:Text("調整搜尋、商品集合或篩選；也可清除篩選重新探索。"))}
            ForEach(Array(matching.prefix(page))){i in
                MarketProductRow(instrument:i,owner:"tradePicker",onSelection:{onSelection(i);dismiss()})
            }
            if matching.count>page{Button("載入更多（\(page)／\(matching.count)）"){page+=40}}
        }
    }.navigationTitle("選擇交易商品").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.immediately)
        .toolbar{ToolbarItem(placement:.topBarTrailing){Button("取消"){dismiss()}};ToolbarItemGroup(placement:.keyboard){Spacer();Button("完成商品搜尋"){searching=false}}}
        .onAppear{guard !initialized else{return};initialized=true;domain=model.tradeInstrument?.market ?? .stocks}
        .onChange(of:domain){_,_ in page=40;model.removeVisibleOwner("tradePicker")}
        .onDisappear{model.removeVisibleOwner("tradePicker")}
    }
}
