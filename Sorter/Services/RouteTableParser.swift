import Foundation

/// `netstat -rn` 출력 파서. 순수 함수로 작성되어 단위 테스트가 용이하다.
enum RouteTableParser {
    /// netstat -rn 전체 출력을 받아 RouteEntry 배열로 변환한다.
    static func parse(_ output: String) -> [RouteEntry] {
        var entries: [RouteEntry] = []
        var currentFamily: RouteEntry.Family?
        var inTable = false

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("Internet6") {
                currentFamily = .ipv6
                inTable = false
                continue
            }
            if line.hasPrefix("Internet") {
                currentFamily = .ipv4
                inTable = false
                continue
            }
            if line.isEmpty {
                inTable = false
                continue
            }
            // 컬럼 헤더 행 ("Destination Gateway ...") 다음부터가 데이터.
            if line.hasPrefix("Destination") {
                inTable = true
                continue
            }
            guard inTable, let family = currentFamily else { continue }

            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard cols.count >= 4 else { continue }

            // Destination Gateway Flags [Netif] [Expire] — Netif는 보통 4번째 컬럼.
            let destination = cols[0]
            let gateway = cols[1]
            let flags = cols[2]
            let interface = cols.count >= 4 ? cols[3] : nil

            entries.append(RouteEntry(
                destination: destination,
                gateway: gateway,
                flags: flags,
                interface: interface,
                family: family
            ))
        }
        return entries
    }
}
