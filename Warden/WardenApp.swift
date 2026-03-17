import SwiftUI

@main
struct WardenApp: App {
    @State private var registry = ServiceRegistry()
    @State private var scheduler = RefreshScheduler()
    @State private var accountStore = AccountStore()
    @State private var proxyStore = ProxyStore()
    @State private var dashboardViewModel: DashboardViewModel?
    @State private var settingsViewModel: SettingsViewModel?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContainer(
                dashboardViewModel: dashboardViewModel,
                settingsViewModel: settingsViewModel,
                onCreate: createViewModels
            )
        } label: {
            Image(systemName: "shield.checkered")
        }
        .menuBarExtraStyle(.window)

        Window("Warden Dashboard", id: "dashboard") {
            if let vm = dashboardViewModel, let svm = settingsViewModel {
                ContentView(
                    dashboardViewModel: vm,
                    settingsViewModel: svm
                )
                .frame(minWidth: 900, minHeight: 650)
                .preferredColorScheme(.dark)
            } else {
                ProgressView("Loading...")
                    .frame(minWidth: 900, minHeight: 650)
                    .onAppear { createViewModels() }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 850)
    }

    private func createViewModels() {
        guard dashboardViewModel == nil else { return }
        dashboardViewModel = DashboardViewModel(registry: registry, scheduler: scheduler, accountStore: accountStore)
        settingsViewModel = SettingsViewModel(registry: registry, accountStore: accountStore, proxyStore: proxyStore)
    }
}

/// Wrapper that lives inside the MenuBarExtra so it can access @Environment(\.openWindow).
private struct MenuBarContainer: View {
    let dashboardViewModel: DashboardViewModel?
    let settingsViewModel: SettingsViewModel?
    let onCreate: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let vm = dashboardViewModel, let svm = settingsViewModel {
            MenuBarSummaryView(viewModel: vm, settingsViewModel: svm) {
                openWindow(id: "dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } else {
            ProgressView()
                .padding()
                .onAppear { onCreate() }
        }
    }
}
