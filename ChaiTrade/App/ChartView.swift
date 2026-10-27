import SwiftUI
import WebKit
import ChaiTradeCore

struct ChartView: UIViewRepresentable {
    @EnvironmentObject var model: AppModel
    var indicator: String
    var period: Int
    var line: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript=true
        let view=WKWebView(frame:.zero,configuration:config);view.isOpaque=false;view.backgroundColor = .clear
        view.navigationDelegate=context.coordinator
        if let url=Bundle.main.url(forResource:"index",withExtension:"html",subdirectory:"Resources/ChartWeb") {
            view.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
        }
        return view
    }
    func updateUIView(_ web: WKWebView, context: Context) {
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
        if let p=model.state?.positions[model.selectedID],p.quantity != .zero {priceLines.append(["price":p.average.displayDouble,"title":"模擬成本","color":"#ffb454"])}
        for order in model.state?.orders.values.filter({$0.status.open && $0.request.instrumentID==model.selectedID}) ?? [] {
            if let p=order.request.price ?? order.request.trigger {priceLines.append(["price":p.displayDouble,"title":order.request.kind.label,"color":"#82aaff"])}
        }
        let data: [String:Any]=["id":model.selectedID,"candles":candles.map{["time":$0.time,"open":$0.open,"high":$0.high,"low":$0.low,"close":$0.close,"volume":$0.volume]},"overlays":overlays,"drawings":drawingData,"lines":priceLines,"line":line,"taiwan":model.settings.taiwanColors,"dark":model.settings.theme != "light"]
        context.coordinator.payload=data
        context.coordinator.render(web)
    }
    @MainActor final class Coordinator: NSObject,WKNavigationDelegate {
        var ready=false
        var payload: [String:Any]=[:]
        func webView(_ webView: WKWebView,didFinish navigation: WKNavigation!) {ready=true;render(webView)}
        func render(_ web: WKWebView) {
            guard ready else{return}
            web.callAsyncJavaScript("window.render(data)",arguments:["data":payload],in:nil,in:.page){_ in}
        }
        func webView(_ webView: WKWebView,decidePolicyFor navigationAction: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            guard let url=navigationAction.request.url,url.isFileURL,url.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path+"/") else {decisionHandler(.cancel);return}
            decisionHandler(.allow)
        }
    }
}
