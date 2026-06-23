import Foundation

/// `netstat -rn` 으로 읽어들인 시스템 라우팅 테이블의 한 행.
/// 표시/교차검증 용도이며 앱이 관리하는 라우트(ManagedRoute)와는 별개다.
struct RouteEntry: Identifiable, Hashable {
    var id: String { "\(family.rawValue):\(destination)>\(interface ?? "-")>\(gateway ?? "-")" }

    enum Family: String { case ipv4 = "v4", ipv6 = "v6" }

    /// netstat에 표시된 그대로의 목적지 (예: "default", "192.168.0/24", "12.12.3.4")
    let destination: String
    let gateway: String?
    let flags: String?
    let interface: String?
    let family: Family

    /// 기본 라우트 여부 (절대 수정/삭제 대상에서 제외)
    var isDefault: Bool { destination == "default" || destination == "::/0" || destination == "0.0.0.0" }
}
