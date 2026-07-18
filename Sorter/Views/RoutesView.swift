import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RoutesView: View {
    @EnvironmentObject private var viewModel: RoutesViewModel

    @State private var editSheet: EditSheet?
    @State private var routeToDelete: ManagedRoute?
    @State private var showDomainSheet = false

    private struct EditSheet: Identifiable {
        let id = UUID()
        let route: ManagedRoute?
    }

    var body: some View {
        VStack(spacing: 0) {
            table
            Divider()
            detail.frame(height: 200)
            statusBar
        }
        .onAppear { viewModel.refresh() }
        .navigationTitle("Routing Table")
        .toolbar { toolbarContent }
        .sheet(item: $editSheet) { sheet in
            RouteEditView(
                viewModel: viewModel,
                devices: viewModel.devices,
                existing: sheet.route
            )
        }
        .sheet(isPresented: $showDomainSheet) {
            DomainRouteView(viewModel: viewModel, devices: viewModel.devices)
        }
        .alert("라우트를 삭제할까요?", isPresented: deleteAlertBinding, presenting: routeToDelete) { route in
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task { await viewModel.delete(route) }
            }
        } message: { route in
            Text("\(route.cidr) → \(route.interface)\n실행: \(viewModel.routeService.deletePreviewCommand(for: route))\n\n이 작업은 관리자 권한이 필요합니다.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("필터", selection: $viewModel.filter) {
                ForEach(RouteFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .help("표시할 라우트 종류를 선택합니다.")

            Button { viewModel.refresh() } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)

            Menu {
                Button {
                    Task { await viewModel.reapplyMissing() }
                } label: {
                    if viewModel.missingCount > 0 {
                        Label("재반영 (\(viewModel.missingCount))", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("재반영", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .help("적용 설정(미적용 상태)인데 라우팅 테이블에 없는 항목만 다시 등록합니다.")

                Divider()

                Button {
                    Task { await viewModel.enableAll() }
                } label: {
                    Label("전체 활성화", systemImage: "play.circle")
                }
                .help("모든 사용자 라우트를 라우팅 테이블에 등록합니다.")

                Button {
                    Task { await viewModel.disableAll() }
                } label: {
                    Label("전체 비활성화", systemImage: "pause.circle")
                }
                .help("모든 사용자 라우트를 라우팅 테이블에서 제거합니다. (설정은 삭제되지 않음)")
            } label: {
                if viewModel.missingCount > 0 {
                    Label("일괄 작업 (\(viewModel.missingCount))", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("일괄 작업", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(viewModel.isLoading)

            Button { exportRoutes() } label: {
                Label("내보내기", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.store.routes.isEmpty)
            .help("사용자 라우트를 JSON 파일로 내보냅니다.")

            Button { importRoutes() } label: {
                Label("불러오기", systemImage: "square.and.arrow.down")
            }
            .help("라우트 파일에서 불러옵니다. 중복(목적지·프리픽스·인터페이스)은 건너뜁니다.")

            Button {
                showDomainSheet = true
            } label: {
                Label("도메인 IP", systemImage: "globe")
            }
            .help("도메인의 IPv4 주소를 모두 조회해 호스트 라우트로 일괄 추가합니다.")

            Button {
                editSheet = EditSheet(route: nil)
            } label: {
                Label("라우트 추가", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // MARK: - 내보내기 / 불러오기

    private func exportRoutes() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "sorter-routes.json"
        panel.prompt = "내보내기"
        panel.message = "사용자 라우트를 저장할 위치를 선택하세요."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try viewModel.exportRoutes(to: url)
                viewModel.statusMessage = "라우트 \(viewModel.store.routes.count)개를 내보냈습니다."
            } catch {
                viewModel.errorMessage = "내보내기 실패: \(error.localizedDescription)"
            }
        }
    }

    private func importRoutes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "불러오기"
        panel.message = "가져올 Sorter 라우트 JSON 파일을 선택하세요."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let result = try viewModel.importRoutes(from: url)
                if result.added == 0 && result.skipped == 0 {
                    viewModel.statusMessage = "불러올 라우트가 없습니다."
                } else if result.skipped == 0 {
                    viewModel.statusMessage = "\(result.added)개를 불러왔습니다."
                } else {
                    viewModel.statusMessage = "\(result.added)개 추가, \(result.skipped)개 중복 건너뜀."
                }
            } catch {
                viewModel.errorMessage = "불러오기 실패: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(viewModel.rows, selection: $viewModel.selectedRowID) {
            TableColumn("상태") { row in statusBadge(row) }
                .width(36)
            TableColumn("이름") { row in
                Text(row.name)
                    .foregroundStyle(row.isEnabled ? Color.primary : Color.secondary)
            }
            TableColumn("목적지") { row in
                Text(row.destination)
                    .foregroundStyle(row.isEnabled ? Color.primary : Color.secondary)
            }
            TableColumn("프리픽스") { row in
                Text(row.prefixText)
                    .foregroundStyle(row.isEnabled ? Color.primary : Color.secondary)
            }
            TableColumn("인터페이스") { row in
                Text(row.interface)
                    .foregroundStyle(row.isEnabled ? Color.primary : Color.secondary)
            }
            TableColumn("유형") { row in
                Text(row.typeText)
                    .foregroundStyle(row.isEnabled ? Color.primary : Color.secondary)
            }
            TableColumn("액션") { row in actions(for: row) }
                .width(50)
        }
    }

    /// 첫 번째 컬럼: 라우트의 시스템 적용 상태.
    /// 관리 라우트는 생성/활성화/미적용 3단계, 시스템 라우트는 잠금 표시.
    @ViewBuilder
    private func statusBadge(_ row: RouteRow) -> some View {
        if !row.isManaged {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.secondary)
                .help("시스템 라우트 (보호됨) — 라우팅 테이블에 적용됨")
        } else if let status = row.status {
            switch status {
            case .created:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(Color.secondary)
                    .help("생성 — 아직 라우팅 테이블에 적용되지 않음")
            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .help("활성화 — 라우팅 테이블에 적용됨")
            case .notApplied:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .help("미적용 — 적용 설정이지만 라우팅 테이블에 없음 (재반영 필요)")
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(for row: RouteRow) -> some View {
        if row.isManaged, let managed = row.managed {
            Menu {
                Button {
                    editSheet = EditSheet(route: managed)
                } label: {
                    Label("수정", systemImage: "pencil")
                }

                Button {
                    Task { await viewModel.toggleEnabled(managed) }
                } label: {
                    if row.isEnabled {
                        Label("비활성화", systemImage: "pause.circle")
                    } else {
                        Label("활성화", systemImage: "play.circle")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    routeToDelete = managed
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let row = viewModel.selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("세부 정보 (\(row.destination)\(row.isManaged ? row.prefixText : "") → \(row.interface))")
                        .font(.headline)
                    DetailRow("이름", row.name)
                    DetailRow("목적지", row.destination)
                    DetailRow("프리픽스", row.prefixText.isEmpty ? "—" : row.prefixText)
                    DetailRow("인터페이스", row.interface)
                    DetailRow("유형", row.typeText)
                    if let managed = row.managed {
                        DetailRow("게이트웨이", managed.gateway ?? "(interface 라우트)")
                        DetailRow("등록일", managed.createdAt.formatted(date: .numeric, time: .shortened))
                        DetailRow("상태", row.status.map(statusText) ?? "—")
                    } else {
                        Text("시스템 라우트는 보호되어 수정/삭제할 수 없습니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("라우트를 선택하세요.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusText(_ status: RouteStatus) -> String {
        switch status {
        case .created:    return "생성 — 아직 라우팅 테이블에 적용되지 않음"
        case .active:     return "✅ 활성화 — 라우팅 테이블에 적용됨"
        case .notApplied: return "⚠️ 미적용 — 적용 설정이지만 라우팅 테이블에 없음 (재반영 필요)"
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if let status = viewModel.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            if viewModel.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { routeToDelete != nil },
            set: { if !$0 { routeToDelete = nil } }
        )
    }
}
