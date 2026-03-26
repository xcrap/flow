import SwiftUI
import AFCore

@Observable
@MainActor
final class RuntimeHealthMonitor {
    let discovery: RuntimeDiscovery
    private(set) var healthByBinary: [String: BinaryHealth] = [:]
    private(set) var specs: [BinarySpec] = []

    init(discovery: RuntimeDiscovery) {
        self.discovery = discovery
    }

    func refresh() async {
        await discovery.refreshAll()
        healthByBinary = await discovery.allHealth()
        specs = await discovery.allSpecs()
    }

    func loadCurrent() async {
        healthByBinary = await discovery.allHealth()
        specs = await discovery.allSpecs()
    }

    func health(for id: String) -> BinaryHealth {
        healthByBinary[id] ?? .checking
    }
}
