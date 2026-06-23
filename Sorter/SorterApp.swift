import SwiftUI

@main
struct SorterApp: App {
    @StateObject private var store: ManagedRouteStore
    @StateObject private var routesVM: RoutesViewModel
    @StateObject private var tunnelStore: TunnelConfigStore
    @StateObject private var tunnelsVM: TunnelsViewModel

    init() {
        let s = ManagedRouteStore()
        _store = StateObject(wrappedValue: s)
        _routesVM = StateObject(wrappedValue: RoutesViewModel(store: s))
        let ts = TunnelConfigStore()
        _tunnelStore = StateObject(wrappedValue: ts)
        _tunnelsVM = StateObject(wrappedValue: TunnelsViewModel(store: ts))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(routesVM)
                .environmentObject(tunnelStore)
                .environmentObject(tunnelsVM)
                .frame(minWidth: 820, minHeight: 520)
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                ) { _ in
                    Task { await tunnelsVM.disconnectAll() }
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarStatusView()
                .environmentObject(routesVM)
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(routesVM.missingCount > 0 ? Color.orange : Color.primary)
        }
        .menuBarExtraStyle(.menu)
    }
}
