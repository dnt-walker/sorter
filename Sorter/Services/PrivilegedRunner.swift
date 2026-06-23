import Foundation

/// 권한 상승이 필요한 명령(route add/delete)을 실행하는 추상화.
/// MVP는 osascript(do shell script ... with administrator privileges)를 사용하고,
/// 배포 시 XPC 권한 헬퍼 구현으로 교체할 수 있다. (CLAUDE.md 권한 섹션 참조)
protocol PrivilegedRunner {
    /// `/sbin/route` 에 전달할 인자 배열. 호출 측에서 검증된 값만 넘긴다.
    func runRoute(arguments: [String]) throws

    /// 여러 route 명령을 한 번의 권한 인증으로 실행한다(재반영 등 일괄 처리용).
    func runRouteBatch(argumentLists: [[String]]) throws
}

extension PrivilegedRunner {
    func runRoute(arguments: [String]) throws {
        try runRouteBatch(argumentLists: [arguments])
    }
}

enum PrivilegedError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "사용자가 인증을 취소했습니다. (변경 없음)"
        case .failed(let m): return m
        }
    }
}

/// osascript 기반 권한 실행기 (MVP).
struct OSAScriptPrivilegedRunner: PrivilegedRunner {
    let routePath: String

    init(routePath: String = "/sbin/route") {
        self.routePath = routePath
    }

    func runRouteBatch(argumentLists: [[String]]) throws {
        guard !argumentLists.isEmpty else { return }

        // 여러 route 명령을 ";" 로 이어 한 번의 권한 인증으로 실행한다.
        // 인자는 호출 전에 화이트리스트 검증되지만 추가로 따옴표 처리한다.
        let command = argumentLists
            .map { args in ([routePath] + args).map { Self.shellQuote($0) }.joined(separator: " ") }
            .joined(separator: "; ")

        // do shell script 내부의 문자열 리터럴용 이스케이프.
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let result: CommandResult
        do {
            result = try CommandRunner.run("/usr/bin/osascript", ["-e", script])
        } catch {
            throw PrivilegedError.failed(error.localizedDescription)
        }

        if !result.succeeded {
            // 사용자가 인증 취소 시 osascript는 -128 에러를 낸다.
            if result.stderr.contains("-128") || result.stderr.localizedCaseInsensitiveContains("User canceled") {
                throw PrivilegedError.cancelled
            }
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PrivilegedError.failed(message.isEmpty ? "명령 실행에 실패했습니다." : message)
        }
    }

    /// 작은따옴표로 감싸 셸 메타문자를 무력화한다.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
