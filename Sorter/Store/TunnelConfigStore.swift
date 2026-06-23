import Foundation
import Combine

@MainActor
final class TunnelConfigStore: ObservableObject {
    @Published private(set) var configs: [TunnelConfig] = []

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Sorter", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tunnel-configs.json")
        load()
    }

    // MARK: - 조회

    func contains(id: UUID) -> Bool {
        configs.contains { $0.id == id }
    }

    func config(withID id: UUID) -> TunnelConfig? {
        configs.first { $0.id == id }
    }

    func hasDuplicate(of config: TunnelConfig) -> Bool {
        configs.contains { $0.id != config.id
            && $0.sshHost == config.sshHost
            && $0.localPort == config.localPort }
    }

    // MARK: - 변경

    func add(_ config: TunnelConfig) {
        configs.append(config)
        save()
    }

    func update(_ config: TunnelConfig) {
        guard let idx = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[idx] = config
        save()
    }

    func remove(id: UUID) {
        configs.removeAll { $0.id == id }
        save()
    }

    // MARK: - 영속화

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder.iso.decode([TunnelConfig].self, from: data) {
            configs = decoded.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(configs) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
