import Foundation
import Combine

/// 관리 라우트의 상태.
/// - created: JSON(스토어)에서 미적용 설정이고 OS 라우팅 테이블에도 없음 (기본 상태).
/// - active: OS 라우팅 테이블에 적용되어 있음.
/// - notApplied: JSON에서는 적용 설정인데 OS 라우팅 테이블에 없음 (재반영 필요).
enum RouteStatus {
    case created
    case active
    case notApplied

    var label: String {
        switch self {
        case .created:    return "생성"
        case .active:     return "활성화"
        case .notApplied: return "미적용"
        }
    }
}

/// 목록에 표시할 통합 라우트 행. 관리(managed) 라우트만 편집/삭제 가능.
struct RouteRow: Identifiable {
    let id: String
    let name: String
    let destination: String
    let prefixText: String
    let interface: String
    let typeText: String
    let isManaged: Bool
    /// managed인 경우 원본.
    let managed: ManagedRoute?
    /// managed인 경우 라우팅 테이블 적용 여부.
    let applied: Bool?
    /// managed 라우트의 활성 여부 (시스템 라우트는 항상 true).
    let isEnabled: Bool
    /// managed 라우트의 상태 (시스템 라우트는 nil).
    let status: RouteStatus?
}

enum RouteFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case managed = "사용자 라우트"
    case system = "시스템 라우트"
    var id: String { rawValue }
}

@MainActor
final class RoutesViewModel: ObservableObject {
    @Published var rows: [RouteRow] = []
    @Published var filter: RouteFilter = .all { didSet { rebuildRows() } }
    @Published var selectedRowID: RouteRow.ID?
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let store: ManagedRouteStore
    let routeService: RouteService
    let deviceService = NetworkDeviceService()

    @Published var devices: [NetworkDevice] = []

    private var systemRoutes: [RouteEntry] = []
    private var appliedByRouteID: [UUID: Bool] = [:]

    init(store: ManagedRouteStore, routeService: RouteService = RouteService()) {
        self.store = store
        self.routeService = routeService
    }

    var selectedRow: RouteRow? {
        guard let id = selectedRowID else { return nil }
        return rows.first { $0.id == id }
    }

    // MARK: - 새로고침

    func refresh() {
        isLoading = true
        errorMessage = nil
        let routeService = self.routeService
        let deviceService = self.deviceService
        let managed = store.routes

        Task {
            let loaded = await Task.detached { () -> (system: [RouteEntry], devices: [NetworkDevice], applied: [UUID: Bool]) in
                let system = (try? routeService.listSystemRoutes()) ?? []
                let devices = deviceService.listDevices()
                var applied: [UUID: Bool] = [:]
                for r in managed { applied[r.id] = routeService.isApplied(r) }
                return (system, devices, applied)
            }.value

            self.systemRoutes = loaded.system
            self.devices = loaded.devices
            self.appliedByRouteID = loaded.applied
            self.isLoading = false
            self.rebuildRows()
        }
    }

    private func rebuildRows() {
        var result: [RouteRow] = []

        // 1) 사용자(관리) 라우트 — 편집 가능. 상단 정렬.
        let managedKeys = Set(store.routes.map { $0.destination })
        if filter != .system {
            for r in store.routes {
                let applied = appliedByRouteID[r.id]
                result.append(RouteRow(
                    id: "managed:\(r.id.uuidString)",
                    name: r.name,
                    destination: r.destination,
                    prefixText: r.prefixText,
                    interface: r.interface,
                    typeText: "사용자",
                    isManaged: true,
                    managed: r,
                    applied: applied,
                    isEnabled: r.isEnabled,
                    status: applied.map { $0 ? .active : (r.isEnabled ? .notApplied : .created) }
                ))
            }
        }

        // 2) 시스템 라우트 — 잠금. 관리 라우트와 목적지가 겹치면 제외(중복 표시 방지).
        if filter != .managed {
            for e in systemRoutes where !managedKeys.contains(e.destination) {
                result.append(RouteRow(
                    id: "system:\(e.id)",
                    name: "—",
                    destination: e.destination,
                    prefixText: e.isDefault ? "—" : "",
                    interface: e.interface ?? "—",
                    typeText: "시스템",
                    isManaged: false,
                    managed: nil,
                    applied: nil,
                    isEnabled: true,
                    status: nil
                ))
            }
        }

        rows = result
    }

    // MARK: - 추가 / 수정 / 삭제

