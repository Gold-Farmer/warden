import Foundation

@MainActor
@Observable
final class RefreshScheduler {
    var interval: TimeInterval = 300 {
        didSet {
            if isRunning { restart() }
        }
    }

    private(set) var isRunning = false
    private(set) var lastRefresh: Date?
    private var task: Task<Void, Never>?
    var onRefresh: (() async -> Void)?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNext()
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    func restart() {
        stop()
        start()
    }

    private func scheduleNext() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.interval ?? 300))
                guard !Task.isCancelled else { break }
                await self?.onRefresh?()
                self?.lastRefresh = Date()
            }
        }
    }
}
