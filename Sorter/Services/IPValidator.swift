import Foundation

/// IP 주소/프리픽스 입력 검증 유틸. inet_pton 기반.
enum IPValidator {
    static func isValidIPv4(_ s: String) -> Bool {
        var addr = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &addr) } == 1
    }

    static func isValidIPv6(_ s: String) -> Bool {
        var addr = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &addr) } == 1
    }

    static func isValidIP(_ s: String) -> Bool {
        isValidIPv4(s) || isValidIPv6(s)
    }

    /// 해당 주소에 대한 최대 프리픽스 길이 (v4=32, v6=128).
    static func maxPrefix(for ip: String) -> Int {
        isValidIPv6(ip) ? 128 : 32
    }

    static func isValidPrefix(_ prefix: Int, for ip: String) -> Bool {
        prefix >= 0 && prefix <= maxPrefix(for: ip)
    }
}

/// IPv4 서브넷 계산.
enum SubnetMath {
    /// 점-십진 IPv4 문자열을 호스트 바이트 순서 UInt32로 변환.
    static func ipv4ToUInt32(_ s: String) -> UInt32? {
        var addr = in_addr()
        guard s.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    /// 두 IPv4 주소가 같은 서브넷(prefix)에 속하는지.
    /// 둘 중 하나라도 IPv4가 아니면 nil(판단 불가).
    static func sameSubnetIPv4(_ a: String, _ b: String, prefix: Int) -> Bool? {
        guard prefix >= 0, prefix <= 32,
              let ua = ipv4ToUInt32(a),
              let ub = ipv4ToUInt32(b) else { return nil }
        // prefix 비트만큼 상위 비트 마스크. (Swift 스마트 시프트로 0/32 경계도 안전)
        let mask: UInt32 = ~(UInt32.max >> UInt32(prefix))
        return (ua & mask) == (ub & mask)
    }
}
