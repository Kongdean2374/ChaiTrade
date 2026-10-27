import SwiftUI
import UIKit
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
                        Text(model.state!.mode == .online ? "A 真實行情":"B 離線模擬").font(.caption.weight(.medium)).accessibilityLabel(model.state!.mode.label).accessibilityIdentifier("activeModeBanner")
                        Spacer()
                        if model.settings.pendingMode != nil { Image(systemName:"arrow.triangle.2.circlepath").accessibilityLabel("待下次完整啟動切換") }
                        Button { settings=true } label: { Image(systemName:"gearshape") }.accessibilityLabel("設定").disabled(model.interactionBlocked)
                    }.padding(.horizontal).padding(.vertical,10).background(.bar)
                    if let notice=model.notice{
                        Button{model.notice=nil}label:{HStack(alignment:.top){Text(notice).lineLimit(3).fixedSize(horizontal:false,vertical:true);Spacer(minLength:8);Image(systemName:"xmark.circle.fill")}.font(.caption).foregroundStyle(.primary).padding(12).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(notice).accessibilityIdentifier("dismissNotice").background(Color.orange.opacity(0.08))
                    }
                    MarketSwitcher()
                    TabView(selection:$model.tab) {
                        NavigationStack { DashboardView(domain:model.market).id(model.market) }.tabItem{Label("總覽",systemImage:"square.grid.2x2")}.tag(0)
                        NavigationStack { MarketsView(domain:model.market).id(model.market) }.tabItem{Label("行情",systemImage:"chart.bar.xaxis")}.tag(1)
                        NavigationStack { TradingView() }.tabItem{Label("交易",systemImage:"arrow.left.arrow.right")}.tag(2)
                        NavigationStack { OrdersView() }.tabItem{Label("委託",systemImage:"list.bullet.rectangle")}.tag(3)
                        NavigationStack { PortfolioView() }.tabItem{Label("資產",systemImage:"wallet.bifold")}.tag(4)
                    }.id(model.stateRevision).onChange(of:model.tab){_,_ in UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}
                }
            }
        }
        .overlay(alignment:.bottomLeading){UITestProbe()}
        .sheet(isPresented:$settings){NavigationStack{SettingsView()}.modifier(UITestVisualEnvironment())}
        .sheet(isPresented:$recovery){NavigationStack{RecoveryView()}}
        .sheet(item:$model.chartAmendment){intent in NavigationStack{ChartAmendConfirm(intent:intent)}}
        .sheet(item:$model.openedNotice){destination in NavigationStack{NoticeDetailView(destination:destination)}.modifier(UITestVisualEnvironment())}
        .onChange(of:model.catalogNavigationRevision){_,_ in settings=false}
        .onReceive(NoticeTapMailbox.shared.$pending.compactMap{$0}){link in NoticeTapMailbox.shared.pending=nil;Task{await model.handleNoticeLink(link)}}
        .confirmationDialog("這則通知屬於另一個獨立帳戶",isPresented:Binding(get:{model.requestedAccountNotice != nil},set:{if !$0{model.requestedAccountNotice=nil}}),titleVisibility:.visible){
            if let link=model.requestedAccountNotice{Button("下次完整啟動切換至 "+link.mode.label){model.queueNoticeAccountSwitch(link)}}
            Button("取消",role:.cancel){model.requestedAccountNotice=nil}
        }message:{Text("目前帳戶不會切換或轉移資金。可記錄目的地，完整關閉再啟動後查看原事件。")}
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
            }
        }
        .fileExporter(isPresented:$model.exporting,document:model.exportDocument,contentType:.data,defaultFilename:model.exportName){ result in
            if case .failure(let error)=result { model.error=error.localizedDescription }
        }
    }
}

struct OnboardingView:View{
    @EnvironmentObject var model:AppModel
    @State private var mode=Mode.offline
    @State private var online="1000000"
    @State private var offline="1000000"
    @State private var currency="TWD"
    @State private var starting=false
    var body:some View{NavigationStack{Form{
        Section{
            HStack(spacing:14){Image(systemName:"chart.xyaxis.line").font(.system(size:30)).foregroundStyle(.orange);VStack(alignment:.leading,spacing:6){Text("ChaiTrade").font(.title.bold());Text("練習判斷，掌握自己的節奏。").font(.subheadline).foregroundStyle(.secondary)}}
            Text("所有資金與成交均為本機模擬。你可以先離線體驗完整市場，再設定真實行情。").font(.footnote).foregroundStyle(.secondary)
        }.listRowBackground(Color.clear).listRowSeparator(.hidden)
        Section("選擇啟動帳戶"){
            Picker("啟動帳戶",selection:$mode){Text("A 真實行情").tag(Mode.online);Text("B 離線模擬").tag(Mode.offline)}.pickerStyle(.segmented)
            Text(mode == .offline ? "B完全離線，內建多市場商品與模擬新聞，不需要API Key。":"A使用真實行情；所有委託只在本機模擬。部分來源需要自己的行情權限。").font(.footnote)
        }
        Section("兩個帳戶各自的虛擬本金"){
            LabeledContent("A本金"){TextField("A初始虛擬本金",text:$online).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("onlineCapital")}
            LabeledContent("B本金"){TextField("B初始虛擬本金",text:$offline).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("offlineCapital")}
            Picker("基準幣別",selection:$currency){Text("TWD").tag("TWD");Text("USD").tag("USD")}.accessibilityIdentifier("baseCurrency")
            Text("A／B資金與歷史完全隔離。股票／加密則是帳戶內的瀏覽分類，不會另開帳戶。").font(.caption).foregroundStyle(.secondary)
        }
        Section{Text("A／B切換於完整關閉再啟動時生效。B重開會按設定補算離開期間；沒有常駐背景交易。來源及模型限制可隨時查看。").font(.caption).foregroundStyle(.secondary)}
    }.scrollDismissesKeyboard(.interactively).navigationTitle("歡迎使用").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.bottom){Button(starting ? "建立帳戶中…":"建立獨立帳戶並開始"){
            guard !starting else{return};starting=true
            Task{await model.onboard(mode:mode,online:online,offline:offline,currency:currency);starting=false}
        }.font(.headline).frame(maxWidth:.infinity,minHeight:48).buttonStyle(.borderedProminent).disabled(starting).accessibilityIdentifier("startTrading").padding(.horizontal,18).padding(.vertical,10).background(.bar)}
    }}
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
