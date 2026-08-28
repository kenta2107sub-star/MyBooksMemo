import Foundation
import Network

// detailed_design.md 3-2（SummaryViewModel／BookDetailViewModel）が参照する
// `NetworkReachability.isConnected`の実体。FR-04・FR-05・FR-09の「ネットワーク接続なし」
// 異常系を、実際にリクエストを送る前に判定するための軽量ラッパー（NF-06参照）。
final class NetworkReachability {
    static let shared = NetworkReachability()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mybooksmemo.network-reachability")
    private var currentIsConnected: Bool = true
    private let lock = NSLock()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.currentIsConnected = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    static var isConnected: Bool {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.currentIsConnected
    }
}
