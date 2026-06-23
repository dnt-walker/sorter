import Foundation
import Darwin

/// 네트워크 디바이스를 열거하고 세부 정보를 채운다.
/// 1차로 getifaddrs(API) 를 사용하고, 표시 이름은 networksetup, MTU는 ifconfig로 보강한다.
struct NetworkDeviceService {

    func listDevices() -> [NetworkDevice] {
        var devices = enumerateInterfaces()

        let portNames = hardwarePortNames()
        let gateways = interfaceGateways()
        for i in devices.indices {
            if let displayName = portNames[devices[i].bsdName] {
                devices[i].displayName = displayName
            }
            devices[i].gateway = gateways[devices[i].bsdName]
            devices[i].mtu = mtu(for: devices[i].bsdName)
        }

        devices.sort { lhs, rhs in
            // loopback은 뒤로, 그 외 BSD 이름 오름차순.
            if lhs.isLoopback != rhs.isLoopback { return !lhs.isLoopback }
            return lhs.bsdName < rhs.bsdName
        }
        return devices
    }

    // MARK: - getifaddrs 열거

    private func enumerateInterfaces() -> [NetworkDevice] {
        var byName: [String: NetworkDevice] = [:]

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0

            var device = byName[name] ?? NetworkDevice(
                bsdName: name,
                displayName: name,
                ipv4: nil, ipv6: nil, mac: nil,
                isUp: false, mtu: nil
            )
            device.isUp = device.isUp || isUp

            if let addr = current.pointee.ifa_addr {
                switch Int32(addr.pointee.sa_family) {
                case AF_INET:
                    if let ip = Self.ipString(addr, family: AF_INET) { device.ipv4 = ip }
                    if let netmask = current.pointee.ifa_netmask {
                        device.ipv4Prefix = Self.prefixFromMask(netmask)
                    }
                case AF_INET6:
                    if device.ipv6 == nil, let ip = Self.ipString(addr, family: AF_INET6) { device.ipv6 = ip }
                case AF_LINK:
                    if let mac = Self.macString(addr) { device.mac = mac }
                default:
                    break
                }
            }

            byName[name] = device
            _ = current
        }
        return Array(byName.values)
    }

    private static func ipString(_ sa: UnsafeMutablePointer<sockaddr>, family: Int32) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let saLen = family == AF_INET
            ? socklen_t(MemoryLayout<sockaddr_in>.size)
            : socklen_t(MemoryLayout<sockaddr_in6>.size)
        let result = getnameinfo(sa, saLen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        var s = String(cString: host)
        // IPv6 링크로컬의 scope id("fe80::1%en0") 제거.
        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
        return s
    }

    /// IPv4 넷마스크 sockaddr → 프리픽스 길이.
    private static func prefixFromMask(_ sa: UnsafeMutablePointer<sockaddr>) -> Int? {
        guard Int32(sa.pointee.sa_family) == AF_INET else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            let mask = UInt32(bigEndian: sin.pointee.sin_addr.s_addr)
            return mask.nonzeroBitCount
        }
    }

    private static func macString(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dlPtr -> String? in
            let alen = Int(dlPtr.pointee.sdl_alen)
            guard alen == 6 else { return nil }
            let nlen = Int(dlPtr.pointee.sdl_nlen)
            // sdl_data 오프셋은 8바이트, MAC은 그 뒤 nlen(인터페이스명) 다음에 위치.
            let base = UnsafeRawPointer(dlPtr).advanced(by: 8)
            let macPtr = base.advanced(by: nlen).assumingMemoryBound(to: UInt8.self)
            let bytes = (0..<6).map { macPtr[$0] }
            return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
    }

    // MARK: - 보강 정보

    /// networksetup -listallhardwareports → [bsdName: 표시이름]
    private func hardwarePortNames() -> [String: String] {
        guard let result = try? CommandRunner.run("/usr/sbin/networksetup", ["-listallhardwareports"]),
              result.succeeded else { return [:] }

        var map: [String: String] = [:]
        var currentPort: String?
        for rawLine in result.stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                currentPort = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:") {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if let port = currentPort, !device.isEmpty { map[device] = port }
            }
        }
        return map
    }

    /// 각 인터페이스의 default 게이트웨이(라우터) IP를 [bsdName: gatewayIP]로.
    /// `netstat -rnf inet` 의 "default <ip> ... <netif>" 행에서 추출한다(link# 게이트웨이는 제외).
    private func interfaceGateways() -> [String: String] {
        guard let result = try? CommandRunner.run("/usr/sbin/netstat", ["-rnf", "inet"]),
              result.succeeded else { return [:] }

        var map: [String: String] = [:]
        for rawLine in result.stdout.components(separatedBy: .newlines) {
            let cols = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard cols.count >= 4, cols[0] == "default" else { continue }
            let gateway = cols[1]
            let netif = cols[3]
            // 게이트웨이가 IPv4 주소인 경우만(link#28 같은 인터페이스 게이트웨이 제외).
            guard IPValidator.isValidIPv4(gateway) else { continue }
            // 같은 인터페이스에 default가 여러 개면 첫 번째(우선순위 높은) 것을 유지.
            if map[netif] == nil { map[netif] = gateway }
        }
        return map
    }

    /// ifconfig <name> 출력에서 "mtu 1500" 파싱.
    private func mtu(for name: String) -> Int? {
        guard let result = try? CommandRunner.run("/sbin/ifconfig", [name]), result.succeeded else { return nil }
        guard let range = result.stdout.range(of: "mtu ") else { return nil }
        let digits = result.stdout[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}
