import Foundation
import Combine

/// 앱(사용자)이 추가한 라우트를 영속화하는 스토어.
/// **수정/삭제 허용 여부의 단일 기준(source of truth)** 이다.
/// Application Support/Sorter/managed-routes.json 에 저장된다.
@MainActor
final class ManagedRouteStore: ObservableObject {
    @Published private(set) var routes: [ManagedRoute] = []

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Sorter", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("managed-routes.json")
        load()
    }

    // MARK: - 조회

    func contains(id: UUID) -> Bool {
        routes.contains { $0.id == id }
    }

    func route(withID id: UUID) -> ManagedRoute? {
        routes.first { $0.id == id }
    }

    /// 같은 목적지/프리픽스가 이미 있는지 (자신 제외).
    func hasDuplicate(of route: ManagedRoute) -> Bool {
        routes.contains { $0.id != route.id && $0.dedupeKey == route.dedupeKey }
    }

    // MARK: - 변경

    func add(_ route: ManagedRoute) {
        routes.append(route)
        save()
    }

    func update(_ route: ManagedRoute) {
        guard let idx = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[idx] = route
        save()
    }

    func remove(id: UUID) {
        routes.removeAll { $0.id == id }
        save()
    }

    // MARK: - 영속화

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder.iso.decode([ManagedRoute].self, from: data) {
            routes = decoded.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(routes) else { return }
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
