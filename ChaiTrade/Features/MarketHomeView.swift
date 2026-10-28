import SwiftUI
import ChaiTradeCore

@MainActor enum MarketText {
    static func orderDirection(_ instrument:Instrument?,side:Side,reduceOnly:Bool)->String{
        if let instrument,instrument.asset.derivative,reduceOnly{return side == .buy ? "平空":"平多"}
        return side == .buy ? (instrument?.buyLabel ?? "買入"):(instrument?.sellLabel ?? "賣出")
    }
    static func number(_ amount:Amount?)->String{
        guard let amount else{return "—"}
        let text=amount.description,parts=text.split(separator:".",omittingEmptySubsequences:false)
        let negative=parts[0].hasPrefix("-"),digits=negative ? String(parts[0].dropFirst()):String(parts[0])
        let grouped=String(digits.reversed().enumerated().map{($0.offset>0 && $0.offset%3==0 ? ",":"")+String($0.element)}.joined().reversed())
        return (negative ? "-":"")+grouped+(parts.count>1 ? "."+parts[1]:"")
    }
    static func change(_ quote:Quote?,summary:QuoteSummary?)->(String,Amount)?{
        guard let quote,let reference=summary?.reference,reference > .zero,let delta=try? quote.last-reference,let percent=try? (delta/reference*Amount(100)).rounded(2,.plain) else{return nil}
        return ((delta >= .zero ? "+":"")+number(delta)+"  "+(percent >= .zero ? "+":"")+percent.description+"%",delta)
    }
}
struct MarketSwitcher:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View{
        HStack(spacing:6){
            ForEach([MarketDomain.stocks,.crypto],id:\.self){domain in
                Button{model.switchMarket(domain)}label:{Text(typeSize.isAccessibilitySize && domain == .crypto ? "加密":domain.label).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth:.infinity,minHeight:44).background(model.market==domain ? Color.orange.opacity(0.16):Color.clear,in:RoundedRectangle(cornerRadius:10)).contentShape(Rectangle())}
                    .buttonStyle(.plain).foregroundStyle(model.market==domain ? .orange:.secondary).accessibilityLabel(domain.label).accessibilityIdentifier(domain == .stocks ? "marketStocks":"marketCrypto").accessibilityAddTraits(model.market==domain ? .isSelected:[])
            }
            Menu{Button("外匯與期貨"){model.switchMarket(.other)};Text("市場切換只改瀏覽分類，A／B 帳戶不變")}label:{Image(systemName:"ellipsis.circle").font(.title3).frame(minWidth:44,minHeight:44)}.accessibilityLabel("其他市場：外匯與期貨")
        }.padding(.horizontal,16).padding(.bottom,5).accessibilityElement(children:.contain)
    }
}
struct MarketCard<Content:View>:View {
    var content:Content
    init(@ViewBuilder content:()->Content){self.content=content()}
    var body:some View{VStack(alignment:.leading,spacing:14){content}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))}
}
struct MarketSectionTitle:View {
    var title:String,subtitle:String?=nil
    var body:some View{VStack(alignment:.leading,spacing:4){Text(title).font(.title3.bold());if let subtitle{Text(subtitle).font(.caption).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,alignment:.leading)}
}
struct QuoteStatusLabel:View {
    var status:MarketIssueKind
    var body:some View{Label(status.label,systemImage:status == .ready ? "checkmark.circle.fill":status == .loading ? "clock":"info.circle").font(.caption2).foregroundStyle(status == .ready ? Color.secondary:Color.orange).fixedSize(horizontal:false,vertical:true)}
}
struct MarketProductRow:View {
    @EnvironmentObject var model:AppModel
    let instrument:Instrument
    var owner:String="markets"
    var onSelection:(()->Void)?=nil
    var body:some View{
        HStack(spacing:12){
            Button{if let onSelection{onSelection()}else{model.select(instrument)}}label:{
                HStack(spacing:12){
                    Text(String(instrument.symbol.prefix(2))).font(.caption.monospaced().bold()).frame(width:38,height:38).background(.orange.opacity(0.10),in:RoundedRectangle(cornerRadius:11))
                    VStack(alignment:.leading,spacing:4){Text(instrument.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2);Text(instrument.symbol+" · "+(instrument.identity?.exchange ?? instrument.asset.label)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)}
                    Spacer(minLength:4)
                    VStack(alignment:.trailing,spacing:5){
                        if let quote=model.state?.quotes[instrument.id]{Text(MarketText.number(quote.last)).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
                            if let change=MarketText.change(quote,summary:model.summary(for:instrument)){Text(change.0).font(.caption2.monospacedDigit()).foregroundStyle(change.1 >= .zero ? (model.settings.taiwanColors ? .red:.green):(model.settings.taiwanColors ? .green:.red)).lineLimit(1).minimumScaleFactor(0.6)}
                        }else if model.status(for:instrument) == .loading{ProgressView().controlSize(.small)}
                        QuoteStatusLabel(status:model.status(for:instrument))
                    }.frame(maxWidth:155,alignment:.trailing)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier((owner=="catalog" ? "catalog-product-":"market-")+instrument.id)
            Button{Task{await model.toggleWatch(instrument.id)}}label:{Image(systemName:model.state?.watchlist.contains(instrument.id)==true ? "star.fill":"star").frame(minWidth:30,minHeight:44)}.accessibilityLabel("自選 "+instrument.name).accessibilityIdentifier((owner=="catalog" ? "catalog-watch-":"watch-")+instrument.id).disabled(model.interactionBlocked)
        }.padding(.vertical,8).onAppear{model.visible(instrument.id,owner:owner,present:true)}.onDisappear{model.visible(instrument.id,owner:owner,present:false)}
    }
}
struct DashboardView:View {
    @EnvironmentObject var model:AppModel
    let domain:MarketDomain
    @State private var calendar=false
    @State private var connections=false
    private var products:[Instrument]{(model.state?.instruments ?? []).filter{domain.contains($0) && $0.identity?.legacy != true && $0.asset != .index && (domain != .crypto || $0.asset == .crypto)}}
    private var common:[Instrument]{let preferred=domain == .crypto ? ["BTC-USD","ETH-USD","SOL-USD","XRP-USD"]:domain == .stocks ? ["2330","0050","2317","2454","AAPL","MSFT"]:["EUR/USD","USD/JPY","TXF202611"];return products.sorted{a,b in (preferred.firstIndex(of:a.symbol) ?? 100, a.symbol)<(preferred.firstIndex(of:b.symbol) ?? 100,b.symbol)}.prefix(8).map{$0}}
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:24){
                HStack(alignment:.top){VStack(alignment:.leading,spacing:5){Text(domain == .stocks ? "掌握股市脈動":domain == .crypto ? "探索加密市場":"外匯與期貨").font(.largeTitle.bold());Text(model.state?.mode == .offline ? "離線行情、價格與事件均為模擬":"真實行情 · 所有買賣只在本機模擬").font(.caption).foregroundStyle(.secondary)};Spacer()}
                Button{model.tab=4}label:{HStack{Label(model.valuation?.complete == true ? "帳戶資產":"已知部分資產",systemImage:"wallet.bifold");Spacer();Text(model.settings.hideBalances ? "••••••":MarketText.number(model.valuation?.total));Image(systemName:"chevron.right").font(.caption)}}.font(.subheadline).buttonStyle(.plain).padding(14).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:13))
                if model.state?.mode == .offline{HStack{Label("模擬時間",systemImage:"clock");Text(Date(timeIntervalSince1970:TimeInterval(model.now)).formatted(date:.abbreviated,time:.shortened));Spacer();Text(model.state?.simulation?.paused==true ? "已暫停":"進行中")}.font(.caption).foregroundStyle(.secondary)}
                if domain == .stocks{MarketIndexStrip()}
                marketShortcuts
                if model.state?.mode == .online,common.allSatisfy({model.state?.quotes[$0.id]==nil}){MarketCard{Label("開始看盤",systemImage:"antenna.radiowaves.left.and.right").font(.headline);Text(domain == .crypto ? "公開現貨行情會依可見商品載入；可查看各商品的連線與授權狀態。":"台股與美股行情依來源授權提供。可以先探索商品，再設定自己的行情連線。").font(.subheadline).foregroundStyle(.secondary);Button("行情連線"){connections=true}.buttonStyle(.bordered)}}
                MarketCard{MarketSectionTitle(title:"常見商品",subtitle:"精選入口；不是熱門或績效推薦");ForEach(common){MarketProductRow(instrument:$0,owner:"home-"+domain.rawValue);if $0.id != common.last?.id{Divider()}};Button("探索全部商品"){model.tab=1}}
                let favorites=products.filter{model.state?.watchlist.contains($0.id)==true}
                MarketCard{MarketSectionTitle(title:"我的自選");if favorites.isEmpty{Text("把想追蹤的商品加入自選，在這裡掌握變化。").font(.subheadline).foregroundStyle(.secondary);Button("加入自選商品"){model.editBrowsing(domain){$0.favoritesOnly=false};model.tab=1}}else{ForEach(Array(favorites.prefix(5))){MarketProductRow(instrument:$0,owner:"home-"+domain.rawValue)};Button("查看全部自選"){model.editBrowsing(domain){$0.favoritesOnly=true};model.tab=1}}}
                MarketRankingPreview()
                HStack{MarketSectionTitle(title:"新聞與市場事件");NavigationLink("全部"){MarketNewsView(initialCategory:domain == .crypto ? "現貨":"全部")}.font(.subheadline).accessibilityIdentifier("openMarketNews")}
                ForEach(Array(model.homeNews.prefix(3))){story in NavigationLink{MarketNewsDetail(story:story)}label:{MarketNewsCard(story:story)}.buttonStyle(.plain)}
                if model.homeNews.isEmpty{MarketCard{Text(model.newsLoading ? "正在載入來源新聞…":"目前沒有符合這個市場的新聞").font(.subheadline);if let issue=model.newsIssue{Text(issue).font(.caption).foregroundStyle(.secondary)};NavigationLink("新聞與來源狀態"){MarketNewsView(initialCategory:domain == .crypto ? "現貨":"全部")}}}
                Button{calendar=true}label:{Label("財報／除息與市場日曆",systemImage:"calendar").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.bordered)
                Text("已到首頁底部").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity).accessibilityIdentifier("homeBottom")
            }.padding(18).padding(.bottom,24)
        }.background(Color(.systemGroupedBackground)).navigationTitle("總覽").navigationBarTitleDisplayMode(.inline)
            .task(id:domain){await model.loadNews();await model.ensureQuoteService()}.onDisappear{model.removeVisibleOwner("home-"+domain.rawValue)}
            .sheet(isPresented:$calendar){NavigationStack{MarketCalendarView()}}
            .sheet(isPresented:$connections){NavigationStack{ConnectionsView()}}
    }
    private var marketShortcuts:some View{
        ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(domain == .stocks ? ["台股","美股","ETF"]:domain == .crypto ? ["現貨","合約"]:["外匯","期貨","歷史模擬"],id:\.self){category in Button(category){model.editBrowsing(domain){$0.category=category;$0.favoritesOnly=false};model.tab=1}.buttonStyle(.bordered)}}}
    }
}
struct MarketIndexStrip:View {
    @EnvironmentObject var model:AppModel
    private var indices:[Instrument]{Array((model.state?.instruments ?? []).filter{$0.asset == .index && $0.identity?.legacy != true}.prefix(5))}
    var body:some View{ScrollView(.horizontal,showsIndicators:false){HStack(spacing:12){ForEach(indices){instrument in Button{model.select(instrument)}label:{VStack(alignment:.leading,spacing:8){Text(instrument.name).font(.caption.weight(.medium));if let quote=model.state?.quotes[instrument.id]{Text(MarketText.number(quote.last)).font(.headline.monospacedDigit());if let change=MarketText.change(quote,summary:model.summary(for:instrument)){Text(change.0).font(.caption2)}}else{QuoteStatusLabel(status:model.status(for:instrument))};Text(instrument.rules.isOpen(at:model.now) ? "交易時段":"休市／非交易時段").font(.caption2).foregroundStyle(.secondary)}.frame(width:150,alignment:.leading).padding(14).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))}.buttonStyle(.plain).onAppear{model.visible(instrument.id,owner:"home-"+instrument.market.rawValue,present:true)}.onDisappear{model.visible(instrument.id,owner:"home-"+instrument.market.rawValue,present:false)}}}}}
}
struct MarketRankingPreview:View {
    @EnvironmentObject var model:AppModel
    var ranked:[Instrument]{(model.state?.instruments ?? []).filter{$0.market==model.market && $0.asset != .index && $0.identity?.legacy != true && (model.market != .crypto || $0.asset == .crypto) && model.summary(for:$0)?.reference != nil && model.state?.quotes[$0.id] != nil}.sorted{a,b in let qa=model.state!.quotes[a.id]!,qb=model.state!.quotes[b.id]!;let aa=(try? (qa.last/model.summary(for:a)!.reference!)-Amount.one) ?? .zero,bb=(try? (qb.last/model.summary(for:b)!.reference!)-Amount.one) ?? .zero;return aa>bb}}
    var body:some View{MarketCard{MarketSectionTitle(title:"漲跌與活躍榜",subtitle:"範圍：目前集合中已取得可比較資料的 \(ranked.count) 個商品");if ranked.isEmpty{Text("來源尚未提供足夠漲跌統計，取得資料後才會排序。").font(.subheadline).foregroundStyle(.secondary)}else{ForEach(Array(ranked.prefix(3))){MarketProductRow(instrument:$0,owner:"home")}};HStack{Button("漲幅"){open(.gainers)};Button("跌幅"){open(.losers)};Button("成交量"){open(.volume)}}}}
    func open(_ sort:MarketSort){model.editBrowsing(model.market){$0.sort=sort;$0.favoritesOnly=false};model.tab=1}
}
