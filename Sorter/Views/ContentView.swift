import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case devices
    case routes
    case tunnels

    var id: String { rawValue }
    var title: String {
        switch self {
        case .devices: return "Network Interface"
        case .routes:  return "Routing Table"
        case .tunnels: return "SSH Tunneling"
        }
    }
    var icon: String {
        switch self {
        case .devices: return "network"
        case .routes:  return "arrow.triangle.branch"
        case .tunnels: return "lock.shield"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ManagedRouteStore
    @EnvironmentObject private var tunnelsVM: TunnelsViewModel
    @State private var selection: SidebarItem? = .routes

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .navigationTitle("Sorter")
        } detail: {
            switch selection ?? .routes {
            case .devices:
                DevicesView()
            case .routes:
                RoutesView()
            case .tunnels:
                TunnelsView()
            }
        }
    }
}
