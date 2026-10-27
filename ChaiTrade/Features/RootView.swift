import SwiftUI
import Charts
import ChaiTradeCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var settings=false
    var body: some View {
        Group {
            if !model.settings.onboarded { OnboardingView() }
            else if model.state == nil {
                ContentUnavailableView { Label("ChaiTrade",systemImage:"chart.xyaxis.line") } description: { Text(model.loading ? "正在驗證本機帳戶…":"帳戶尚未載入。原始資料保留，請重試或檢查備份。") } actions: { Button("重試啟動"){Task{await model.boot()}} }
            } else {
                VStack(spacing:0) {
                    HStack {
                        Image(systemName:"circle.fill").font(.system(size:7)).foregroundStyle(model.state?.mode == .offline ? .orange:.cyan)
                        Text(model.state!.mode.label).font(.caption.weight(.semibold))
                        Spacer()
                        if model.settings.pendingMode != nil { Image(systemName:"arrow.triangle.2.circlepath").accessibilityLabel("待下次完整啟動切換") }
                        Button { settings=true } label: { Image(systemName:"gearshape") }.accessibilityLabel("設定")
                    }.padding(.horizontal).padding(.vertical,10).background(.bar)
                    TabView(selection:$model.tab) {
                        NavigationStack { DashboardView() }.tabItem{Label("總覽",systemImage:"square.grid.2x2")}.tag(0)
                        NavigationStack { MarketsView() }.tabItem{Label("行情",systemImage:"chart.bar.xaxis")}.tag(1)
                        NavigationStack { TradingView() }.tabItem{Label("交易",systemImage:"arrow.left.arrow.right")}.tag(2)
                        NavigationStack { OrdersView() }.tabItem{Label("委託",systemImage:"list.bullet.rectangle")}.tag(3)
                        NavigationStack { PortfolioView() }.tabItem{Label("資產",systemImage:"wallet.bifold")}.tag(4)
                    }
                }
            }
        }
        .sheet(isPresented:$settings){NavigationStack{SettingsView()}}
        .alert("操作未完成",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})) { Button("知道了"){model.error=nil} } message:{Text(model.error ?? "")}
        .alert("時間完整性確認",isPresented:Binding(get:{model.clockWarning != nil},set:{_ in})) {
            Button("依經過時間補算"){Task{await model.catchUp()}}
            Button("放棄這段推進，從檢查點繼續",role:.destructive){Task{await model.skipCatchup()}}
        } message:{Text(model.clockWarning ?? "")}
        .overlay(alignment:.top) {
            if let progress=model.progress {
                VStack { Text("重開後補算離線市場").font(.headline);ProgressView(value:progress);Text("已完成事件會逐批保存；此時暫停下單").font(.caption);Button("暫停補算"){model.stopCatchup()} }.padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding()
            } else if let notice=model.notice {
                Button{model.notice=nil}label:{Text(notice).font(.caption).padding().foregroundStyle(.primary).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))}.padding()
            }
        }
        .fileExporter(isPresented:$model.exporting,document:model.exportDocument,contentType:.data,defaultFilename:model.exportName){ result in
            if case .failure(let error)=result { model.error=error.localizedDescription }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode=Mode.offline
    @State private var online="1000000"
    @State private var offline="1000000"
    @State private var currency="TWD"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(systemName:"chart.xyaxis.line").font(.system(size:48)).foregroundStyle(.orange).frame(maxWidth:.infinity).padding(.top)
                    Text("ChaiTrade").font(.largeTitle.bold()).frame(maxWidth:.infinity)
                    Text("練習判斷，掌握自己的節奏。\n所有資金與成交都是模擬。").multilineTextAlignment(.center).frame(maxWidth:.infinity).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
                Section("選擇本次市場") {
                    Picker("運作模式",selection:$mode){ForEach(Mode.allCases,id:\.self){Text($0.label).tag($0)}}.pickerStyle(.inline)
                    Text(mode == .offline ? "完全離線，首次開啟就能操作。不要求帳號或 API Key。":"使用真實行情；成交仍由本機引擎處理。部分來源需自己的行情權限。").font(.caption)
                }
                Section("兩個帳戶獨立本金") {
                    TextField("A 初始虛擬本金",text:$online).keyboardType(.decimalPad).accessibilityIdentifier("onlineCapital")
                    TextField("B 初始虛擬本金",text:$offline).keyboardType(.decimalPad).accessibilityIdentifier("offlineCapital")
                    Picker("基準幣別",selection:$currency){Text("TWD").tag("TWD");Text("USD").tag("USD")}
                }
                Section {
                    Text("模式變更於下次完整關閉並啟動時生效。\n離線市場預設在重開時補算離開期間，沒有常駐背景交易。\n行情、合約及費率有來源與模型限制。").font(.footnote).foregroundStyle(.secondary)
                    Button("建立獨立帳戶並開始"){Task{await model.onboard(mode:mode,online:online,offline:offline,currency:currency)}}.font(.headline).accessibilityIdentifier("startTrading")
                }
            }.navigationTitle("歡迎使用")
        }
    }
}

