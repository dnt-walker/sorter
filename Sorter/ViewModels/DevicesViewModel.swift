import Foundation
import Combine

@MainActor
final class DevicesViewModel: ObservableObject {
    @Published var devices: [NetworkDevice] = []
    @Published var selectedID: NetworkDevice.ID?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = NetworkDeviceService()

    var selectedDevice: NetworkDevice? {
        guard let id = selectedID else { return nil }
        return devices.first { $0.id == id }
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        let service = self.service
        Task {
            let result = await Task.detached { service.listDevices() }.value
            self.devices = result
            if result.isEmpty {
                self.errorMessage = "네트워크 디바이스를 불러올 수 없습니다."
            } else if self.selectedID == nil {
                self.selectedID = result.first?.id
            }
            self.isLoading = false
        }
    }
}
