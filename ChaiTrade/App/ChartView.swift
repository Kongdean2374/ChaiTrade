import SwiftUI
import WebKit
import ChaiTradeCore

@MainActor private final class LayoutAwareChartWebView:WKWebView{
    var geometryChanged:((WKWebView)->Void)?
    private var previousSize=CGSize.zero
    override func layoutSubviews(){
        super.layoutSubviews()
        guard bounds.size != previousSize else{return}
        previousSize=bounds.size;geometryChanged?(self)
    }
    override func didMoveToWindow(){super.didMoveToWindow();geometryChanged?(self)}
}

struct ChartView: UIViewRepresentable {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var indicator: String
    var period: Int
    var line: Bool
    var role:String="inline"
    var interactionEnabled=true
    func makeCoordinator() -> Coordinator { Coordinator(model:model,role:role) }
    func makeUIView(context: Context) -> WKWebView {
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript=true
        config.userContentController.add(context.coordinator,name:"intent")
        let view=LayoutAwareChartWebView(frame:.zero,configuration:config);view.isOpaque=false;view.backgroundColor = .clear
        view.geometryChanged={ [weak coordinator=context.coordinator] web in
            Task{@MainActor [weak web] in await Task.yield();guard let web else{return};coordinator?.render(web)}
        }
        // The inline document has no own scrollable page. Let native vertical
        // drags scroll its SwiftUI parent while JavaScript keeps horizontal tools.
        if role=="inline"{view.scrollView.isScrollEnabled=false;view.scrollView.bounces=false}
        let spinner=UIActivityIndicatorView(style:.medium);spinner.startAnimating()
        let label=UILabel();label.text="正在繪製圖表…";label.font = .preferredFont(forTextStyle:.caption1);label.textColor = .secondaryLabel
        let overlay=UIStackView(arrangedSubviews:[spinner,label]);overlay.axis = .vertical;overlay.alignment = .center;overlay.spacing=8;overlay.translatesAutoresizingMaskIntoConstraints=false;overlay.isAccessibilityElement=true;overlay.accessibilityLabel="正在繪製圖表"
        view.addSubview(overlay);NSLayoutConstraint.activate([overlay.centerXAnchor.constraint(equalTo:view.centerXAnchor),overlay.centerYAnchor.constraint(equalTo:view.centerYAnchor)])
        context.coordinator.loadingOverlay=overlay
        view.navigationDelegate=context.coordinator
        model.chartWebView=view
        if let url=Bundle.main.url(forResource:"index",withExtension:"html",subdirectory:"ChartWeb") {
            view.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
        }
        return view
    }
    static func dismantleUIView(_ web:WKWebView,coordinator:Coordinator){
        coordinator.cancel();(web as? LayoutAwareChartWebView)?.geometryChanged=nil
        web.configuration.userContentController.removeScriptMessageHandler(forName:"intent");web.navigationDelegate=nil;web.stopLoading()
        if coordinator.model.chartWebView===web{coordinator.model.chartWebView=nil}
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        web.accessibilityElementsHidden = !interactionEnabled;web.isUserInteractionEnabled=interactionEnabled
        model.chartWebView=web
        let candles=model.candles
        let values=candles.map(\.close)
        var overlays: [[String:Any]]=[]
        func add(_ name: String, _ data: [Double?], _ color: String, pane: Int = 0) {
            overlays.append(["name":name,"color":color,"pane":pane,"data":zip(candles,data).compactMap { candle,value -> [String:Any]? in guard let value,value.isFinite else{return nil};return ["time":candle.time,"value":value] }])
        }
        switch indicator {
        case "MA": add("MA",Indicators.ma(values,period:period),"#ffb454")
        case "EMA": add("EMA",Indicators.ema(values,period:period),"#82aaff")
        case "BOLL": let b=Indicators.bollinger(values,period:period);add("BOLL",b.middle,"#ffb454");add("UP",b.upper,"#82aaff");add("LOW",b.lower,"#82aaff")
        case "RSI": add("RSI",Indicators.rsi(values,period:period),"#c792ea",pane:1)
        case "MACD": let m=Indicators.macd(values);add("DIF",m.line,"#ffb454",pane:1);add("SIGNAL",m.signal,"#82aaff",pane:1);add("HIST",m.histogram,"#89ddff",pane:1)
        case "KD": let kd=Indicators.kd(candles,period:period);add("K",kd.k,"#ffb454",pane:1);add("D",kd.d,"#82aaff",pane:1)
        case "VWAP": add("VWAP",Indicators.vwap(candles,timeZone:model.selected?.rules.timeZone ?? "UTC"),"#ffb454")
        case "ATR": add("ATR",Indicators.atr(candles,period:period),"#82aaff",pane:1)
        default: break
        }
        let drawings=(model.state?.drawings ?? []).filter{$0.instrumentID==model.selectedID}
        let drawingData=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(drawings))) as? [[String:Any]] ?? []
        var priceLines: [[String:Any]]=[]
        for p in model.state?.heldPositions(model.selectedID) ?? []{priceLines.append(["price":p.average.displayDouble,"title":(p.side?.label ?? "持倉")+"模擬成本","color":"#ffb454"])}
        for order in model.state?.orders.values.filter({$0.status.open && $0.request.instrumentID==model.selectedID}) ?? [] {
            if let p=order.request.price ?? order.request.trigger {priceLines.append(["id":order.id,"price":p.displayDouble,"title":order.request.kind.label,"color":"#82aaff"])}
        }
        let data: [String:Any]=["id":model.selectedID,"account":model.context?.accountID ?? "","epoch":model.context?.epoch.uuidString ?? "","fullscreen":role=="fullscreen","candles":candles.map{["time":$0.time,"open":$0.open,"high":$0.high,"low":$0.low,"close":$0.close,"volume":$0.volume.map{$0 as Any} ?? NSNull()]},"overlays":overlays,"drawings":drawingData,"lines":priceLines,"line":line,"timeZone":model.selected?.rules.timeZone ?? "UTC","fontSize":dynamicTypeSize.isAccessibilitySize ? 16:12,"taiwan":model.settings.taiwanColors,"dark":model.settings.theme == "system" ? web.traitCollection.userInterfaceStyle == .dark:model.settings.theme != "light"]
        context.coordinator.payload=data
        context.coordinator.interval=model.interval
        context.coordinator.render(web)
    }
    @MainActor final class Coordinator: NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        let model: AppModel
        let role:String
        weak var loadingOverlay:UIStackView?
        var interval:Int64=60
        init(model:AppModel,role:String){self.model=model;self.role=role}
        var ready=false
        var payload: [String:Any]=[:]
        private var lastRendered:Data?
        private var inFlight:Data?
        private var retryTask:Task<Void,Never>?
        private var lastAttempt:Data?
        private var deferredAttempts=0
        private var processReloads=0
        func cancel(){retryTask?.cancel();retryTask=nil;inFlight=nil}
        private func record(_ message:String){
            #if DEBUG
            guard UITestSupport.session != nil else{return}
            let value=role+": "+message
            Task{@MainActor [weak self] in
                guard let self,self.model.uiTestChartDiagnostics.last != value else{return}
                self.model.uiTestChartDiagnostics=Array((self.model.uiTestChartDiagnostics+[value]).suffix(20))
            }
            #endif
        }
        func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
            guard message.name=="intent",message.frameInfo.isMainFrame,let body=message.body as? [String:Any],body.count<=8,
                  body["type"] as? String=="amend",body["account"] as? String==model.context?.accountID,body["epoch"] as? String==model.context?.epoch.uuidString,
                  body["instrument"] as? String==model.selectedID,let id=body["orderID"] as? String,id.utf8.count<=128,
                  let price=body["price"] as? Double,price.isFinite,price>0,let order=model.state?.orders[id],order.status.open,order.request.instrumentID==model.selectedID,
                  let rules=model.selected?.rules else{return}
            do {
                let raw=try Amount(String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),price))
                let quantized=try rules.roundedPrice(raw,.plain)
                model.chartAmendment=ChartAmendment(order:order,price:quantized)
            }catch{model.error=error.localizedDescription}
        }
        func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) {ready=true;record("local document ready");render(webView)}
        func render(_ web: WKWebView) {
            guard ready,web.window != nil,web.bounds.width>0,web.bounds.height>0,inFlight==nil,
                  let candles=payload["candles"] as? [[String:Any]],!candles.isEmpty,
                  let encoded=try? JSONSerialization.data(withJSONObject:payload,options:.sortedKeys),
                  encoded != lastRendered || model.chartRenderings[role]==nil else{return}
            if lastAttempt != encoded{lastAttempt=encoded;deferredAttempts=0}
            retryTask?.cancel();retryTask=nil;inFlight=encoded
            let capturedContext=model.context,instrument=payload["id"] as? String,renderInterval=interval
            record("render requested \(candles.count), size \(web.bounds.size)")
            web.callAsyncJavaScript("window.render(data); await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); const box=document.getElementById('chart'); return {count:data.candles.length,visible:box.clientWidth>0 && box.clientHeight>0 && box.querySelectorAll('canvas').length>0};",arguments:["data":payload],in:nil,in:.page){[weak self,weak web] result in
                Task{@MainActor in
                guard let self,let web,self.inFlight==encoded else{return};self.inFlight=nil
                guard let capturedContext,let instrument,self.model.context==capturedContext,self.model.selectedID==instrument,self.model.interval==renderInterval else{
                    // A new product/interval may have arrived while this single
                    // request was in flight. Drain its current payload even if
                    // B is paused and no further clock update will occur.
                    if self.payload["account"] as? String==self.model.context?.accountID,self.payload["epoch"] as? String==self.model.context?.epoch.uuidString,self.payload["id"] as? String==self.model.selectedID{self.render(web)}
                    return
                }
                guard (try? JSONSerialization.data(withJSONObject:self.payload,options:.sortedKeys))==encoded else{self.render(web);return}
                switch result{
                case .failure(let error):let code=(error as NSError).code;self.lastRendered=nil;self.record("render failed \(code)");self.model.chartError="本機圖表更新失敗（\(code)），請重載圖表或切換週期"
                case .success(let value):
                    let result=value as? [String:Any],count=result?["count"] as? Int ?? 0,visible=result?["visible"] as? Bool ?? false
                        guard visible,count>0 else{
                            self.lastRendered=nil;self.deferredAttempts+=1;self.record("waiting for canvas layout \(self.deferredAttempts)")
                            if self.deferredAttempts<=8{self.retryTask=Task{@MainActor [weak self,weak web] in
                                do{try await Task.sleep(for:.milliseconds(250))}catch{return}
                                guard let self,let web else{return};self.render(web)
                            }}
                            return
                        }
                        self.lastRendered=encoded;self.record("canvas rendered \(count)")
                        self.loadingOverlay?.isHidden=true
                        let evidence=ChartRenderEvidence(context:capturedContext,instrumentID:instrument,interval:renderInterval,count:count)
                        if self.model.chartRenderings[self.role] != evidence{self.model.chartRenderings[self.role]=evidence}
                }
                }
            }
        }
        func webViewWebContentProcessDidTerminate(_ webView:WKWebView){
            cancel();lastRendered=nil;ready=false
            guard payload["account"] as? String==model.context?.accountID,payload["epoch"] as? String==model.context?.epoch.uuidString,payload["id"] as? String==model.selectedID else{return}
            model.chartRenderings[role]=nil;loadingOverlay?.isHidden=false
            guard processReloads==0 else{model.chartError="本機圖表程序再次中斷，請重新開啟商品。";return}
            processReloads+=1;record("local content process interrupted; reload once");webView.reload()
        }
        func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error){failedLocalLoad()}
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){failedLocalLoad()}
        private func failedLocalLoad(){guard payload["account"] as? String==model.context?.accountID,payload["epoch"] as? String==model.context?.epoch.uuidString,payload["id"] as? String==model.selectedID else{return};model.chartError="本機圖表載入失敗，請切換週期或重新開啟商品。"}
        func webView(_ webView: WKWebView,decidePolicyFor navigationAction: WKNavigationAction,decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy)->Void) {
            guard let url=navigationAction.request.url,url.isFileURL,url.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path+"/") else {decisionHandler(.cancel);return}
            decisionHandler(.allow)
        }
    }
}