    /// 추가 또는 수정.
    /// - apply: true이면 route 명령도 실행(라우팅 테이블 반영), false이면 스토어에만 저장.
    func save(_ route: ManagedRoute, isEditing: Bool, apply: Bool = true) async -> Bool {
        errorMessage = nil
        statusMessage = nil

        // 검증
        guard IPValidator.isValidIP(route.destination) else {
            errorMessage = RouteError.invalidDestination.localizedDescription
            return false
        }
        guard IPValidator.isValidPrefix(route.prefix, for: route.destination) else {
            errorMessage = RouteError.invalidPrefix.localizedDescription
            return false
        }
        let device = devices.first(where: { $0.bsdName == route.interface })
        // apply 시에는 인터페이스가 실제 존재해야 한다. 저장만 할 때는 허용한다.
        if device == nil && apply {
            errorMessage = RouteError.unknownInterface.localizedDescription
            return false
        }
        let hasGateway = !(route.gateway ?? "").isEmpty
        if hasGateway, !IPValidator.isValidIP(route.gateway!) {
            errorMessage = "게이트웨이 주소가 올바르지 않습니다."
            return false
        }
        // A안: 게이트웨이 없이(=interface 라우트) 비로컬 목적지를 추가하면 패킷이 로컬 링크로만
        // 나가 도달하지 못한다. 비로컬이면 게이트웨이를 요구한다.
        // 인터페이스가 없어 로컬 서브넷 판단이 불가능한 경우에는 이 검증을 건너뛴다.
        if let device, !hasGateway, device.isInLocalSubnet(route.destination) == false {
            let suggestion = device.gateway.map { " (예: \($0))" } ?? ""
            errorMessage = "목적지가 \(route.interface)의 로컬 서브넷 밖입니다. next-hop 게이트웨이를 지정하세요\(suggestion)."
            return false
        }
        if store.hasDuplicate(of: route) {
            errorMessage = RouteError.duplicate.localizedDescription
            return false
        }
        // 수정 대상은 반드시 관리 라우트여야 한다(보호 가드).
        if isEditing && !store.contains(id: route.id) {
            errorMessage = RouteError.notManaged.localizedDescription
            return false
        }

        // 상태 규칙: 적용하면 '활성화' 설정, 새 라우트를 저장만 하면 '생성' 상태(미적용 설정).
        var route = route
        if apply {
            route.isEnabled = true
        } else if !isEditing {
            route.isEnabled = false
        }

        if apply {
            let routeService = self.routeService
            do {
                if isEditing, let old = store.route(withID: route.id) {
                    // 수정: 기존 삭제 후 추가 (CLAUDE.md 정책).
                    try await Task.detached { try routeService.delete(old) }.value
                }
                try await Task.detached { try routeService.add(route) }.value
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // 사용자 취소는 변경 없음으로 처리.
                return false
            }
        }

        if isEditing {
            store.update(route)
        } else {
            store.add(route)
        }
        if apply {
            statusMessage = isEditing ? "라우트를 수정·적용했습니다." : "라우트를 추가·적용했습니다."
        } else {
            statusMessage = isEditing ? "라우트를 저장했습니다." : "라우트를 저장했습니다. (생성 상태 — 활성화 필요)"
        }
        refresh()
        return true
    }

