import SwiftUI

struct RouteEditView: View {
    @ObservedObject var viewModel: RoutesViewModel
    let devices: [NetworkDevice]
    let existing: ManagedRoute?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "-"
    @State private var kind: RouteKind = .net
    @State private var destination: String = ""
    @State private var prefix: Int = 24
    @State private var interface: String = ""
    @State private var gateway: String = ""
    /// 자동 추천으로 채운 게이트웨이 값(사용자가 직접 수정하면 gateway != autoFilledValue 가 되어 수동으로 간주).
    @State private var autoFilledValue: String?
    @State private var localError: String?
    @State private var isSubmitting = false

    private var isEditing: Bool { existing != nil }

    private var routableDevices: [NetworkDevice] {
        devices.filter { !$0.isLoopback }
    }

    private var selectedDevice: NetworkDevice? {
        devices.first { $0.bsdName == interface }
    }

    /// 수정 모드에서 기존 인터페이스가 현재 시스템에 없는 경우 해당 이름을 반환한다.
    private var offlineInterface: String? {
        guard isEditing, let r = existing,
              !routableDevices.contains(where: { $0.bsdName == r.interface }) else { return nil }
        return r.interface
    }

    /// 목적지가 선택된 인터페이스의 로컬 서브넷에 속하는지. nil=판단 불가.
    private var destinationIsLocal: Bool? {
        let dest = destination.trimmingCharacters(in: .whitespaces)
        guard !dest.isEmpty else { return nil }
        return selectedDevice?.isInLocalSubnet(dest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "라우트 수정" : "라우트 추가")
                .font(.title3).bold()
                .padding()
            Divider()

            Form {
                TextField("이름", text: $name)

                Picker("목적지 유형", selection: $kind) {
                    ForEach(RouteKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _ in if kind == .host { prefix = maxPrefix } }

                TextField("목적지 (예: 12.12.3.0)", text: $destination)
                    .onChange(of: destination) { _ in
                        clampPrefix()
                        recomputeGatewaySuggestion()
                    }

                if kind == .net {
                    Stepper(value: $prefix, in: 0...maxPrefix) {
                        HStack {
                            Text("프리픽스")
                            Spacer()
                            Text("/\(prefix)").monospaced().foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text("프리픽스")
                        Spacer()
                        Text("/\(maxPrefix) (호스트)").monospaced().foregroundStyle(.secondary)
                    }
                }

                Picker("대상 인터페이스", selection: $interface) {
                    Text("선택…").tag("")
                    ForEach(routableDevices) { d in
                        Text("\(d.bsdName) — \(d.displayName)").tag(d.bsdName)
                    }
                    if let offline = offlineInterface {
                        Divider()
                        Text("\(offline) (현재 없음)").tag(offline)
                    }
                }
                .onChange(of: interface) { _ in
                    // 인터페이스가 바뀌면 이전 자동 추천값은 무효 → 비우고 새 인터페이스 기준으로 재추천.
                    if let v = autoFilledValue, gateway == v { gateway = ""; autoFilledValue = nil }
                    recomputeGatewaySuggestion()
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("게이트웨이 (선택)", text: $gateway)
                        .help("입력 시 게이트웨이 라우트, 비우면 interface 라우트")
                    gatewayHint
                }
            }
            .formStyle(.grouped)

            commandPreview
                .padding(.horizontal)

            if let error = localError ?? viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Label("적용 시 관리자 권한이 필요합니다.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 6)

            Divider().padding(.top, 8)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "저장" : "추가") { submit(apply: false) }
                    .disabled(isSubmitting)
                Button(isEditing ? "저장·적용" : "적용") { submit(apply: true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear {
            viewModel.errorMessage = nil
            loadExisting()
            recomputeGatewaySuggestion()
        }
    }

    // MARK: - 명령 미리보기

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("실행될 명령(미리보기)").font(.caption).foregroundStyle(.secondary)
            Text(previewText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var previewText: String {
        viewModel.routeService.previewCommand(for: draftRoute())
    }

    // MARK: - 게이트웨이 힌트 / 자동 추천

    private var isAutoFilledGateway: Bool {
        if let v = autoFilledValue { return !gateway.isEmpty && gateway == v }
        return false
    }

    @ViewBuilder
    private var gatewayHint: some View {
        if isAutoFilledGateway {
            Label("이 인터페이스(\(interface))의 게이트웨이를 자동 추천했습니다.", systemImage: "wand.and.stars")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if destinationIsLocal == false, gateway.trimmingCharacters(in: .whitespaces).isEmpty {
            // 비로컬인데 게이트웨이가 비어있고 추천도 불가한 경우(인터페이스에 default 게이트웨이 없음).
            VStack(alignment: .leading, spacing: 4) {
                Label("목적지가 \(interface)의 로컬 서브넷 밖입니다. interface 라우트로는 도달하지 못합니다. next-hop 게이트웨이를 입력하세요.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let gw = selectedDevice?.gateway {
                    Button("추천 게이트웨이 사용 (\(gw))") {
                        gateway = gw
                        autoFilledValue = gw
                    }
                    .controlSize(.small)
                }
            }
        } else if destinationIsLocal == true, gateway.trimmingCharacters(in: .whitespaces).isEmpty {
            Label("로컬 링크 대상 → interface 라우트로 동작합니다.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 비로컬 목적지면 인터페이스 게이트웨이를 자동으로 채우고, 로컬로 바뀌면 자동값을 해제한다.
    /// 사용자가 직접 입력한 게이트웨이는 보존한다.
    private func recomputeGatewaySuggestion() {
        let isAuto = isAutoFilledGateway
        if destinationIsLocal == false, let gw = selectedDevice?.gateway {
            if gateway.trimmingCharacters(in: .whitespaces).isEmpty || isAuto {
                gateway = gw
                autoFilledValue = gw
            }
            return
        }
        if destinationIsLocal == true, isAuto {
            gateway = ""
            autoFilledValue = nil
        }
    }

    // MARK: - 로직

    private var maxPrefix: Int {
        destination.isEmpty ? 32 : IPValidator.maxPrefix(for: destination)
    }

    private func clampPrefix() {
        if prefix > maxPrefix { prefix = maxPrefix }
        if kind == .host { prefix = maxPrefix }
    }

    private func draftRoute() -> ManagedRoute {
        ManagedRoute(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            destination: destination.trimmingCharacters(in: .whitespaces),
            prefix: kind == .host ? maxPrefix : prefix,
            kind: kind,
            interface: interface,
            gateway: gateway.trimmingCharacters(in: .whitespaces),
            createdAt: existing?.createdAt ?? Date(),
            isEnabled: existing?.isEnabled ?? true
        )
    }

    private func loadExisting() {
        guard let r = existing else {
            interface = routableDevices.first?.bsdName ?? ""
            return
        }
        name = r.name
        kind = r.kind
        destination = r.destination
        prefix = r.prefix
        interface = r.interface
        gateway = r.gateway ?? ""
    }

    private func submit(apply: Bool) {
        localError = nil
        guard !interface.isEmpty else {
            localError = "대상 인터페이스를 선택하세요."
            return
        }
        isSubmitting = true
        Task {
            let ok = await viewModel.save(draftRoute(), isEditing: isEditing, apply: apply)
            isSubmitting = false
            if ok { dismiss() }
        }
    }
}
