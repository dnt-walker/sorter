import Foundation
import Combine
import Citadel

enum TunnelStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "연결 안 됨"
        case .connecting: return "연결 중…"
        case .connected: return "연결됨"
        case .error(let msg): return "오류: \(msg)"
        }
    }

    var isConnected: Bool { self == .connected }
    var isConnecting: Bool { self == .connecting }
}

@MainActor
final class TunnelsViewModel: ObservableObject {
    @Published var statuses: [UUID: TunnelStatus] = [:]
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    let store: TunnelConfigStore
    private var sshClients: [UUID: SSHClient] = [:]
    private var listeners: [UUID: LocalPortListener] = [:]

    init(store: TunnelConfigStore) {
        self.store = store
    }

    // MARK: - 상태 조회

    func status(for config: TunnelConfig) -> TunnelStatus {
        statuses[config.id] ?? .disconnected
    }

    var connectedCount: Int {
        statuses.values.filter { $0.isConnected }.count
    }

    // MARK: - 연결

    func connect(_ config: TunnelConfig) async {
        errorMessage = nil
        statusMessage = nil
        guard statuses[config.id] != .connected, statuses[config.id] != .connecting else { return }

        statuses[config.id] = .connecting

        do {
            let password = config.authKind == .password
                ? (try? KeychainHelper.load(forKey: config.keychainKey)) ?? nil
                : nil

            let client = try await SSHTunnelService.connect(config: config, password: password)

            // SSH 세션이 외부에서 끊어질 때 UI 상태를 업데이트한다.
            let configID = config.id
            let configName = config.name
            client.onDisconnect { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.statuses[configID] = .error("연결이 끊어졌습니다.")
                    self.errorMessage = "\(configName) 연결이 끊어졌습니다."
                    self.listeners.removeValue(forKey: configID)
                    self.sshClients.removeValue(forKey: configID)
                }
            }

            let listener = LocalPortListener()
            try await listener.start(
                localPort: config.localPort,
                sshClient: client,
                remoteHost: config.remoteHost,
                remotePort: config.remotePort
            )

            sshClients[config.id] = client
            listeners[config.id] = listener
            statuses[config.id] = .connected
            statusMessage = "\(config.name) 연결됨 (\(config.localAddress) → \(config.remoteAddress))"
        } catch {
            statuses[config.id] = .error(error.localizedDescription)
            errorMessage = "\(config.name) 연결 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - 연결 해제

    func disconnect(_ config: TunnelConfig) async {
        errorMessage = nil
        statusMessage = nil

        await listeners[config.id]?.stop()
        try? await sshClients[config.id]?.close()

        listeners.removeValue(forKey: config.id)
        sshClients.removeValue(forKey: config.id)
        statuses[config.id] = .disconnected
        statusMessage = "\(config.name) 연결 해제됨"
    }

    func disconnectAll() async {
        for config in store.configs {
            if statuses[config.id] == .connected || statuses[config.id] == .connecting {
                await disconnect(config)
            }
        }
    }

    // MARK: - 저장

    func save(_ config: TunnelConfig, password: String?, isEditing: Bool) -> Bool {
        errorMessage = nil

        if config.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "이름을 입력하세요."
            return false
        }
        if config.sshHost.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "SSH 호스트를 입력하세요."
            return false
        }
        if config.username.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "사용자명을 입력하세요."
            return false
        }
        if config.authKind == .publicKey && (config.publicKeyPath ?? "").isEmpty {
            errorMessage = "공개키 파일을 선택하세요."
            return false
        }
        if store.hasDuplicate(of: config) {
            errorMessage = "같은 SSH 호스트와 로컬 포트 조합이 이미 존재합니다."
            return false
        }

        if let pw = password, !pw.isEmpty {
            try? KeychainHelper.save(pw, forKey: config.keychainKey)
        }

        if isEditing {
            store.update(config)
        } else {
            store.add(config)
        }
        return true
    }

    func delete(_ config: TunnelConfig) async {
        if statuses[config.id] == .connected || statuses[config.id] == .connecting {
            await disconnect(config)
        }
        KeychainHelper.delete(forKey: config.keychainKey)
        store.remove(id: config.id)
    }
}
