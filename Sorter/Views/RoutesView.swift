import SwiftUI

struct RoutesView: View {
    @EnvironmentObject private var viewModel: RoutesViewModel

    @State private var editSheet: EditSheet?
    @State private var routeToDelete: ManagedRoute?

    private struct EditSheet: Identifiable {
        let id = UUID()
        let route: ManagedRoute?
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            table
            Divider()
            detail.frame(height: 200)
            statusBar
        }
        .onAppear { viewModel.refresh() }
        .sheet(item: $editSheet) { sheet in
            RouteEditView(
                viewModel: viewModel,
                devices: viewModel.devices,
                existing: sheet.route
            )
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("라우트").font(.title2).bold()
            Spacer()
            Picker("필터", selection: $viewModel.filter) {
                ForEach(RouteFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .labelsHidden()

            Button { viewModel.refresh() } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)

            Button {
                Task { await viewModel.reapplyMissing() }
            } label: {
                if viewModel.missingCount > 0 {
                    Label("재반영 (\(viewModel.missingCount))", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("재반영", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .help("저장된 사용자 라우트 중 라우팅 테이블에 없는 항목을 다시 등록합니다.")
            .disabled(viewModel.isLoading)

            Button {
                editSheet = EditSheet(route: nil)
            } label: {
                Label("라우트 추가", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding()
    }

    // MARK: - Table

    private var table: some View {
        Table(viewModel.rows, selection: $viewModel.selectedRowID) {
            TableColumn("") { row in
                Image(systemName: row.isManaged ? "pencil.circle" : "lock.fill")
                    .foregroundStyle(row.isManaged ? Color.accentColor : Color.secondary)
                    .help(row.isManaged ? "사용자 라우트" : "시스템 라우트 (보호됨)")
            }
            .width(28)
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
            TableColumn("적용") { row in appliedBadge(row) }
                .width(60)
            TableColumn("액션") { row in actions(for: row) }
                .width(175)
        }
    }

    @ViewBuilder
    private func appliedBadge(_ row: RouteRow) -> some View {
        if row.isManaged && !row.isEnabled {
            Image(systemName: "pause.circle")
                .foregroundStyle(Color.secondary)
                .help("비활성화됨")
        } else if let applied = row.applied {
            Image(systemName: applied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(applied ? Color.green : Color.orange)
                .help(applied ? "라우팅 테이블에 존재" : "스토어에만 있음 (재적용 필요)")
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(for row: RouteRow) -> some View {
        if row.isManaged, let managed = row.managed {
            HStack(spacing: 6) {
                Button("수정") {
                    editSheet = EditSheet(route: managed)
                }
                .buttonStyle(.borderless)
                .disabled(!row.isEnabled)

                Button(row.isEnabled ? "비활성화" : "활성화") {
                    Task { await viewModel.toggleEnabled(managed) }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(row.isEnabled ? Color.orange : Color.accentColor)

                Button("삭제") { routeToDelete = managed }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
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
                    DetailRow("목적지", row.destination)
                    DetailRow("프리픽스", row.prefixText.isEmpty ? "—" : row.prefixText)
                    DetailRow("인터페이스", row.interface)
                    DetailRow("유형", row.typeText)
                    if let managed = row.managed {
                        DetailRow("게이트웨이", managed.gateway ?? "(interface 라우트)")
                        DetailRow("등록일", managed.createdAt.formatted(date: .numeric, time: .shortened))
                        DetailRow("적용 상태", (row.applied ?? false) ? "✅ 라우팅 테이블에 존재" : "⚠️ 스토어에만 있음")
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
