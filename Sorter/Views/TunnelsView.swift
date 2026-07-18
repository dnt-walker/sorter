import SwiftUI

struct TunnelsView: View {
    @EnvironmentObject private var vm: TunnelsViewModel

    @State private var selectedID: TunnelConfig.ID?
    @State private var editSheet: EditSheet?
    @State private var configToDelete: TunnelConfig?

    private struct EditSheet: Identifiable {
        let id = UUID()
        let config: TunnelConfig?
    }

    var body: some View {
        VStack(spacing: 0) {
            table
            Divider()
            statusBar
        }
        .navigationTitle("SSH Tunneling")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editSheet = EditSheet(config: nil)
                } label: {
                    Label("터널 추가", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $editSheet) { sheet in
            TunnelEditView(existing: sheet.config)
                .environmentObject(vm)
        }
        .alert("터널을 삭제할까요?", isPresented: deleteAlertBinding, presenting: configToDelete) { config in
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task { await vm.delete(config) }
            }
        } message: { config in
            Text("\(config.name) (\(config.localAddress) → \(config.remoteAddress))\n이 설정과 저장된 비밀번호가 모두 삭제됩니다.")
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(vm.store.configs, selection: $selectedID) {
            TableColumn("") { c in statusBadge(c) }
                .width(28)
            TableColumn("이름") { c in Text(c.name) }
            TableColumn("SSH 호스트") { c in Text(verbatim: "\(c.sshHost):\(c.sshPort)") }
            TableColumn("포워딩") { c in
                Text("\(c.localAddress) → \(c.remoteAddress)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            TableColumn("인증") { c in Text(c.authKind.rawValue) }
                .width(80)
            TableColumn("액션") { c in actions(for: c) }
                .width(150)
        }
    }

    @ViewBuilder
    private func statusBadge(_ config: TunnelConfig) -> some View {
        let st = vm.status(for: config)
        switch st {
        case .disconnected:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .help("연결 안 됨")
        case .connecting:
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.orange)
                .help("연결 중…")
        case .connected:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .help("연결됨")
        case .error(let msg):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help(msg)
        }
    }

    @ViewBuilder
    private func actions(for config: TunnelConfig) -> some View {
        let st = vm.status(for: config)
        HStack(spacing: 8) {
            if st.isConnected || st.isConnecting {
                Button("연결 해제") {
                    Task { await vm.disconnect(config) }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                .disabled(st.isConnecting)
            } else {
                Button("연결") {
                    Task { await vm.connect(config) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Menu {
                Button {
                    editSheet = EditSheet(config: config)
                } label: {
                    Label("수정", systemImage: "pencil")
                }
                .disabled(st.isConnected || st.isConnecting)

                Divider()

                Button(role: .destructive) {
                    configToDelete = config
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if let status = vm.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            if vm.connectedCount > 0 {
                Text("연결된 터널: \(vm.connectedCount)개")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { configToDelete != nil },
            set: { if !$0 { configToDelete = nil } }
        )
    }
}
