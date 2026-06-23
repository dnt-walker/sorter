import Foundation

/// 시스템에 등록된 네트워크 인터페이스(디바이스) 한 개.
struct NetworkDevice: Identifiable, Hashable {
    var id: String { bsdName }

    /// BSD 이름 (예: en0)
    let bsdName: String
    /// 사용자 표시 이름 (예: Wi-Fi). 알 수 없으면 bsdName과 동일.
    var displayName: String
    var ipv4: String?
    /// IPv4 서브넷 프리픽스 길이 (예: 24). 넷마스크에서 계산.
    var ipv4Prefix: Int?
    var ipv6: String?
    var mac: String?
    /// 이 인터페이스의 default 게이트웨이(라우터) IP. 비로컬 목적지 라우팅의 next-hop 추천에 사용.
    var gateway: String?
    /// IFF_UP && IFF_RUNNING
    var isUp: Bool
    var mtu: Int?

    var statusText: String { isUp ? "up" : "down" }

    /// 라우팅 대상이 될 수 있는 실제 인터페이스인지(loopback 등 제외하지 않고 표시는 하되 참고용).
    var isLoopback: Bool { bsdName.hasPrefix("lo") }

    /// 목적지가 이 인터페이스의 로컬 IPv4 서브넷에 속하는지.
    /// - nil: 판단 불가(인터페이스에 IPv4가 없거나 목적지가 IPv4가 아님).
    /// - true: 로컬 링크에 직접 존재 → interface 라우트로 충분.
    /// - false: 비로컬 → 게이트웨이(next-hop)가 필요.
    func isInLocalSubnet(_ destination: String) -> Bool? {
        guard let myIP = ipv4, let prefix = ipv4Prefix else { return nil }
        return SubnetMath.sameSubnetIPv4(myIP, destination, prefix: prefix)
    }
}
