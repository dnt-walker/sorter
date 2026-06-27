import Foundation

/// 내보내기/불러오기 파일 최상위 구조.
struct RouteExportPayload: Codable {
    let version: Int
    let routes: [RouteExportItem]
}

/// 파일에 저장되는 개별 라우트 항목. id/createdAt은 제외(불러올 때 새로 생성).
struct RouteExportItem: Codable {
    let name: String
    let destination: String
    let prefix: Int
    let kind: RouteKind
    let `interface`: String
    let gateway: String?
    let isEnabled: Bool

    init(from route: ManagedRoute) {
        name        = route.name
        destination = route.destination
        prefix      = route.prefix
        kind        = route.kind
        interface   = route.interface
        gateway     = route.gateway
        isEnabled   = route.isEnabled
    }

    func toManagedRoute() -> ManagedRoute {
        ManagedRoute(
            name:        name,
            destination: destination,
            prefix:      prefix,
            kind:        kind,
            interface:   interface,
            gateway:     gateway,
            isEnabled:   isEnabled
        )
    }
}
