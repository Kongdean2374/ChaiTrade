import SwiftUI
import ChaiTradeCore

private extension ProviderID{
    var marketsDescription:String{switch self{case .coinbase:"加密貨幣現貨（美元等交易對）";case .fugle:"台灣股票、ETF與指數；依方案與商品權限";case .fugleFutures:"台灣期貨；須核對實際契約與規則";case .alpaca:"美股與ETF，IEX單一交易所行情";case .twelveData:"外匯參考行情；預設不供撮合";case .binance:"USDT線性永續合約公開行情"}}
    var capability:String{switch self{case .coinbase:"成交價、前五檔、歷史K線與24小時統計。即時頁優先串流，並有依配額輪詢的恢復路徑。";case .fugle:"報價、買賣檔、成交與K線依權限提供。整股與零股資料不得互相冒充。";case .fugleFutures:"行情與歷史依方案提供；契約乘數、到期與保證金須另外核對，未確認前不開放新委託。";case .alpaca:"報價、成交與K線。IEX不代表全美綜合行情；新聞另外依來源授權。";case .twelveData:"外匯參考價與歷史資料；沒有真實買賣檔，不會補造五檔。估算模型需另行明確啟用。";case .binance:"深度、K線、標記價、資金費與24小時統計。某些地區無法使用，會顯示實際限制。"}}
    var instructionsURL:URL{let address:String=switch self{case .coinbase:"https://docs.cdp.coinbase.com/exchange/docs/welcome";case .fugle,.fugleFutures:"https://developer.fugle.tw/";case .alpaca:"https://docs.alpaca.markets/docs/about-market-data-api";case .twelveData:"https://twelvedata.com/docs";case .binance:"https://developers.binance.com/docs/derivatives/usds-margined-futures/market-data/rest-api/Order-Book"};return URL(string:address)!}
    var budgetDescription:String{switch self{case .coinbase:"App共用公開請求預算，每秒最多3次，超過配額會排隊。";case .fugle,.fugleFutures:"App預設每分鐘最多30次；實際方案更低時請調整來源配額。";case .alpaca:"App預設每分鐘最多60次；各端點共用預算。";case .twelveData:"App預設每分鐘最多8次；免費與付費方案權限不同。";case .binance:"App每秒最多2次；遇限流依來源要求退避。"}}
}
struct ConnectionsView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    var body:some View{List{
        Section{Text("選市場、了解來源、再連線。這裡只取得行情，不會向交易所傳送委託。").font(.subheadline)}
        if model.state?.mode == .offline{Section{Label("目前是完全離線帳戶",systemImage:"airplane");Text("B不建立行情網路連線，也不讀取Keychain。要設定A行情，請到模式與帳戶選擇A，完整重新啟動後再回來。").font(.footnote);NavigationLink("模式與帳戶"){ModeAccountSettings()}}}
        else{Section("可用來源"){ForEach(ProviderID.allCases,id:\.self){id in NavigationLink{ProviderSettings(id:id)}label:{VStack(alignment:.leading,spacing:7){Text(id.label).font(.headline);Text(id.marketsDescription).font(.caption).foregroundStyle(.secondary);Text(id.needsKey ? (model.credentialReady[id]==true ? "金鑰已存於此裝置":"需要自己的行情金鑰"):"公開行情，不需金鑰").font(.caption).foregroundStyle(id.needsKey && model.credentialReady[id] != true ? Color.orange:Color.secondary)}}}}}
        Section("來源使用說明"){Text("只有實際取得且通過時間、品質與規則檢查的行情才能用於本機撮合。延遲、過期、無權限與限流會分別說明；部位、帳務及撤單仍可查看與操作。").font(.footnote)}
    }.navigationTitle("行情連線").toolbar{if model.state?.mode == .offline{Button("完成"){dismiss()}}}.onAppear{model.loadCredentialReadiness()}}
}
struct ProviderSettings:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.openURL) var openURL
    let id:ProviderID
    @State private var key=""
    @State private var secret=""
    @State private var result=""
    @State private var testing=false
    @State private var deleteKey=false
    @State private var openInstructions=false
    var body:some View{Form{
        Section("1 · 確認支援市場"){Text(id.marketsDescription).font(.headline);Text(id.capability).font(.subheadline);Text(id.budgetDescription).font(.caption).foregroundStyle(.secondary)}
        if model.state?.mode == .online{
            Section("2 · 行情權限"){
                if id.needsKey{
                    Text(model.credentialReady[id]==true ? "此裝置已有金鑰。需要更換時才在下方輸入。":"請從官方申請自己合法可用的行情權限。").font(.footnote)
                    SecureField("新的API Key",text:$key).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                    if id == .alpaca{SecureField("新的API Secret",text:$secret).privacySensitive()}
                    Button("保存至裝置Keychain"){save()}.disabled(key.isEmpty || (id == .alpaca && secret.isEmpty))
                    if model.credentialReady[id]==true{Button("刪除此來源金鑰",role:.destructive){deleteKey=true}}
                }else{Text("這個公開來源不需要API Key。來源仍可能有地區、服務或配額限制。").font(.footnote)}
                Button("查看官方申請與使用說明"){openInstructions=true}
                Text("金鑰只留在裝置Keychain，不會放入帳戶備份、日誌或GitHub；不要貼到聊天室。").font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · 測試與更新"){
                Button(testing ? "測試中…":"測試此來源行情"){Task{await test()}}.disabled(testing)
                if id != .alpaca{Button(model.catalogLoading ? "更新商品中…":"更新此來源商品目錄"){Task{await model.refreshCatalog(id)}}.disabled(model.catalogLoading)}
                else{NavigationLink("搜尋官方美股／ETF目錄"){USStockDiscoveryView()}}
                if !result.isEmpty{Text(result).font(.subheadline).accessibilityIdentifier("connectionResult")}
                if let issue=model.catalogIssue{Text(issue).font(.caption)}
                Text("這個測試只證明當次讀取結果。持續更新、斷線恢復與歷史K線仍以實際操作和驗收結果為準。").font(.caption).foregroundStyle(.secondary)
            }
        }else{Section{Text("B完全離線；請先切換至A並重新啟動，才可設定或測試網路來源。").font(.footnote)}}
    }.navigationTitle(id.label).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("刪除此裝置的來源金鑰？",isPresented:$deleteKey,titleVisibility:.visible){Button("刪除金鑰",role:.destructive){do{try KeychainVault.write("",key:id.rawValue+".key");try KeychainVault.write("",key:id.rawValue+".secret");model.loadCredentialReadiness();result="金鑰已刪除；帳務與歷史保留。"}catch{result="無法刪除，請確認裝置已解鎖後重試。"}}}
        .confirmationDialog("前往行情來源官方網站？",isPresented:$openInstructions,titleVisibility:.visible){Button("開啟官方說明"){openURL(id.instructionsURL)}}
    }
    private func save(){guard model.context?.mode == .online else{return};do{try KeychainVault.write(key,key:id.rawValue+".key");if id == .alpaca{try KeychainVault.write(secret,key:id.rawValue+".secret")};key="";secret="";model.loadCredentialReadiness();result="已安全保存於此裝置。請接著測試行情。";Task{await model.quoteScheduler.retry(Set((model.state?.instruments ?? []).filter{$0.provider==id}.map(\.id)));await model.ensureQuoteService()}}catch{result="保存失敗，請解鎖裝置後重試。"}}
    private func test()async{
        guard model.context?.mode == .online,!testing,let context=model.context else{return};testing=true;defer{testing=false}
        do{guard let instrument=model.state?.instruments.first(where:{$0.provider==id && $0.asset != .index})else{result="此來源尚無可測商品，請先更新商品目錄。";return}
            let q=try await model.provider(id).quote(instrument,now:model.now,includeSummary:true)
            guard model.context==context else{return}
            if let engine=model.engine{try await engine.ingest(q,now:model.now,context:context);await model.refresh()}
            result="已讀取 "+instrument.symbol+" · "+MarketText.number(q.last)+" "+instrument.currency+"。"+(q.quality == .realtime ? "來源標示即時；實際撮合仍需通過新鮮度與規則檢查。":"目前不是可即時撮合的行情。")
        }catch{result=(error as? MarketDataFailure)?.localizedDescription ?? "無法完成測試，請確認連線、權限與來源支援商品後重試。"}
    }
}
struct USStockDiscoveryView:View{
    @EnvironmentObject var model:AppModel
    @State private var query=""
    @State private var page:DirectoryPage?
    @State private var message=""
    @State private var loading=false
    var body:some View{List{
        Section{
            Text("搜尋Nasdaq Trader公開商品身份，涵蓋NASDAQ與其他上市交易所的股票、ETF。目錄不代表已取得IEX即時行情權限。").font(.footnote)
            TextField("代碼或英文名稱",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(loading ? "搜尋中…":"搜尋官方目錄"){Task{await search(offset:0)}}.disabled(loading)
            if !message.isEmpty{Text(message).font(.subheadline)}
        }
        if let page{
            Section("符合 \(page.total) 個商品"){
                ForEach(page.instruments){instrument in
                    Button{Task{await add(instrument)}}label:{VStack(alignment:.leading,spacing:5){Text(instrument.symbol+" · "+instrument.name);Text((instrument.identity?.exchange ?? "")+" · "+instrument.asset.label+" · USD").font(.caption).foregroundStyle(.secondary)}}.disabled(loading)
                }
                HStack{if page.offset>0{Button("上一頁"){Task{await search(offset:max(0,page.offset-40))}}};Spacer();if page.offset+page.instruments.count<page.total{Button("下一頁"){Task{await search(offset:page.offset+40)}}}}.disabled(loading)
            }
            Section("身份資料來源"){Text("Nasdaq Trader · "+page.updatedAt).font(.caption);Text("只在挑選時加入本機目錄；行情、精度及可成交狀態另行驗證，不合併同名跨交易所商品。").font(.caption)}
        }
    }.navigationTitle("探索美股與ETF")}
    private func search(offset:Int)async{
        guard model.context?.mode == .online,!loading,let context=model.context else{return};loading=true;defer{loading=false}
        do{let directory=try USStockDirectory(mode:.online,transport:ReadOnlyTransport(mode:.online)),result=try await directory.search(query.trimmingCharacters(in:.whitespacesAndNewlines),offset:offset);guard model.context==context else{return};page=result;message=result.total==0 ? "官方目錄找不到符合的股票或ETF。":"點選商品加入行情列表。"}catch{message=error.localizedDescription}
    }
    private func add(_ instrument:Instrument)async{
        guard !loading,let engine=model.engine,let context=model.context,context.mode == .online else{return};loading=true;defer{loading=false}
        do{try await engine.importOnlineInstruments([instrument],context:context);guard model.context==context else{return};await model.refresh();message="已加入 "+instrument.symbol+" · "+instrument.name+"。行情將依來源權限載入。"}catch{message=error.localizedDescription}
    }
}
