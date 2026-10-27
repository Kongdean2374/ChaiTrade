import SwiftUI
import UniformTypeIdentifiers
import ChaiTradeCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var backupPassword=""
    @State private var importing=false
    @State private var confirmRestore=false
    @State private var restoreURL: URL?
    @State private var resetStage=false
    @State private var resetText=""
    @State private var confirmReset=false
    var body: some View {
        Form {
            Section("運作模式（下次完整啟動生效）") {
                Text("目前：\(model.settings.activeMode.label)")
                ForEach(Mode.allCases,id:\.self){mode in Button(mode.label){model.setPending(mode)}}
                if let pending=model.settings.pendingMode{Text("待套用：\(pending.label)。請完整關閉並重新開啟；返回主畫面不等於程序重啟。").font(.footnote).foregroundStyle(.orange);Button("取消待切換"){model.setPending(nil)}}
            }
            Section("外觀"){
                Picker("主題",selection:$model.settings.theme){Text("深色").tag("dark");Text("淺色").tag("light");Text("跟隨系統").tag("system")}.onChange(of:model.settings.theme){_,_ in model.saveSettings()}
                Toggle("臺灣紅漲綠跌",isOn:$model.settings.taiwanColors).onChange(of:model.settings.taiwanColors){_,_ in model.saveSettings()}
                Toggle("遮蔽資產金額",isOn:$model.settings.hideBalances).onChange(of:model.settings.hideBalances){_,_ in model.saveSettings()}
            }
            Section("交易與風險"){
                Toggle("啟用槓桿／合約功能",isOn:Binding(get:{model.state?.leverageEnabled ?? false},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(leverageEnabled:v,context:context)}}}))
                Text("啟用即表示了解虛擬合約可能強平及穿倉，負債會保留。現貨不自動借貸。").font(.caption).foregroundStyle(.orange)
                if model.state?.mode == .online{
                    Toggle("允許合約採自訂參考風險價模型",isOn:Binding(get:{model.state?.useReferenceRiskPrice ?? false},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(useReferenceRiskPrice:v,context:context)}}}))
                    Text("缺少交易所標記價時，只有明確啟用才可用來源參考價計算自訂風險。畫面會標示此模型；不能宣稱為交易所標記價。").font(.caption)
                    Toggle("允許 E3 參考價估算撮合",isOn:Binding(get:{model.state?.allowEstimatedExecution ?? false},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(allowEstimated:v,context:context)}}}))
                    Text("E3 使用明示價差與有限流動性模型，成交永久標記為估算。延遲／過期行情仍不可成交。").font(.caption)
                }
            }
            if let sim=model.state?.simulation{
                Section("B 離線沙盒（只影響未來）"){
                    SimulationControls()
                    Picker("市場情境",selection:Binding(get:{sim.scenario},set:{v in Task{await model.configureSimulation(scenario:v)}})){ForEach(["多頭","空頭","盤整","恐慌","復甦"],id:\.self){Text($0)}}
                    VStack(alignment:.leading){Text("波動係數 \(sim.volatility,specifier:"%.1f")×");Slider(value:Binding(get:{sim.volatility},set:{v in Task{await model.configureSimulation(volatility:v)}}),in:0.1...5,step:0.1)}
                    VStack(alignment:.leading){Text("流動性 \(sim.liquidity,specifier:"%.1f")×");Slider(value:Binding(get:{sim.liquidity},set:{v in Task{await model.configureSimulation(liquidity:v)}}),in:0.1...5,step:0.1)}
                    Toggle("離開期間以 1× 計時，重開才補算",isOn:Binding(get:{model.state?.continueWhileAway ?? true},set:{v in Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.updatePreferences(continueWhileAway:v,context:context)}}}))
                    Text("固定種子 \(String(sim.seed)) · \(sim.algorithm)\n切到 A 期間 B 暫停；不常駐背景。").font(.caption.monospaced())
                    if model.catchupTarget != nil{Button("繼續補算"){Task{await model.catchUp()}}}
                }
            }
            Section("A 真實行情來源") {
                if model.state?.mode == .offline{Text("B 不讀取金鑰、不建立網路 Provider。切到 A 並完整重新啟動後配置。").font(.footnote)}
                else{ForEach(ProviderID.allCases,id:\.self){id in NavigationLink(id.label){ProviderSettings(id:id)}}}
            }
            Section("目前帳戶備份與還原") {
                SecureField("備份／還原密碼（可留空）",text:$backupPassword)
                Text("密碼備份使用 AES-256-GCM 與 PBKDF2-HMAC-SHA256（600,000 次）。密碼遺失無法恢復。API 金鑰不進備份。").font(.caption)
                Button("匯出目前帳戶備份"){Task{await model.export(kind:"backup",password:backupPassword)}}
                Button("完整備份 A 與 B（各自隔離）"){Task{await model.export(kind:"both",password:backupPassword)}}
                Button("選擇備份並驗證還原"){importing=true}
                Text("還原會先驗證模式、版本、校驗碼與帳本，再取代此帳戶。雙帳戶備份會取出符合目前模式的帳戶；另一帳戶保持不變。原帳戶會保存本機恢復點；A／B 不可交叉還原。").font(.caption).foregroundStyle(.secondary)
            }
            Section("重設目前帳戶") {
                Button("重設 \(model.settings.activeMode.accountID)",role:.destructive){resetStage=true}
                if resetStage{Text("先匯出備份，再輸入 RESET 二次確認。另一帳戶不受影響。").font(.caption);TextField("輸入 RESET",text:$resetText).autocorrectionDisabled();Button("確認重設目前帳戶",role:.destructive){confirmReset=true}.disabled(resetText != "RESET")}
            }
            Section("關於"){
                Text("ChaiTrade 1.0 · 原生本機模擬交易\n無真實交易、錢包、入出金、廣告或遙測。")
                NavigationLink("第三方授權"){LicenseView()}
                Text("建置成功、IPA 結構驗證、裝機簽署、實機啟動及交易驗收是不同項目。未簽名 IPA 須自行使用有效簽署方式安裝。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("設定").toolbar{Button("完成"){dismiss()}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.json]){result in switch result{case .success(let url):restoreURL=url;confirmRestore=true;case .failure(let error):model.error=error.localizedDescription}}
            .confirmationDialog("以備份取代目前帳戶？",isPresented:$confirmRestore,titleVisibility:.visible){Button("確認驗證並還原",role:.destructive){if let url=restoreURL{Task{await model.importBackup(url,password:backupPassword)}}}}
            .confirmationDialog("確定重設此帳戶？",isPresented:$confirmReset,titleVisibility:.visible){Button("重設並保存恢復點",role:.destructive){Task{await reset()}}}
    }
    func reset() async {
        guard let engine=model.engine,let context=model.context else{return}
        await model.run{
            let current=await engine.snapshot(),backup=try BackupService.export(current,password:nil,time:model.now)
            let dir=model.root.appendingPathComponent("accounts/\(context.accountID)/snapshots")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try backup.write(to:dir.appendingPathComponent("before-reset-\(Date().timeIntervalSince1970).chaitrade"),options:.atomic)
            let fresh=try TradingEngine.initial(mode:context.mode,baseCurrency:current.baseCurrency,capital:Amount("1000000"),time:model.now)
            try await engine.restore(fresh,context:context);try await engine.initializeQuotes(context:context)
            resetStage=false;resetText="";model.notice="目前帳戶已重設；原資料有本機恢復點"
        }
    }
}
struct ProviderSettings: View {
    @EnvironmentObject var model: AppModel
    let id: ProviderID
    @State private var key=""
    @State private var secret=""
    @State private var result=""
    var body: some View {
        Form{
            Text("只讀取行情，不使用交易 SDK、帳戶委託或轉帳 API。請使用自己的合法行情權限，勿把金鑰提交到 GitHub。").font(.footnote)
            if id.needsKey{SecureField("API Key",text:$key);if id == .alpaca{SecureField("API Secret",text:$secret)};Button("保存至裝置 Keychain"){save()};Button("刪除此來源金鑰",role:.destructive){key="";secret="";save()}}
            Button("保存並測試讀取行情"){save();Task{await test()}}
            if id != .alpaca{Button("載入來源商品目錄（最多 2,000 個）"){Task{do{guard let engine=model.engine,let context=model.context else{return};let products=try await model.provider(id).products();try await engine.importOnlineInstruments(products,context:context);await model.refresh();result="已加入 \(products.count) 個來源商品；既有資料未改寫"}catch{result=error.localizedDescription}}}}
            if !result.isEmpty{Text(result).font(.caption)}
            if let status=model.providerStatus[id]{Text(status).font(.caption)}
            Text("\(id == .alpaca ? "IEX 單一市場，不是全美綜合報價。":id == .twelveData ? "外匯參考價，E3 估算預設不成交。":"資料能力、時間戳及授權以實際回應為準。")\n需要授權的來源尚未提供憑證時，不代表已完成實際連線驗證。").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle(id.label)
            .onAppear{guard model.state?.mode == .online else{return};do{key=try KeychainVault.read(id.rawValue+".key");secret=try KeychainVault.read(id.rawValue+".secret")}catch{result=error.localizedDescription}}
    }
    func save(){guard model.state?.mode == .online else{return};do{try KeychainVault.write(key,key:id.rawValue+".key");try KeychainVault.write(secret,key:id.rawValue+".secret");result="金鑰已保存於裝置，不包含在備份內"}catch{result=error.localizedDescription}}
    func test() async{do{guard let i=model.state?.instruments.first(where:{$0.provider==id})else{result="請先載入來源商品目錄，並核對確切合約代碼";return};let quote=try await model.provider(id).quote(i,now:Int64(Date().timeIntervalSince1970));result="成功讀取 \(i.symbol) · \(quote.last) · \(quote.quality.rawValue) · \(quote.grade.rawValue)"}catch{result=error.localizedDescription}}
}
struct LicenseView: View {
    var license: String { guard let url=Bundle.main.url(forResource:"LightweightCharts-LICENSE",withExtension:nil,subdirectory:"Licenses") else{return "授權資源遺失"};return (try? String(contentsOf:url,encoding:.utf8)) ?? "授權檔無法讀取" }
    var body: some View{ScrollView{VStack(alignment:.leading,spacing:16){Text("Lightweight Charts™\nCopyright © TradingView, Inc.\nhttps://www.tradingview.com/").font(.headline);Text("圖表資源以 Apache License 2.0 授權，完整條款隨 App 打包。")
        Text(license).font(.caption)
        Text("SQLite：Public Domain。Apple 系統框架依 Apple 平台條款提供。ChaiTrade 自有程式碼採 MIT。").font(.footnote)
    }.padding()}}
}
