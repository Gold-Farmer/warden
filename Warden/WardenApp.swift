import SwiftUI

@main
struct WardenApp: App {
    @State private var registry = ServiceRegistry()
    @State private var scheduler = RefreshScheduler()

    var body: some Scene {
        WindowGroup {
            ContentView(
                dashboardViewModel: DashboardViewModel(registry: registry, scheduler: scheduler),
                settingsViewModel: SettingsViewModel(registry: registry)
            )
            .frame(minWidth: 900, minHeight: 650)
            .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 850)
        #endif
    }
}
