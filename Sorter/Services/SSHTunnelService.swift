import Foundation
import Citadel
import Crypto

enum TunnelError: LocalizedError {
    case noPassword
    case invalidKeyPath
    case invalidKeyFormat
    case unsupportedKeyType(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPassword: return "비밀번호가 필요합니다."
        case .invalidKeyPath: return "공개키 파일 경로가 올바르지 않습니다."
        case .invalidKeyFormat: return "공개키 파일 형식이 지원되지 않습니다. (ed25519 OpenSSH 형식 권장)"
        case .unsupportedKeyType(let t): return "지원하지 않는 키 타입입니다: \(t)"
        case .connectionFailed(let msg): return "연결 실패: \(msg)"
        }
    }
}

struct SSHTunnelService {
    static func connect(config: TunnelConfig, password: String?) async throws -> SSHClient {
        let authMethod = try buildAuthMethod(config: config, password: password)
        let client = try await SSHClient.connect(
            host: config.sshHost,
            port: config.sshPort,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )
        return client
    }

    private static func buildAuthMethod(config: TunnelConfig, password: String?) throws -> SSHAuthenticationMethod {
        switch config.authKind {
        case .password:
            guard let pw = password, !pw.isEmpty else { throw TunnelError.noPassword }
            return .passwordBased(username: config.username, password: pw)
        case .publicKey:
            guard let path = config.publicKeyPath, !path.isEmpty else { throw TunnelError.invalidKeyPath }
            return try buildPublicKeyAuth(username: config.username, path: path)
        }
    }

    private static func buildPublicKeyAuth(username: String, path: String) throws -> SSHAuthenticationMethod {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard let keyContent = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            throw TunnelError.invalidKeyPath
        }

        let keyType = try SSHKeyDetection.detectPrivateKeyType(from: keyContent)

        switch keyType {
        case .ed25519:
            let privateKey = try Curve25519.Signing.PrivateKey(sshEd25519: keyContent)
            return .ed25519(username: username, privateKey: privateKey)
        case .rsa:
            let privateKey = try Insecure.RSA.PrivateKey(sshRsa: keyContent)
            return .rsa(username: username, privateKey: privateKey)
        default:
            throw TunnelError.unsupportedKeyType(keyType.description)
        }
    }
}