struct Metric: View {
    var title: String
    var value: String
    var body: some View { VStack(alignment:.leading,spacing:8){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)}.frame(maxWidth:.infinity,alignment:.leading) }
}
struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack { Text("CHAI / TRADE").font(.caption.monospaced().weight(.bold)).tracking(3);Spacer();Button{model.settings.hideBalances.toggle();model.saveSettings()}label:{Image(systemName:model.settings.hideBalances ? "eye.slash":"eye")} }
                VStack(alignment:.leading,spacing:10) {
                    Text("\(model.state?.baseCurrency ?? "") 帳戶淨值\(model.valuation?.complete == false ? "（已知部分）":"")").font(.subheadline).foregroundStyle(.secondary)
                    Text(model.money(model.valuation?.total)).font(.system(size:38,weight:.semibold,design:.rounded)).monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                    HStack { Metric(title:"交易淨損益（扣除資金流）",value:model.money(model.valuation?.tradingPnL));Metric(title:"成交筆數",value:String(model.state?.fills.count ?? 0)) }
                }.padding(22).background(.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:22))
                if let valuation=model.valuation,!valuation.complete { Text(valuation.missing.joined(separator:"\n")).font(.caption).foregroundStyle(.orange) }
                if let sim=model.state?.simulation {
                    SimulationControls()
                    Text("模擬時間 \(Date(timeIntervalSince1970:TimeInterval(sim.time)).formatted(date:.abbreviated,time:.standard))").font(.caption.monospaced()).foregroundStyle(.secondary)
                } else {
                    Button{Task{await model.fetchQuotes()}}label:{Label(model.fetching ? "更新行情中":"更新真實行情",systemImage:"arrow.clockwise")}.buttonStyle(.bordered)
                    ForEach(ProviderID.allCases,id:\.self){id in if let status=model.providerStatus[id]{Text("\(id.label)：\(status)").font(.caption).foregroundStyle(.secondary)}}
                }
                if let equity=model.state?.equity,!equity.isEmpty {
                    Chart(Array(equity.enumerated()),id:\.offset){_,point in if let value=point.value{LineMark(x:.value("時間",Date(timeIntervalSince1970:TimeInterval(point.time))),y:.value("實際淨值",value.displayDouble)).foregroundStyle(.orange)}}.frame(height:130)
                }
                Text("關注市場").font(.title3.bold())
                ForEach(Array((model.state?.instruments ?? []).filter { model.state?.watchlist.contains($0.id) == true }.prefix(8))) { instrument in
                    Button{model.select(instrument)}label:{InstrumentRow(instrument:instrument)}.buttonStyle(.plain)
                }
                if model.state?.watchlist.isEmpty == true { Text("到行情頁收藏商品，在這裡追蹤價格。").foregroundStyle(.secondary) }
                Text("通知與市場事件").font(.title3.bold())
                ForEach(Array((model.state?.events ?? []).suffix(10).reversed())) { event in
                    VStack(alignment:.leading,spacing:4){Text(event.message).font(.subheadline);Text("\(event.kind) · \(Date(timeIntervalSince1970:TimeInterval(event.time)).formatted())").font(.caption2).foregroundStyle(.secondary)}.padding(.vertical,4)
                }
            }.padding(20)
        }.navigationTitle("總覽").navigationBarTitleDisplayMode(.inline)
    }
}
struct SimulationControls: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let sim=model.state?.simulation {
            HStack {
                Button{Task{await model.configureSimulation(paused:!sim.paused)}}label:{Image(systemName:sim.paused ? "play.fill":"pause.fill")}.accessibilityLabel(sim.paused ? "繼續模擬":"暫停模擬")
                Picker("速度",selection:Binding(get:{sim.speed},set:{v in Task{await model.configureSimulation(speed:v)}})){ForEach([1,2,5,10,60,100],id:\.self){Text("\($0)×").tag($0)}}.pickerStyle(.menu)
                Spacer()
                Text(sim.scenario).font(.caption).padding(6).background(.orange.opacity(0.12),in:Capsule())
            }.padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:14))
        }
    }
}
struct InstrumentRow: View {
    @EnvironmentObject var model: AppModel
    var instrument: Instrument
    var body: some View {
        HStack(spacing:12) {
            Text(String(instrument.symbol.prefix(2))).font(.caption.bold()).frame(width:38,height:38).background(.orange.opacity(0.12),in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:3){Text(instrument.name).font(.subheadline.weight(.medium)).lineLimit(1);Text("\(instrument.symbol) · \(instrument.asset.label)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)}
            Spacer()
            VStack(alignment:.trailing,spacing:4){Text(model.state?.quotes[instrument.id]?.last.description ?? "未提供").monospacedDigit().font(.subheadline.weight(.semibold));Text(instrument.currency).font(.caption2).foregroundStyle(.secondary)}
        }.contentShape(Rectangle()).padding(.vertical,5)
    }
}
struct MarketsView: View {
    @EnvironmentObject var model: AppModel
    @State private var search=""
    @State private var asset: AssetClass?
    @State private var favorites=false
    @State private var custom=false
    var filtered: [Instrument] {
        (model.state?.instruments ?? []).filter { i in
            (asset == nil || i.asset == asset) && (!favorites || model.state!.watchlist.contains(i.id)) && (search.isEmpty || "\(i.name) \(i.symbol)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            Section {
                Toggle("只看自選",isOn:$favorites)
                Picker("市場分類",selection:$asset){Text("全部").tag(AssetClass?.none);ForEach(AssetClass.allCases,id:\.self){Text($0.label).tag(Optional($0))}}
            }
            Section(model.state?.mode == .offline ? "B 模擬商品商店 · \(filtered.count) 個":"已配置來源範圍 · \(filtered.count) 個") {
                ForEach(filtered){i in Button{model.select(i)}label:{InstrumentRow(instrument:i)}.buttonStyle(.plain).swipeActions{Button{Task{await model.toggleWatch(i.id)}}label:{Label("自選",systemImage:model.state?.watchlist.contains(i.id) == true ? "star.slash":"star")}.tint(.orange)}}
            }
            if filtered.isEmpty { ContentUnavailableView.search(text:search) }
        }.searchable(text:$search,prompt:"搜尋商品名稱或代碼").navigationTitle("行情")
            .toolbar{if model.state?.mode == .offline{Button{custom=true}label:{Image(systemName:"plus")}.accessibilityLabel("新增自訂商品")}}
            .sheet(isPresented:$custom){NavigationStack{CustomInstrumentView()}}
    }
}
