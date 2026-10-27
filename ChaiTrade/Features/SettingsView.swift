import SwiftUI
import UniformTypeIdentifiers
import ChaiTradeCore

struct SettingsView:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    var body:some View{List{
        Section{Text("讓看盤與練習交易照自己的習慣運作。").foregroundStyle(.secondary)}
        Section{
            NavigationLink{ModeAccountSettings()}label:{Label("模式與帳戶",systemImage:"person.crop.circle")}
            NavigationLink{ConnectionsView()}label:{Label("行情連線",systemImage:"antenna.radiowaves.left.and.right")}
            NavigationLink{TradingPreferencesView()}label:{Label("交易偏好",systemImage:"slider.horizontal.3")}
            NavigationLink{OfflineSettingsView()}label:{Label("離線模擬",systemImage:"airplane")}
            NavigationLink{AppearanceNotificationSettings()}label:{Label("外觀與通知",systemImage:"bell.badge")}
            NavigationLink{DataBackupView()}label:{Label("資料備份／還原",systemImage:"externaldrive")}
            NavigationLink{AdvancedDiagnosticsView()}label:{Label("進階診斷",systemImage:"stethoscope")}
        }
        Section{NavigationLink("關於與第三方授權"){LicenseView()};Text("ChaiTrade · 私人娛樂模擬交易。所有資金與委託在本機處理。").font(.footnote).foregroundStyle(.secondary)}
    }.navigationTitle("設定").toolbar{Button("完成"){dismiss()}}}
}
struct ModeAccountSettings:View{
    @EnvironmentObject var model:AppModel
    var body:some View{Form{
        Section("目前帳戶"){Text(model.settings.activeMode.label);Text("股票／加密切換只是瀏覽分類，使用相同帳戶。A／B 則是完全隔離的帳戶、資金、委託與歷史。").font(.footnote)}
        Section("下次完整啟動切換"){
            ForEach(Mode.allCases,id:\.self){mode in Button(mode.label){model.setPending(mode)}}
            if let pending=model.settings.pendingMode{Text("待切換："+pending.label+"。請完整關閉 App 再開啟；回到主畫面不會換帳戶。").font(.footnote).foregroundStyle(.orange);Button("取消待切換"){model.setPending(nil)}}
        }
        Section{NavigationLink("重設目前帳戶"){AccountResetView()};Text("改版與切換市場不會自動重設資產。").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("模式與帳戶")}
}

struct LicenseView: View {
    @Environment(\.openURL) private var openURL
    @State private var confirmExternal=false
    var license: String { guard let url=Bundle.main.url(forResource:"LightweightCharts-LICENSE",withExtension:nil,subdirectory:"Licenses") else{return "授權資源遺失"};return (try? String(contentsOf:url,encoding:.utf8)) ?? "授權檔無法讀取" }
    var body: some View{ScrollView{VStack(alignment:.leading,spacing:16){Text("Lightweight Charts™\nCopyright © TradingView, Inc.\nhttps://www.tradingview.com/").font(.headline);Text("圖表資源以 Apache License 2.0 授權，完整條款隨 App 打包。")
        Button("TradingView（官方出處）"){confirmExternal=true}
        Text(license).font(.caption)
        Text("SQLite：Public Domain。Apple 系統框架依 Apple 平台條款提供。ChaiTrade 自有程式碼採 MIT。").font(.footnote)
    }.padding()}.confirmationDialog("將開啟外部官方網站，離開本機離線操作環境",isPresented:$confirmExternal,titleVisibility:.visible){Button("開啟 TradingView"){openURL(URL(string:"https://www.tradingview.com/")!)}}}
}

struct TradingPreferencesView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{Form{
            Section("交易與風險"){
                Picker("合約持倉模式",selection:Binding(get:{model.state?.positionMode ?? .oneWay},set:{value in Task{guard let engine=model.engine,let context=model.context else{return};_ = await model.run{try await engine.setPositionMode(value,context:context)}}})){ForEach(PositionMode.allCases,id:\.self){Text($0.label)}}
                Text("切換前須結束所有合約持倉與未結委託，避免自動合併部位；現貨維持買進／賣出。").font(.caption).foregroundStyle(.secondary)

                Toggle("啟用槓桿／合約功能",isOn:Binding(get:{model.state?.leverageEnabled ?? false},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(leverageEnabled:v,context:context)}}}))
                Text("啟用即表示了解虛擬合約可能強平及穿倉，負債會保留。現貨不自動借貸。").font(.caption).foregroundStyle(.orange)
                if model.state?.mode == .online{
                    Toggle("允許合約採自訂參考風險價模型",isOn:Binding(get:{model.state?.useReferenceRiskPrice ?? false},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(useReferenceRiskPrice:v,context:context)}}}))
                    Text("缺少交易所標記價時，只有明確啟用才可用來源參考價計算自訂風險。畫面會標示此模型；不能宣稱為交易所標記價。").font(.caption)
                    Toggle("允許參考價模型估算撮合",isOn:Binding(get:{model.state?.allowEstimatedExecution ?? false},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(allowEstimated:v,context:context)}}}))
                    Text("參考價估算使用明示價差與有限流動性模型，成交永久標記為估算。延遲／過期行情仍不可成交。").font(.caption)
                }
            }
    }.navigationTitle("交易偏好")}
}

