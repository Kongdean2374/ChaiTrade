import SwiftUI
import UIKit
import ChaiTradeCore

@main
struct ChaiTradeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().modifier(UITestVisualEnvironment()).onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in model.clearChartCaches()}.environmentObject(model)
                .preferredColorScheme(model.settings.theme == "system" ? nil : model.settings.theme == "light" ? .light : .dark)
                .tint(.orange)
                .task { await model.boot() }
                .task(id:scenePhase) {
                    guard scenePhase == .active else{return}
                    while !Task.isCancelled {
                        do{try await Task.sleep(for:.seconds(1))}catch{return}
                        guard !Task.isCancelled else{return}
                        await model.tick()
                    }
                }
                .onChange(of:scenePhase) { _, phase in
                    Task { if phase == .active { await model.resume() } else { await model.suspend() } }
                }
        }
    }
}
