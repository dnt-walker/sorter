import SwiftUI
import AppKit

struct MenuBarStatusView: View {
    @EnvironmentObject private var vm: RoutesViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        statusText
        Divider()
        if vm.missingCount > 0 {
            Button {
                Task { await vm.reapplyMissing() }
            } label: {
                Text("재반영 (\(vm.missingCount)개 누락)")
            }
            Divider()
        }
        Button("앱 열기") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("새로고침") {
            vm.refresh()
        }
        Divider()
        Button("Sorter 종료") {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        let total = vm.store.routes.count
        let missing = vm.missingCount
        if total == 0 {
            Text("관리 라우트 없음")
        } else if missing > 0 {
            Text("라우트 \(total)개 · \(missing)개 누락 ⚠️")
        } else {
            Text("라우트 \(total)개 모두 적용됨 ✅")
        }
    }
}
