import SwiftUI
import ChaiTradeCore

@main
struct ChaiTradeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .preferredColorScheme(model.settings.theme == "system" ? nil : model.settings.theme == "light" ? .light : .dark)
                .tint(.orange)
                .task { await model.boot() }
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for:.seconds(1))
                        if scenePhase == .active { await model.tick() }
                    }
                }
                .onChange(of:scenePhase) { _, phase in
                    Task { if phase == .active { await model.resume() } else { await model.suspend() } }
                }
        }
    }
}
