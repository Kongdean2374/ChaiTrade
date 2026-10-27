import SwiftUI
import Charts
import ChaiTradeCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var settings=false
    @State private var recovery=false
    var body: some View {
        Group {
            if !model.settings.onboarded { OnboardingView() }
            else if model.state == nil {
                ContentUnavailableView { Label("ChaiTrade",systemImage:"chart.xyaxis.line") } description: { Text(model.loading ? "正在驗證本機帳戶…":"帳戶尚未載入。原始資料保留，可從已驗證備份恢復。") } actions: {
                    Button("重試啟動"){Task{await model.boot()}}
                    Button("從備份恢復無法啟動的帳戶"){recovery=true}
                    if model.settings.pendingMode != nil{Button("取消待切換，載入原帳戶"){model.setPending(nil);Task{await model.boot()}}}
                }
            } else {
                VStack(spacing:0) {
                    HStack {
                        Image(systemName:"circle.fill").font(.system(size:7)).foregroundStyle(model.state?.mode == .offline ? .orange:.cyan)
                        Text(model.state!.mode.label).font(.caption.weight(.medium)).accessibilityIdentifier("activeModeBanner")
                        Spacer()
                        if model.settings.pendingMode != nil { Image(systemName:"arrow.triangle.2.circlepath").accessibilityLabel("待下次完整啟動切換") }
                        Button { settings=true } label: { Image(systemName:"gearshape") }.accessibilityLabel("設定").disabled(model.interactionBlocked)
                    }.padding(.horizontal).padding(.vertical,10).background(.bar)
                    MarketSwitcher()
                    TabView(selection:$model.tab) {
                        NavigationStack { DashboardView() }.tabItem{Label("總覽",systemImage:"square.grid.2x2")}.tag(0)
                        NavigationStack { MarketsView() }.tabItem{Label("行情",systemImage:"chart.bar.xaxis")}.tag(1)
                        NavigationStack { TradingView() }.tabItem{Label("交易",systemImage:"arrow.left.arrow.right")}.tag(2)
                        NavigationStack { OrdersView() }.tabItem{Label("委託",systemImage:"list.bullet.rectangle")}.tag(3)
                        NavigationStack { PortfolioView() }.tabItem{Label("資產",systemImage:"wallet.bifold")}.tag(4)
                    }.id(model.stateRevision)
                }
            }
        }
        .overlay(alignment:.bottomLeading){UITestProbe()}
        .sheet(isPresented:$settings){NavigationStack{SettingsView()}}
        .sheet(isPresented:$recovery){NavigationStack{RecoveryView()}}
        .sheet(item:$model.chartAmendment){intent in NavigationStack{ChartAmendConfirm(intent:intent)}}
        .alert("操作未完成",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})) { Button("知道了"){model.error=nil} } message:{Text(model.error ?? "")}
        .alert("時間完整性確認",isPresented:Binding(get:{model.clockWarning != nil},set:{_ in})) {
            Button("依經過時間補算"){Task{await model.catchUp()}}
            Button("放棄這段推進，從檢查點繼續",role:.destructive){Task{await model.skipCatchup()}}
        } message:{Text(model.clockWarning ?? "")}
        .overlay(alignment:.top) {
            if model.maintainingAccount{ProgressView("建立帳戶恢復點／還原中，暫停帳務操作…").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding()}
            else if model.progress != nil || (model.catchupTarget != nil && model.clockWarning == nil) {
                VStack(spacing:10){
                    ZStack{
                        Text("順序處理離線市場事件").opacity(model.progress != nil ? 1:0).accessibilityHidden(model.progress == nil)
                        Text("市場事件處理已暫停").opacity(model.progress == nil ? 1:0).accessibilityHidden(model.progress != nil)
                    }.font(.headline)
                    ProgressView(value:model.progress ?? 0).opacity(model.progress != nil ? 1:0).accessibilityHidden(model.progress == nil)
                    ZStack{
                        Text("已完成事件會逐批保存；此時暫停下單").opacity(model.progress != nil ? 1:0).accessibilityHidden(model.progress == nil)
                        Text("從已保存的進度繼續，或明確放棄剩餘推進").opacity(model.progress == nil ? 1:0).accessibilityHidden(model.progress != nil)
                    }.font(.caption)
                    HStack(spacing:16){
                        Button{model.stopCatchup()}label:{Text("暫停補算").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                            .disabled(model.progress == nil).accessibilityIdentifier("catchupPause")
                        Button{Task{await model.catchUp()}}label:{Text("從檢查點繼續處理").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                            .disabled(model.progress != nil || model.catchingUp).accessibilityIdentifier("catchupResume")
                    }.buttonStyle(.bordered)
                    Button("放棄未完成的推進",role:.destructive){model.clockWarning="確定放棄尚未處理的推進區段？已完成的行情與交易會保留。"}
                        .disabled(model.progress != nil || model.catchingUp)
                }.padding().frame(maxWidth:420).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding()
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
