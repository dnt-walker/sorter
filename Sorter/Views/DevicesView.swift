import SwiftUI

struct DevicesView: View {
    @StateObject private var viewModel = DevicesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isLoading && viewModel.devices.isEmpty {
                Spacer()
                ProgressView("불러오는 중…")
                Spacer()
            } else if let error = viewModel.errorMessage, viewModel.devices.isEmpty {
                Spacer()
                ContentUnavailable(title: error, systemImage: "wifi.exclamationmark") {
                    Button("재시도") { viewModel.refresh() }
                }
                Spacer()
            } else {
                Table(viewModel.devices, selection: $viewModel.selectedID) {
                    TableColumn("상태") { d in
                        Label(d.statusText, systemImage: d.isUp ? "circle.fill" : "circle")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(d.isUp ? Color.green : Color.secondary)
                            .help(d.statusText)
                    }
                    .width(44)
                    TableColumn("표시 이름", value: \.displayName)
                    TableColumn("BSD 이름", value: \.bsdName)
                    TableColumn("IPv4") { d in Text(d.ipv4 ?? "—") }
                    TableColumn("상태") { d in Text(d.statusText) }
                }

                Divider()
                detail
                    .frame(height: 190)
            }
        }
        .onAppear { if viewModel.devices.isEmpty { viewModel.refresh() } }
    }

    private var header: some View {
        HStack {
            Text("네트워크 디바이스").font(.title2).bold()
            Spacer()
            Button { viewModel.refresh() } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        .padding()
    }

    @ViewBuilder
    private var detail: some View {
        if let d = viewModel.selectedDevice {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("세부 정보 (\(d.bsdName) / \(d.displayName))")
                        .font(.headline)
                    DetailRow("표시 이름", d.displayName)
                    DetailRow("BSD 이름", d.bsdName)
                    DetailRow("IPv4", d.ipv4 ?? "—")
                    DetailRow("IPv6", d.ipv6 ?? "—")
                    DetailRow("MAC", d.mac ?? "—")
                    DetailRow("상태", d.statusText)
                    DetailRow("MTU", d.mtu.map(String.init) ?? "—")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("디바이스를 선택하세요.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 라벨: 값 한 줄.
struct DetailRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

/// 간단한 빈 상태 컴포넌트 (macOS 13 호환).
struct ContentUnavailable<Action: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            action
        }
        .padding()
    }
}