    /// 삭제. 관리 라우트만 허용(보호 가드).
    func delete(_ route: ManagedRoute) async {
        errorMessage = nil
        statusMessage = nil
        guard store.contains(id: route.id) else {
            errorMessage = RouteError.notManaged.localizedDescription
            return
        }
        let routeService = self.routeService
        do {
            try await Task.detached { try routeService.delete(route) }.value
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        store.remove(id: route.id)
        statusMessage = "라우트를 삭제했습니다."
        refresh()
    }

    // MARK: - 도메인 IP 일괄 추가

    /// 도메인에서 해석된 IP들을 호스트 라우트로 일괄 추가한다.
    /// 검증 규칙은 save()와 동일하며, 중복(목적지+프리픽스)은 건너뛴다.
    /// apply 시 addBatch로 권한 인증을 한 번만 받아 적용한다.
    func addResolvedRoutes(_ routes: [ManagedRoute], apply: Bool) async -> Bool {
        errorMessage = nil
        statusMessage = nil

        guard !routes.isEmpty else {
            errorMessage = "추가할 IP가 없습니다."
            return false
        }

        let interface = routes[0].interface
        let device = devices.first { $0.bsdName == interface }
        if device == nil && apply {
            errorMessage = RouteError.unknownInterface.localizedDescription
            return false
        }
        for route in routes {
            guard IPValidator.isValidIP(route.destination) else {
                errorMessage = RouteError.invalidDestination.localizedDescription
                return false
            }
            let hasGateway = !(route.gateway ?? "").isEmpty
            if hasGateway, !IPValidator.isValidIP(route.gateway!) {
                errorMessage = "게이트웨이 주소가 올바르지 않습니다."
                return false
            }
            // A안: 비로컬 목적지는 게이트웨이 필수 (interface 라우트로는 도달 불가).
            if let device, !hasGateway, device.isInLocalSubnet(route.destination) == false {
                errorMessage = "목적지 \(route.destination)이(가) \(interface)의 로컬 서브넷 밖입니다. next-hop 게이트웨이를 지정하세요."
                return false
            }
        }

        var newRoutes: [ManagedRoute] = []
        var skipped = 0
        for var route in routes {
            if store.hasDuplicate(of: route) {
                skipped += 1
                continue
            }
            route.isEnabled = apply
            newRoutes.append(route)
        }
        guard !newRoutes.isEmpty else {
            statusMessage = "모든 IP(\(skipped)개)가 이미 등록되어 있습니다."
            return true
        }

        if apply {
            let routeService = self.routeService
            let batch = newRoutes
            do {
                try await Task.detached { try routeService.addBatch(batch) }.value
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return false
            }
        }

        for route in newRoutes { store.add(route) }

        let domainName = routes[0].name
        var message = apply
            ? "\(domainName): IP 라우트 \(newRoutes.count)개를 추가·적용했습니다."
            : "\(domainName): IP 라우트 \(newRoutes.count)개를 저장했습니다. (생성 상태 — 활성화 필요)"
        if skipped > 0 { message += " (중복 \(skipped)개 건너뜀)" }
        statusMessage = message
        refresh()
        return true
    }

    // MARK: - 활성화 / 비활성화

    /// 라우트를 비활성화하면 라우팅 테이블에서 제거하고(삭제는 아님), 활성화하면 다시 등록한다.
    func toggleEnabled(_ route: ManagedRoute) async {
        errorMessage = nil
        statusMessage = nil
        guard store.contains(id: route.id) else { return }

        var updated = route
        updated.isEnabled = !route.isEnabled

        let routeService = self.routeService
        if !updated.isEnabled {
            // 비활성화: 라우팅 테이블에서 제거 (이미 없으면 무시)
            try? await Task.detached { try routeService.delete(route) }.value
            statusMessage = "라우트를 비활성화했습니다."
        } else {
            // 활성화: 라우팅 테이블에 재등록
            do {
                try await Task.detached { try routeService.add(updated) }.value
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
            statusMessage = "라우트를 활성화했습니다."
        }

        store.update(updated)
        refresh()
    }

    // MARK: - 내보내기 / 불러오기

    /// 관리 라우트 전체를 JSON 파일로 내보낸다.
    func exportRoutes(to url: URL) throws {
        let payload = RouteExportPayload(version: 1, routes: store.routes.map(RouteExportItem.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    /// JSON 파일에서 라우트를 읽어 중복(목적지+프리픽스+인터페이스)이 아닌 항목만 스토어에 추가한다.
    /// 불러온 라우트는 스토어에만 저장되며 라우팅 테이블에는 즉시 반영하지 않는다.
    func importRoutes(from url: URL) throws -> (added: Int, skipped: Int) {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(RouteExportPayload.self, from: data)

        var added = 0
        var skipped = 0
        for item in payload.routes {
            let isDuplicate = store.routes.contains {
                $0.destination == item.destination &&
                $0.prefix      == item.prefix &&
                $0.interface   == item.interface
            }
            if isDuplicate {
                skipped += 1
            } else {
                store.add(item.toManagedRoute())
                added += 1
            }
        }
        if added > 0 { refresh() }
        return (added, skipped)
    }

    // MARK: - 재반영 (저장된 사용자 라우트 중 미적용 항목을 다시 등록)

    /// 적용되지 않은(라우팅 테이블에 없는) 활성 관리 라우트 개수.
    var missingCount: Int {
        store.routes.filter { $0.isEnabled && appliedByRouteID[$0.id] == false }.count
    }

    /// 저장된 사용자 라우트 중 라우팅 테이블에 없는 항목만 다시 등록한다.
    /// 인터페이스가 변경/제거되어 존재하지 않는 라우트는 건너뛰고 보고한다.
    /// 여러 항목이라도 권한 인증은 한 번만 받는다(배치 실행).
    func reapplyMissing() async {
        errorMessage = nil
        statusMessage = nil

        // 최신 적용 상태를 보장하기 위해 먼저 동기 조회.
        let routeService = self.routeService
        let managed = store.routes
        let currentApplied = await Task.detached { () -> [UUID: Bool] in
            var applied: [UUID: Bool] = [:]
            for r in managed { applied[r.id] = routeService.isApplied(r) }
            return applied
        }.value
        self.appliedByRouteID = currentApplied

        let missing = store.routes.filter { $0.isEnabled && currentApplied[$0.id] == false }
        guard !missing.isEmpty else {
            statusMessage = "모든 사용자 라우트가 이미 적용되어 있습니다."
            rebuildRows()
            return
        }

        // 현재 존재하는 인터페이스만 적용 가능. 사라진 인터페이스는 건너뛴다.
        let availableInterfaces = Set(devices.map { $0.bsdName })
        let applicable = missing.filter { availableInterfaces.contains($0.interface) }
        let unresolved = missing.filter { !availableInterfaces.contains($0.interface) }

        if applicable.isEmpty {
            errorMessage = "재적용할 수 있는 라우트가 없습니다. 인터페이스가 존재하지 않는 항목: " +
                unresolved.map { "\($0.cidr)→\($0.interface)" }.joined(separator: ", ")
            rebuildRows()
            return
        }

        do {
            try await Task.detached { try routeService.addBatch(applicable) }.value
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        var message = "\(applicable.count)개 라우트를 재적용했습니다."
        if !unresolved.isEmpty {
            message += " (인터페이스 없음으로 건너뜀: " +
                unresolved.map { "\($0.cidr)→\($0.interface)" }.joined(separator: ", ") + ")"
        }
        statusMessage = message
        refresh()
    }

    // MARK: - 전체 활성화 / 전체 비활성화

    /// 모든 관리 라우트를 라우팅 테이블에 등록하고 '활성화' 설정으로 만든다.
    /// 이미 적용된 항목은 건너뛰고, 인터페이스가 없는 항목은 보고한다. 권한 인증은 한 번만 받는다.
    func enableAll() async {
        errorMessage = nil
        statusMessage = nil

        let managed = store.routes
        guard !managed.isEmpty else {
            statusMessage = "관리 라우트가 없습니다."
            return
        }

        let routeService = self.routeService
        let currentApplied = await Task.detached { () -> [UUID: Bool] in
            var applied: [UUID: Bool] = [:]
            for r in managed { applied[r.id] = routeService.isApplied(r) }
            return applied
        }.value
        self.appliedByRouteID = currentApplied

        let missing = managed.filter { currentApplied[$0.id] != true }
        let availableInterfaces = Set(devices.map { $0.bsdName })
        let applicable = missing.filter { availableInterfaces.contains($0.interface) }
        let unresolved = missing.filter { !availableInterfaces.contains($0.interface) }

        if !applicable.isEmpty {
            do {
                try await Task.detached { try routeService.addBatch(applicable) }.value
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }

        // 적용된(또는 이미 적용돼 있던) 항목만 '활성화' 설정으로 저장한다.
        let unresolvedIDs = Set(unresolved.map { $0.id })
        for route in managed where !route.isEnabled && !unresolvedIDs.contains(route.id) {
            var updated = route
            updated.isEnabled = true
            store.update(updated)
        }

        var message = applicable.isEmpty
            ? "모든 라우트가 이미 적용되어 있습니다."
            : "\(applicable.count)개 라우트를 활성화했습니다."
        if !unresolved.isEmpty {
            message += " (인터페이스 없음으로 건너뜀: " +
                unresolved.map { "\($0.cidr)→\($0.interface)" }.joined(separator: ", ") + ")"
        }
        statusMessage = message
        refresh()
    }

    /// 모든 관리 라우트를 라우팅 테이블에서 제거하고(삭제 아님) '비활성화' 설정으로 만든다.
    /// 권한 인증은 한 번만 받는다.
    func disableAll() async {
        errorMessage = nil
        statusMessage = nil

        let managed = store.routes
        guard !managed.isEmpty else {
            statusMessage = "관리 라우트가 없습니다."
            return
        }

        let routeService = self.routeService
        let currentApplied = await Task.detached { () -> [UUID: Bool] in
            var applied: [UUID: Bool] = [:]
            for r in managed { applied[r.id] = routeService.isApplied(r) }
            return applied
        }.value
        self.appliedByRouteID = currentApplied

        let appliedRoutes = managed.filter { currentApplied[$0.id] == true }
        if !appliedRoutes.isEmpty {
            do {
                try await Task.detached { try routeService.deleteBatch(appliedRoutes) }.value
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }

        for route in managed where route.isEnabled {
            var updated = route
            updated.isEnabled = false
            store.update(updated)
        }

        statusMessage = appliedRoutes.isEmpty
            ? "라우팅 테이블에 적용된 라우트가 없어 설정만 비활성화했습니다."
            : "\(appliedRoutes.count)개 라우트를 비활성화했습니다."
        refresh()
    }
}
