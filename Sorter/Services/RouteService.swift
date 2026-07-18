import Foundation

enum RouteError: LocalizedError {
    case invalidDestination
    case invalidPrefix
    case unknownInterface
    case duplicate
    case notManaged

    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "목적지 IP 주소가 올바르지 않습니다."
        case .invalidPrefix: return "프리픽스(넷마스크) 값이 올바르지 않습니다."
        case .unknownInterface: return "선택한 네트워크 인터페이스를 찾을 수 없습니다."
        case .duplicate: return "같은 목적지/프리픽스의 라우트가 이미 존재합니다."
        case .notManaged: return "이 라우트는 앱에서 관리하는 항목이 아니므로 수정/삭제할 수 없습니다."
        }
    }
}

/// `route` 명령으로 라우트를 추가/삭제하고, `netstat`/`route get` 으로 상태를 조회한다.
struct RouteService {
    let privileged: PrivilegedRunner

    init(privileged: PrivilegedRunner = OSAScriptPrivilegedRunner()) {
        self.privileged = privileged
    }

    // MARK: - 조회 (권한 불필요)

    func listSystemRoutes() throws -> [RouteEntry] {
        let result = try CommandRunner.run("/usr/sbin/netstat", ["-rn"])
        return RouteTableParser.parse(result.stdout)
    }

    /// 라우트가 **지정한 인터페이스로** 실제 적용되어 있는지 교차 확인한다.
    /// 주의: `route get` 은 목적지가 무엇이든 항상 기본 라우트로라도 응답하므로,
    /// 단순히 응답 존재만 보면 안 되고 **해석된 interface(및 게이트웨이)가 일치**하는지 확인해야 한다.
    func isApplied(_ route: ManagedRoute) -> Bool {
        guard let result = try? CommandRunner.run("/sbin/route", ["-n", "get", route.destination]),
              result.succeeded else {
            return false
        }
        let parsed = Self.parseRouteGet(result.stdout)

        // 1) 해석된 인터페이스가 우리가 지정한 인터페이스와 같아야 한다(기본 라우트로 빠지면 불일치).
        guard let iface = parsed.interface, iface == route.interface else { return false }

        // 2) 게이트웨이 라우트라면 게이트웨이(IP)도 일치해야 한다.
        if let gw = route.gateway, !gw.isEmpty {
            guard let resolvedGW = parsed.gateway, resolvedGW == gw else { return false }
        }
        return true
    }

    /// `route -n get <dest>` 출력에서 destination/gateway/interface 추출.
    static func parseRouteGet(_ output: String) -> (destination: String?, gateway: String?, interface: String?) {
        var destination: String?
        var gateway: String?
        var interface: String?
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let range = line.range(of: ": ") {
                let key = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "destination": destination = value
                case "gateway": gateway = value
                case "interface": interface = value
                default: break
                }
            }
        }
        return (destination, gateway, interface)
    }

    // MARK: - 변경 (권한 필요)

    func add(_ route: ManagedRoute) throws {
        try privileged.runRoute(arguments: addArguments(for: route))
    }

    func delete(_ route: ManagedRoute) throws {
        try privileged.runRoute(arguments: deleteArguments(for: route))
    }

    /// 여러 라우트를 한 번의 권한 인증으로 추가한다(재반영·전체 활성화용).
    func addBatch(_ routes: [ManagedRoute]) throws {
        guard !routes.isEmpty else { return }
        try privileged.runRouteBatch(argumentLists: routes.map { addArguments(for: $0) })
    }

    /// 여러 라우트를 한 번의 권한 인증으로 삭제한다(전체 비활성화용).
    func deleteBatch(_ routes: [ManagedRoute]) throws {
        guard !routes.isEmpty else { return }
        try privileged.runRouteBatch(argumentLists: routes.map { deleteArguments(for: $0) })
    }

    // MARK: - 명령 인자 구성 (미리보기/테스트와 공유)

    func addArguments(for route: ManagedRoute) -> [String] {
        var args = ["-n", "add"]
        switch route.kind {
        case .host: args += ["-host", route.destination]
        case .net: args += ["-net", route.cidr]
        }
        if let gw = route.gateway, !gw.isEmpty {
            args += [gw]
        } else {
            args += ["-interface", route.interface]
        }
        return args
    }

    func deleteArguments(for route: ManagedRoute) -> [String] {
        var args = ["-n", "delete"]
        switch route.kind {
        case .host: args += ["-host", route.destination]
        case .net: args += ["-net", route.cidr]
        }
        return args
    }

    /// 사용자에게 보여줄 명령 미리보기 문자열.
    func previewCommand(for route: ManagedRoute) -> String {
        (["route"] + addArguments(for: route)).joined(separator: " ")
    }

    func deletePreviewCommand(for route: ManagedRoute) -> String {
        (["route"] + deleteArguments(for: route)).joined(separator: " ")
    }
}