struct OfflineSettingsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{Form{
            if let sim=model.state?.simulation{
                Section("B 離線沙盒（只影響未來）"){
                    SimulationControls()
                    Picker("市場情境",selection:Binding(get:{sim.scenario},set:{v in Task{await model.configureSimulation(scenario:v)}})){ForEach(["多頭","空頭","盤整","恐慌","復甦"],id:\.self){Text($0)}}
                    VStack(alignment:.leading){Text("波動係數 \(sim.volatility,specifier:"%.1f")×");Slider(value:Binding(get:{sim.volatility},set:{v in Task{await model.configureSimulation(volatility:v)}}),in:0.1...5,step:0.1)}
                    VStack(alignment:.leading){Text("流動性 \(sim.liquidity,specifier:"%.1f")×");Slider(value:Binding(get:{sim.liquidity},set:{v in Task{await model.configureSimulation(liquidity:v)}}),in:0.1...5,step:0.1)}
                    Toggle("離開期間以 1× 計時，重開才補算",isOn:Binding(get:{model.state?.continueWhileAway ?? true},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(continueWhileAway:v,context:context)}}}))
                    Text("切到 A 期間 B 暫停；相同時間線可重播。事件均為模擬情境，非真實新聞。").font(.caption)
                    if model.catchupTarget != nil{Button("繼續補算"){Task{await model.catchUp()}}}
                }
            }

            if model.state?.mode != .offline{Section{Text("這些偏好屬於 B 帳戶。請在模式與帳戶選擇 B，完整重新啟動後再調整。").font(.footnote)}}
    }.navigationTitle("離線模擬")}
}

struct AppearanceNotificationSettings:View{
    @EnvironmentObject var model:AppModel
    var body:some View{Form{
            Section("外觀"){
                Picker("主題",selection:$model.settings.theme){Text("深色").tag("dark");Text("淺色").tag("light");Text("跟隨系統").tag("system")}.onChange(of:model.settings.theme){_,_ in model.saveSettings()}
                Toggle("臺灣紅漲綠跌",isOn:$model.settings.taiwanColors).onChange(of:model.settings.taiwanColors){_,_ in model.saveSettings()}
                Toggle("遮蔽資產金額",isOn:$model.settings.hideBalances).onChange(of:model.settings.hideBalances){_,_ in model.saveSettings()}
            }
            Section("目前帳戶通知"){
                NavigationLink("通知中心"){AccountInboxView()}
                Button("啟用／檢查系統通知權限"){Task{await model.enableNotifications()}}
                if model.state?.notificationEnabled==true{Button("停用此帳戶系統通知"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.configureNotifications(false,context:context)}}}}
                Text("只有實際運作中的行情／交易引擎能偵測事件。沒有背景即時監控保證；B 補算事件會標示補算發現。拒絕權限仍保留 App 內事件。").font(.caption)
            }
    }.navigationTitle("外觀與通知")}
}
