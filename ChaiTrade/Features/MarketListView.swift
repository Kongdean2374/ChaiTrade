import SwiftUI
import ChaiTradeCore

struct MarketsView:View {
    @EnvironmentObject var model:AppModel
    let domain:MarketDomain
    @State private var pageSize=40
    @FocusState private var searching:Bool
    @State private var catalog=false
    @State private var groups=false
    @State private var custom=false
    private var preferences:MarketBrowsingState{model.browsing[domain] ?? MarketBrowsingState()}
    private var categories:[String]{domain == .stocks ? ["全部","台股","美股","ETF"]:domain == .crypto ? ["現貨","合約"]:["全部","外匯","期貨"]}
    private var products:[Instrument]{
        var pool=(model.state?.instruments ?? []).filter{domain.contains($0) && $0.asset != .index && $0.identity?.legacy != true}
        let category=preferences.category
        pool=pool.filter{i in
            if domain == .crypto{return category == "合約" ? i.asset == .perpetual:i.asset == .crypto}
            switch category{case "台股":return i.asset == .taiwanStock;case "美股":return i.asset == .usStock;case "ETF":return i.asset == .etf;case "外匯":return i.asset == .forex;case "期貨":return i.asset == .future;default:return true}
        }
        if preferences.favoritesOnly{pool=pool.filter{model.state?.watchlist.contains($0.id)==true}}
        if let groupID=preferences.groupID,let group=model.state?.productPreferences?.groups.first(where:{$0.id==groupID}){pool=pool.filter{group.instrumentIDs.contains($0.id)}}
        let query=preferences.search.trimmingCharacters(in:.whitespacesAndNewlines)
        if !query.isEmpty{pool=pool.filter{[$0.symbol,$0.name,$0.id,$0.identity?.exchange ?? ""].contains{$0.localizedCaseInsensitiveContains(query)}}}
        if [.gainers,.losers].contains(preferences.sort){pool=pool.filter{(model.summary(for:$0)?.reference ?? .zero) > .zero && model.state?.quotes[$0.id] != nil}}
        if preferences.sort == .volume{pool=pool.filter{model.summary(for:$0)?.volume != nil}}
        return pool.sorted{a,b in
            switch preferences.sort{
            case .name:return (a.symbol,a.id)<(b.symbol,b.id)
            case .gainers,.losers:
                let aa=changeRatio(a),bb=changeRatio(b)
                return aa==bb ? a.id<b.id:preferences.sort == .gainers ? aa>bb:aa<bb
            case .volume:
                let aa=model.summary(for:a)?.volume ?? .zero,bb=model.summary(for:b)?.volume ?? .zero
                return aa==bb ? a.id<b.id:aa>bb
            case .familiar:
                let priority=["2330","0050","2317","2454","AAPL","MSFT","BTC-USD","ETH-USD","SOL-USD","EUR/USD"]
                return (priority.firstIndex(of:a.symbol) ?? 100,a.symbol,a.id)<(priority.firstIndex(of:b.symbol) ?? 100,b.symbol,b.id)
            }
        }
    }
    private func changeRatio(_ i:Instrument)->Amount{guard let quote=model.state?.quotes[i.id],let reference=model.summary(for:i)?.reference,reference > .zero else{return .zero};return (try? quote.last/reference) ?? .zero}
    private var search:Binding<String>{Binding(get:{preferences.search},set:{text in model.editBrowsing(domain){$0.search=text;$0.scrollID=nil};pageSize=40})}
    private var scroll:Binding<String?>{Binding(get:{preferences.scrollID},set:{id in model.editBrowsing(domain){$0.scrollID=id}})}
    var body:some View{
        ScrollView{
            LazyVStack(alignment:.leading,spacing:14){
                VStack(alignment:.leading,spacing:12){
                    HStack{Text(domain.label).font(.largeTitle.bold());Spacer();Button{catalog=true}label:{Label("商品目錄",systemImage:"books.vertical")}.accessibilityIdentifier("openCatalog")}
                    HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("代碼或名稱，例如 BTC、ETH、2330",text:search).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searching).submitLabel(.search).onSubmit{searching=false}.accessibilityIdentifier("marketSearch");if !search.wrappedValue.isEmpty{Button{search.wrappedValue=""}label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel("清除搜尋")}}
                        .padding(12).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12))
                    ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(categories,id:\.self){category in Button(category){model.editBrowsing(domain){$0.category=category;$0.scrollID=nil};pageSize=40}.buttonStyle(.bordered).tint(preferences.category==category || (domain == .crypto && preferences.category == "全部" && category == "現貨") ? .orange:.gray)}}}
                    HStack{
                        Toggle("自選",isOn:Binding(get:{preferences.favoritesOnly},set:{value in model.editBrowsing(domain){$0.favoritesOnly=value;$0.scrollID=nil}})).toggleStyle(.button).accessibilityIdentifier("marketFavorites")
                        Menu{ForEach(MarketSort.allCases,id:\.self){sort in Button(sort.label){model.editBrowsing(domain){$0.sort=sort;$0.scrollID=nil};pageSize=40}}}label:{Label(preferences.sort.label,systemImage:"arrow.up.arrow.down")}
                        Spacer();Button{groups=true}label:{Label("分組",systemImage:"folder")}
                    }.font(.subheadline)
                    if let groupID=preferences.groupID,let group=model.state?.productPreferences?.groups.first(where:{$0.id==groupID}){HStack{Text("分組："+group.name);Spacer();Button("清除"){model.editBrowsing(domain){$0.groupID=nil}}}.font(.caption)}
                    Text("範圍：目前商品目錄的 \(products.count) 個符合項目；排行只納入已取得對應統計的商品，並非完整市場。").font(.caption).foregroundStyle(.secondary)
                    if domain == .crypto{Text(preferences.category == "合約" ? "合約另有槓桿、保證金與強平風險。":"現貨以幣數買入／賣出；不包含合約。 ").font(.caption).foregroundStyle(.secondary)}
                }.id("marketTop")
                if preferences.search.isEmpty && !preferences.favoritesOnly && preferences.sort == .familiar{recentProducts}
                if products.isEmpty{ContentUnavailableView("沒有符合的商品",systemImage:"magnifyingglass",description:Text("調整搜尋或分類，也可從商品目錄查看來源支援範圍。"));Button("清除篩選"){model.editBrowsing(domain){$0.search="";$0.favoritesOnly=false;$0.groupID=nil;$0.sort = .familiar;$0.category=domain == .crypto ? "現貨":"全部"}}}
                ForEach(Array(products.prefix(pageSize))){instrument in
                    MarketProductRow(instrument:instrument,owner:"markets-"+domain.rawValue).padding(.horizontal,12).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12)).id(instrument.id)
                }
                if products.count>pageSize{Button("載入更多（已顯示 \(pageSize)／\(products.count)）"){pageSize+=40}.frame(maxWidth:.infinity)}
                if (model.state?.instruments ?? []).contains(where:{$0.identity?.legacy==true && $0.market==domain}){NavigationLink("舊版自訂商品與原有身份"){LegacyProductsView()}.font(.footnote)}
                Text("已到目前列表底部").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity).accessibilityIdentifier("marketBottom")
            }.scrollTargetLayout().padding(16).padding(.bottom,20)
        }.scrollPosition(id:scroll,anchor:.top).scrollDismissesKeyboard(.interactively).background(Color(.systemGroupedBackground)).navigationTitle("行情").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$catalog){NavigationStack{ProductCatalogView()}}
            .sheet(isPresented:$groups){NavigationStack{WatchGroupsView()}}
            .task(id:domain){if let id=preferences.scrollID,let index=products.firstIndex(where:{$0.id==id}){pageSize=max(40,(index/40+1)*40)};await model.ensureQuoteService()}
            .onChange(of:model.tab){_,tab in if tab != 1{searching=false}}
            .onDisappear{searching=false;model.removeVisibleOwner("markets-"+domain.rawValue)}
    }
    @ViewBuilder private var recentProducts:some View{
        let recent=preferences.recent.compactMap{id in model.state?.instruments.first{$0.id==id && $0.market==domain}}
        if !recent.isEmpty{ScrollView(.horizontal,showsIndicators:false){HStack{Text("最近瀏覽").font(.caption).foregroundStyle(.secondary);ForEach(Array(recent.prefix(8))){i in Button(i.symbol){model.select(i)}.font(.caption).buttonStyle(.bordered)}}}}
    }
}
struct ProductCatalogView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    var body:some View{List{
        Section("內建商品"){
            Text("股票、ETF、加密現貨、合約、外匯與期貨均有獨立身份；相同代碼在不同交易所不會合併。")
            LabeledContent("目前商品數",value:String(model.state?.instruments.filter{$0.identity?.legacy != true}.count ?? 0))
            Text(model.state?.mode == .offline ? "內建真實名稱與代碼，價格、新聞及成交全為離線模擬。飛航模式也可探索。":"目錄有商品身份不代表已取得即時行情或交易規則授權。請查看每個商品的狀態。").font(.caption)
        }
        if model.state?.mode == .online{Section("從來源更新商品目錄"){
            NavigationLink("搜尋官方美股／ETF目錄"){USStockDiscoveryView()}
            ForEach(ProviderID.allCases,id:\.self){id in NavigationLink(id.label){ProviderSettings(id:id)}}
            Text("來源頁會說明支援市場、權限與限制。更新採加入及核對身份；不改寫既有部位成別的商品。").font(.caption)
        }}else{Section{NavigationLink("自訂離線商品"){CustomInstrumentView()};NavigationLink("舊版自訂商品"){LegacyProductsView()}}}
        Section("尋找商品"){Text("關閉此頁後，在行情頁搜尋 BTC、ETH、2330 或 0050。可依市場、分類、自選及分組篩選。").font(.subheadline)}
    }.navigationTitle("商品目錄").toolbar{Button("完成"){dismiss()}}}
}
struct LegacyProductsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{Section{Text("這些是先前建立的自訂模擬商品，名稱與身份維持原樣，部位、委託、價格與歷史均保留。新目錄商品另外建立，不會把原有資產換成另一支股票。").font(.footnote)};ForEach((model.state?.instruments ?? []).filter{$0.identity?.legacy==true && $0.market==model.market}){i in MarketProductRow(instrument:i,owner:"legacy")}}.navigationTitle("舊版商品").onDisappear{model.removeVisibleOwner("legacy")}}
}
struct WatchGroupsView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name=""
    @State private var saving=false
    var body:some View{List{
        Section("\(model.market.label)自選分組"){
            ForEach((model.state?.productPreferences?.groups ?? []).filter{$0.market==model.market}){group in NavigationLink{WatchGroupEditor(group:group,onBrowse:{dismiss()})}label:{HStack{Text(group.name);Spacer();Text("\(group.instrumentIDs.count)").foregroundStyle(.secondary)}}}
            TextField("新分組名稱",text:$name)
            Button("建立分組"){guard !saving,let engine=model.engine,let context=model.context else{return};saving=true;let group=WatchGroup(name:name,market:model.market);Task{defer{saving=false};if await model.run({try await engine.saveWatchGroup(group,context:context)}){name=""}}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || saving)
        }
    }.navigationTitle("自選分組").toolbar{Button("完成"){dismiss()}}}
}
struct WatchGroupEditor:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    let group:WatchGroup
    var onBrowse:()->Void
    @State private var selected:Set<String>=[]
    @State private var name=""
    @State private var saving=false
    @State private var deleting=false
    var body:some View{List{
        Section{
            TextField("分組名稱",text:$name)
            Button("在行情頁查看此組"){model.editBrowsing(group.market){$0.groupID=group.id;$0.favoritesOnly=false;$0.search="";$0.category=group.market == .crypto ? "現貨":"全部"};model.tab=1;onBrowse()}
            Text("挑選這個市場中要放入分組的商品。").font(.caption)
        }
        ForEach((model.state?.instruments ?? []).filter{$0.market==group.market && $0.asset != .index}){i in Toggle(i.name+" · "+i.symbol,isOn:Binding(get:{selected.contains(i.id)},set:{value in if value{selected.insert(i.id)}else{selected.remove(i.id)}}))}
        Button(saving ? "保存中…":"保存分組"){
            guard !saving,let engine=model.engine,let context=model.context else{return};saving=true
            var value=group;value.name=name.trimmingCharacters(in:.whitespacesAndNewlines);value.instrumentIDs=selected.sorted()
            Task{defer{saving=false};if await model.run({try await engine.saveWatchGroup(value,context:context)}){dismiss()}}
        }.disabled(saving || model.interactionBlocked || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        Section{Button("刪除分組",role:.destructive){deleting=true};Text("只刪除此分組，商品的自選狀態與持倉會保留。").font(.caption)}
    }.navigationTitle(name.isEmpty ? group.name:name).onAppear{selected=Set(group.instrumentIDs);name=group.name}
        .confirmationDialog("刪除這個自選分組？",isPresented:$deleting,titleVisibility:.visible){Button("刪除分組",role:.destructive){
            guard !saving,let engine=model.engine,let context=model.context else{return};saving=true
            Task{defer{saving=false};if await model.run({try await engine.removeWatchGroup(id:group.id,context:context)}){model.editBrowsing(group.market){if $0.groupID==group.id{$0.groupID=nil}};dismiss()}}
        };Button("取消",role:.cancel){}}
}
}
