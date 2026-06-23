import Foundation
import Combine

/// 목록에 표시할 통합 라우트 행. 관리(managed) 라우트만 편집/삭제 가능.
struct RouteRow: Identifiable {
    let id: String
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
                result.append(RouteRow(
                    id: "managed:\(r.id.uuidString)",
                    destination: r.destination,
                    prefixText: r.prefixText,
                    interface: r.interface,
                    typeText: "사용자",
                    isManaged: true,
                    managed: r,
                    applied: appliedByRouteID[r.id],
                    isEnabled: r.isEnabled
                ))
            }
        }

        // 2) 시스템 라우트 — 잠금. 관리 라우트와 목적지가 겹치면 제외(중복 표시 방지).
        if filter != .managed {
            for e in systemRoutes where !managedKeys.contains(e.destination) {
                result.append(RouteRow(
                    id: "system:\(e.id)",
                    destination: e.destination,
                    prefixText: e.isDefault ? "—" : "",
                    interface: e.interface ?? "—",
                    typeText: "시스템",
                    isManaged: false,
                    managed: nil,
                    applied: nil,
                    isEnabled: true
                ))
            }
        }

        rows = result
    }

    // MARK: - 추가 / 수정 / 삭제

    /// 추가 또는 수정. 검증 후 route 명령 실행, 성공 시 스토어 반영.
    func save(_ route: ManagedRoute, isEditing: Bool) async -> Bool {
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
        guard let device = devices.first(where: { $0.bsdName == route.interface }) else {
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
        if !hasGateway, device.isInLocalSubnet(route.destination) == false {
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

        if isEditing {
            store.update(route)
        } else {
            store.add(route)
        }
        statusMessage = isEditing ? "라우트를 수정했습니다." : "라우트를 추가했습니다."
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
}
