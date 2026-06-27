import Foundation

/// 라우트 유형: 단일 호스트 또는 네트워크(CIDR).
enum RouteKind: String, Codable, CaseIterable, Identifiable {
    case host
    case net

    var id: String { rawValue }
    var label: String { self == .host ? "호스트" : "네트워크" }
}

/// 앱(사용자)이 추가한 라우트. **이 스토어에 존재하는 라우트만 수정/삭제가 허용된다.**
/// 기본/시스템 라우트는 여기에 들어오지 않으므로 보호된다.
struct ManagedRoute: Identifiable, Codable, Hashable {
    let id: UUID
    /// 사용자 지정 이름. 기본값 "-".
    var name: String
    var destination: String
    /// 프리픽스 길이. host인 경우 IPv4=32 / IPv6=128.
    var prefix: Int
    var kind: RouteKind
    /// 대상 BSD 인터페이스 이름 (예: en0)
    var interface: String
    /// 지정 시 게이트웨이 라우트, 비어 있으면 interface 라우트.
    var gateway: String?
    var createdAt: Date
    /// false이면 라우팅 테이블에서 제거된 상태로 유지한다 (삭제는 아님).
    var isEnabled: Bool

    init(id: UUID = UUID(),
         name: String = "-",
         destination: String,
         prefix: Int,
         kind: RouteKind,
         interface: String,
         gateway: String? = nil,
         createdAt: Date = Date(),
         isEnabled: Bool = true) {
        self.id = id
        self.name = name.isEmpty ? "-" : name
        self.destination = destination
        self.prefix = prefix
        self.kind = kind
        self.interface = interface
        self.gateway = (gateway?.isEmpty == true) ? nil : gateway
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }

    // 기존 JSON(name/isEnabled 필드 없음)을 읽을 때 기본값을 적용한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,     forKey: .id)
        name        = try c.decodeIfPresent(String.self, forKey: .name) ?? "-"
        destination = try c.decode(String.self,   forKey: .destination)
        prefix      = try c.decode(Int.self,      forKey: .prefix)
        kind        = try c.decode(RouteKind.self, forKey: .kind)
        interface   = try c.decode(String.self,   forKey: .interface)
        gateway     = try c.decodeIfPresent(String.self, forKey: .gateway)
        createdAt   = try c.decode(Date.self,     forKey: .createdAt)
        isEnabled   = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    var isIPv6: Bool { destination.contains(":") }

    /// CIDR 표기 (예: 12.12.3.0/24)
    var cidr: String { "\(destination)/\(prefix)" }

    /// 목록/세부정보에 표시할 프리픽스 텍스트.
    var prefixText: String {
        kind == .host ? "/\(prefix) (호스트)" : "/\(prefix)"
    }

    /// 중복 판정 키 (목적지 + 프리픽스).
    var dedupeKey: String { "\(destination)/\(prefix)" }
}
