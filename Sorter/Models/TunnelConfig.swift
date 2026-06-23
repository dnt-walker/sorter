import Foundation

struct TunnelConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var sshHost: String
    var sshPort: Int = 22
    var username: String
    var authKind: AuthKind
    var publicKeyPath: String?
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
    var createdAt: Date = Date()

    enum AuthKind: String, Codable, CaseIterable {
        case password = "비밀번호"
        case publicKey = "공개키"
    }

    var keychainKey: String { "com.cheilpengtai.Sorter.tunnel.\(id.uuidString)" }
    var localAddress: String { "127.0.0.1:\(localPort)" }
    var remoteAddress: String { "\(remoteHost):\(remotePort)" }
}
