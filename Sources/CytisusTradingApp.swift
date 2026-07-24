import SwiftUI

@main
struct CytisusTradingApp: App {
    @StateObject private var model = StudioModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1060, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 780)

        Settings {
            PrivacyView()
                .environmentObject(model)
                .frame(width: 620, height: 430)
        }
    }
}
