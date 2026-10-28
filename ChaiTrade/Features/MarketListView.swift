import SwiftUI
import ChaiTradeCore

struct MarketsView:View {
    @EnvironmentObject var model:AppModel
    let domain:MarketDomain
    @State private var pageSize=40
    @State private var searchText=""
    @State private var searchInitialized=false
    @FocusState private var searching:Bool
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
        let query=searchText.trimmingCharacters(in:.whitespacesAndNewlines)
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
    private var search:Binding<String>{Binding(get:{searchText},set:{text in searchText=text;pageSize=40})}
    private var scroll:Binding<String?>{Binding(get:{preferences.scrollID},set:{id in guard model.tab==1,(model.marketPaths[domain] ?? []).isEmpty else{return};model.editBrowsing(domain){$0.scrollID=id}})}
    var body:some View{
        ScrollView{
            LazyVStack(alignment:.leading,spacing:14){
                VStack(alignment:.leading,spacing:12){
                    if !searching{HStack{Text(domain.label).font(.largeTitle.bold());Spacer();Button{model.catalogVisible=true}label:{Label("商品目錄",systemImage:"books.vertical")}.accessibilityIdentifier("openCatalog")}}
                    HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("代碼或名稱，例如 BTC、ETH、2330",text:search).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searching).submitLabel(.search).onSubmit{searching=false}.accessibilityIdentifier("marketSearch");if !search.wrappedValue.isEmpty{Button{searching=false;search.wrappedValue=""}label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel("清除搜尋")}}
                        .padding(12).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12))
                    ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(categories,id:\.self){category in Button(category){searching=false;model.editBrowsing(domain){$0.category=category;$0.scrollID=nil};pageSize=40}.buttonStyle(.bordered).tint(preferences.category==category || (domain == .crypto && preferences.category == "全部" && category == "現貨") ? .orange:.gray)}}}
                    if searching{HStack{Text("目前目錄：\(products.count)個符合項目").font(.caption).foregroundStyle(.secondary);Spacer();Button("取消搜尋鍵盤"){searching=false}.font(.caption)}}
                    if !searching{HStack{
                        Toggle("自選",isOn:Binding(get:{preferences.favoritesOnly},set:{value in model.editBrowsing(domain){$0.favoritesOnly=value;$0.scrollID=nil}})).toggleStyle(.button).accessibilityIdentifier("marketFavorites")
                        Menu{ForEach(MarketSort.allCases,id:\.self){sort in Button(sort.label){model.editBrowsing(domain){$0.sort=sort;$0.scrollID=nil};pageSize=40}}}label:{Label(preferences.sort.label,systemImage:"arrow.up.arrow.down")}
                        Spacer();Button{groups=true}label:{Label("分組",systemImage:"folder")}
                    }.font(.subheadline)
                    if let groupID=preferences.groupID,let group=model.state?.productPreferences?.groups.first(where:{$0.id==groupID}){HStack{Text("分組："+group.name);Spacer();Button("清除"){model.editBrowsing(domain){$0.groupID=nil}}}.font(.caption)}
                    Text("範圍：目前商品目錄的 \(products.count) 個符合項目；排行只納入已取得對應統計的商品，並非完整市場。").font(.caption).foregroundStyle(.secondary)
                    if domain == .crypto{Text(preferences.category == "合約" ? "合約另有槓桿、保證金與強平風險。":"現貨以幣數買入／賣出；不包含合約。 ").font(.caption).foregroundStyle(.secondary)}
                    }
                }.id("marketTop")
                if !searching{MarketRefreshStatus()}
                if !searching && preferences.search.isEmpty && !preferences.favoritesOnly && preferences.sort == .familiar{recentProducts}
                if products.isEmpty{ContentUnavailableView("沒有符合的商品",systemImage:"magnifyingglass",description:Text("調整搜尋或分類，也可從商品目錄查看來源支援範圍。"));Button("清除篩選"){model.editBrowsing(domain){$0.search="";$0.favoritesOnly=false;$0.groupID=nil;$0.sort = .familiar;$0.category=domain == .crypto ? "現貨":"全部"}}}
                ForEach(Array(products.prefix(pageSize))){instrument in
                    MarketProductRow(instrument:instrument,owner:"markets-"+domain.rawValue).padding(.horizontal,12).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12)).id(instrument.id)
                }
                if products.count>pageSize{Button("載入更多（已顯示 \(pageSize)／\(products.count)）"){pageSize+=40}.frame(maxWidth:.infinity)}
                if (model.state?.instruments ?? []).contains(where:{$0.identity?.legacy==true && $0.market==domain}){NavigationLink("舊版自訂商品與原有身份"){LegacyProductsView()}.font(.footnote)}
                Text("已到目前列表底部").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity).accessibilityIdentifier("marketBottom")
            }.scrollTargetLayout().padding(16).padding(.bottom,20)
        }.refreshable{await model.fetchQuotes()}.scrollPosition(id:scroll,anchor:.top).scrollDismissesKeyboard(.immediately).background(Color(.systemGroupedBackground)).navigationTitle("行情").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("完成搜尋"){searching=false}}}
            .sheet(isPresented:$model.catalogVisible){NavigationStack{ProductCatalogView()}}
            .sheet(isPresented:$groups){NavigationStack{WatchGroupsView()}}
            .onAppear{if !searchInitialized{searchText=preferences.search;searchInitialized=true}}
            .onChange(of:searchText){_,text in model.editBrowsing(domain){$0.search=text;$0.scrollID=nil}}
            .task(id:domain){if let id=preferences.scrollID,let index=products.firstIndex(where:{$0.id==id}){pageSize=max(40,(index/40+1)*40)};await model.ensureQuoteService()}
            .onChange(of:model.tab){_,tab in if tab != 1{searching=false}}
            .onDisappear{searching=false;model.removeVisibleOwner("markets-"+domain.rawValue)}
    }
    @ViewBuilder private var recentProducts:some View{
        let recent=preferences.recent.compactMap{id in model.state?.instruments.first{$0.id==id && $0.market==domain}}
        if !recent.isEmpty{ScrollView(.horizontal,showsIndicators:false){HStack{Text("最近瀏覽").font(.caption).foregroundStyle(.secondary);ForEach(Array(recent.prefix(8))){i in Button(i.symbol){model.select(i)}.font(.caption).buttonStyle(.bordered)}}}}
    }
}
private struct CatalogBrowse{var query:String;var category:String;var page=0}
struct ProductCatalogView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State private var filters:[MarketDomain:CatalogBrowse]=[:]
    private var domain:MarketDomain{model.market}
    private var browsing:CatalogBrowse{filters[domain] ?? CatalogBrowse(query:model.currentBrowsing.search,category:categories.contains(model.currentBrowsing.category) ? model.currentBrowsing.category:(domain == .crypto ? "現貨":"全部"))}
    private var query:String{browsing.query}
    private var category:String{browsing.category}
    private var page:Int{browsing.page}
    private var categories:[String]{domain == .stocks ? ["全部","台股","美股","ETF"]:domain == .crypto ? ["現貨","合約"]:["全部","外匯","期貨","指數"]}
    private var matching:[Instrument]{
        (model.state?.instruments ?? []).filter{i in
            guard i.identity?.legacy != true,i.market==domain else{return false}
            let asset:AssetClass?=switch category{case "台股":.taiwanStock;case "美股":.usStock;case "ETF":.etf;case "現貨":.crypto;case "合約":.perpetual;case "外匯":.forex;case "期貨":.future;case "指數":.index;default:nil}
            guard asset==nil || i.asset==asset else{return false}
            return query.isEmpty || i.symbol.localizedCaseInsensitiveContains(query) || i.name.localizedCaseInsensitiveContains(query)
        }.sorted{($0.symbol,$0.id)<($1.symbol,$1.id)}
    }
    var body:some View{List{
        Section("搜尋本機商品目錄"){
            TextField("代碼或商品名稱",text:Binding(get:{query},set:{value in var updated=browsing;updated.query=value;updated.page=0;filters[domain]=updated;model.editBrowsing(domain){$0.search=value}})).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("catalogSearch")
            Picker("市場",selection:Binding(get:{domain},set:{model.switchMarket($0)})){ForEach(MarketDomain.allCases,id:\.self){Text($0.label)}}.accessibilityIdentifier("catalogMarket")
            Picker("分類",selection:Binding(get:{category},set:{value in var updated=browsing;updated.category=value;updated.page=0;filters[domain]=updated;model.editBrowsing(domain){$0.category=value}})){ForEach(categories,id:\.self){Text($0)}}.accessibilityIdentifier("catalogCategory")
            Text(model.state?.mode == .offline ? "真實名稱與代碼；所有價格、新聞與成交均為離線模擬。飛航也可搜尋與選取。":"身份不代表行情或交易權限；選取後會顯示可用價格及具體限制。").font(.caption).foregroundStyle(.secondary)
        }
        if model.state?.mode == .online{Section{NavigationLink("探索更多來源商品"){SourceCatalogLinksView()}.accessibilityIdentifier("exploreSourceCatalogs")}}
        Section("符合 \(matching.count) 個商品 · 第 \(page+1) 頁"){
            ForEach(Array(matching.dropFirst(page*20).prefix(20))){instrument in
                MarketProductRow(instrument:instrument,owner:"catalog",onSelection:{
                    guard model.context != nil else{return};model.catalogVisible=false;dismiss();model.select(instrument)
                })
            }
            if matching.isEmpty{Text("此市場沒有符合的商品。可調整分類、搜尋或切換市場。").font(.subheadline).foregroundStyle(.secondary)}
            HStack{Button("上一頁"){guard page>0 else{return};var updated=browsing;updated.page-=1;filters[domain]=updated}.disabled(page==0);Spacer();Button("下一頁"){guard (page+1)*20<matching.count else{return};var updated=browsing;updated.page+=1;filters[domain]=updated}.disabled((page+1)*20>=matching.count)}
        }
        Section("商品身份"){
            Text("股票、ETF、現貨、合約、外匯與期貨各自保留交易所、幣別及交易單位；同名跨交易所商品不合併。").font(.caption)
            LabeledContent("全部本機商品",value:String(model.state?.instruments.filter{$0.identity?.legacy != true}.count ?? 0))
            if model.state?.mode == .offline{NavigationLink("自訂離線商品"){CustomInstrumentView()};NavigationLink("舊版自訂商品與原部位"){LegacyProductsView()}}
        }
    }.navigationTitle("商品目錄").scrollDismissesKeyboard(.immediately).toolbar{Button("完成"){dismiss()}}
        .onDisappear{model.removeVisibleOwner("catalog")}
    }
}
struct SourceCatalogLinksView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{
        if model.context?.mode == .online{Section("合法來源商品身份"){
            NavigationLink("搜尋官方美股／ETF目錄"){USStockDiscoveryView()}
            ForEach(ProviderID.allCases,id:\.self){id in NavigationLink(id.label){SourceProductDiscoveryView(id:id)}.accessibilityIdentifier("catalogSource-"+id.rawValue)}
            Text("依來源權限查核並加入單一商品；不覆寫原持倉、歷史或規則。目錄、行情與可成交權限分開確認。").font(.caption)
        }}else{Text("B完全離線；可返回本機目錄探索商品。")}
    }.navigationTitle("來源商品目錄")}
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
