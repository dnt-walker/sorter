import SwiftUI
import AppKit

struct TunnelEditView: View {
    @EnvironmentObject private var vm: TunnelsViewModel
    @Environment(\.dismiss) private var dismiss

    let existing: TunnelConfig?

    @State private var name: String = ""
    @State private var sshHost: String = ""
    @State private var sshPort: String = "22"
    @State private var username: String = ""
    @State private var authKind: TunnelConfig.AuthKind = .password
    @State private var password: String = ""
    @State private var publicKeyPath: String = ""
    @State private var localPort: String = ""
    @State private var remoteHost: String = ""
    @State private var remotePort: String = ""

    @State private var commandInput: String = ""
    @State private var copyConfirmed: Bool = false

    private var isEditing: Bool { existing != nil }

    private var generatedCommand: String {
        guard !username.isEmpty, !sshHost.isEmpty,
              !localPort.isEmpty, !remoteHost.isEmpty, !remotePort.isEmpty else { return "" }
        let port = sshPort.isEmpty ? "22" : sshPort
        let portSuffix = port == "22" ? "" : " -p\(port)"
        return "ssh -L \(localPort):\(remoteHost):\(remotePort) \(username)@\(sshHost)\(portSuffix)"
    }

    init(existing: TunnelConfig? = nil) {
        self.existing = existing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "터널 수정" : "터널 추가")
                    .font(.title2).bold()
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("SSH 명령어") {
                    HStack(spacing: 6) {
                        TextField("", text: $commandInput)
                            .font(.system(.body, design: .monospaced))
                        Button("채우기") { parseCommand() }
                            .disabled(commandInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !generatedCommand.isEmpty {
                        HStack(spacing: 6) {
                            Text(generatedCommand)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Spacer()
                            Button(copyConfirmed ? "복사됨" : "복사") { copyCommand() }
                                .foregroundStyle(copyConfirmed ? .green : .accentColor)
                        }
                    }
                }

                Section("식별") {
                    LabeledContent("이름") {
                        TextField("", text: $name)
                    }
                }

                Section("SSH 서버") {
                    LabeledContent("호스트") {
                        TextField("", text: $sshHost)
                    }
                    LabeledContent("포트") {
                        TextField("", text: $sshPort)
                            .frame(width: 70)
                    }
                    LabeledContent("사용자명") {
                        TextField("", text: $username)
                    }
                }

                Section("인증") {
                    Picker("방식", selection: $authKind) {
                        ForEach(TunnelConfig.AuthKind.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    if authKind == .password {
                        LabeledContent("비밀번호") {
                            SecureField("", text: $password)
                        }
                    } else {
                        LabeledContent("개인키 파일") {
                            HStack {
                                Text(publicKeyPath.isEmpty ? "선택 안 됨" : publicKeyPath)
                                    .foregroundStyle(publicKeyPath.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("파일 선택…") { selectKeyFile() }
                            }
                        }
                    }
                }

                Section("포트 포워딩") {
                    LabeledContent("로컬 포트") {
                        TextField("", text: $localPort)
                            .frame(width: 100)
                    }
                    LabeledContent("원격 호스트") {
                        TextField("", text: $remoteHost)
                    }
                    LabeledContent("원격 포트") {
                        TextField("", text: $remotePort)
                            .frame(width: 100)
                    }
                }
            }
            .formStyle(.grouped)

            if let err = vm.errorMessage {
                HStack {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Divider()

            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button(isEditing ? "저장" : "추가") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            vm.errorMessage = nil
            loadExisting()
        }
    }

    // MARK: - SSH 명령어 파싱

    private func parseCommand() {
        let raw = commandInput.trimmingCharacters(in: .whitespaces)
        var tokens = raw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard tokens.first == "ssh" else { return }
        tokens.removeFirst()

        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            switch tok {
            case "-L":
                i += 1
                if i < tokens.count { applyForward(tokens[i]) }
            case "-p":
                i += 1
                if i < tokens.count { sshPort = tokens[i] }
            default:
                if tok.hasPrefix("-L") {
                    applyForward(String(tok.dropFirst(2)))
                } else if tok.hasPrefix("-p") {
                    sshPort = String(tok.dropFirst(2))
                } else if tok.contains("@") && !tok.hasPrefix("-") {
                    let parts = tok.components(separatedBy: "@")
                    if parts.count == 2 {
                        username = parts[0]
                        sshHost = parts[1]
                    }
                }
            }
            i += 1
        }
    }

    private func applyForward(_ spec: String) {
        // spec: localPort:remoteHost:remotePort
        let parts = spec.components(separatedBy: ":")
        guard parts.count == 3 else { return }
        localPort = parts[0]
        remoteHost = parts[1]
        remotePort = parts[2]
    }

    // MARK: - 명령어 복사

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedCommand, forType: .string)
        copyConfirmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyConfirmed = false }
    }

    // MARK: - 기존 설정 로드

    private func loadExisting() {
        guard let c = existing else { return }
        name = c.name
        sshHost = c.sshHost
        sshPort = String(c.sshPort)
        username = c.username
        authKind = c.authKind
        publicKeyPath = c.publicKeyPath ?? ""
        localPort = String(c.localPort)
        remoteHost = c.remoteHost
        remotePort = String(c.remotePort)
        if c.authKind == .password,
           let pw = try? KeychainHelper.load(forKey: c.keychainKey) {
            password = pw
        }
    }

    private func selectKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "개인키 파일 선택"
        panel.message = "SSH 개인키 파일을 선택하세요 (id_ed25519, id_rsa 등)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: (NSString("~/.ssh") as NSString).expandingTildeInPath)
        if panel.runModal() == .OK {
            publicKeyPath = panel.url?.path ?? ""
        }
    }

    private func save() {
        var config = existing ?? TunnelConfig(
            name: "", sshHost: "", username: "",
            authKind: authKind, localPort: 0, remoteHost: "", remotePort: 0
        )
        config.name = name.trimmingCharacters(in: .whitespaces)
        config.sshHost = sshHost.trimmingCharacters(in: .whitespaces)
        config.sshPort = Int(sshPort) ?? 22
        config.username = username.trimmingCharacters(in: .whitespaces)
        config.authKind = authKind
        config.publicKeyPath = authKind == .publicKey ? publicKeyPath : nil
        config.localPort = Int(localPort) ?? 0
        config.remoteHost = remoteHost.trimmingCharacters(in: .whitespaces)
        config.remotePort = Int(remotePort) ?? 0

        let pw = authKind == .password ? password : nil
        if vm.save(config, password: pw, isEditing: isEditing) {
            dismiss()
        }
    }
}
