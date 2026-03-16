import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .dashboard

    let dashboardViewModel: DashboardViewModel
    let settingsViewModel: SettingsViewModel

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2.fill"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
            .scrollContentBackground(.hidden)
            .background(Color.grafanaBg)
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .dashboard:
                    DashboardView(viewModel: dashboardViewModel)
                case .settings:
                    SettingsView(viewModel: settingsViewModel)
                }
            }
        }
        .preferredColorScheme(.dark)
        #else
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(viewModel: dashboardViewModel)
            }
            .tabItem {
                Label(Tab.dashboard.rawValue, systemImage: Tab.dashboard.icon)
            }
            .tag(Tab.dashboard)

            NavigationStack {
                SettingsView(viewModel: settingsViewModel)
            }
            .tabItem {
                Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
            }
            .tag(Tab.settings)
        }
        .preferredColorScheme(.dark)
        #endif
    }
}
