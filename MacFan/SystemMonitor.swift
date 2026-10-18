import Foundation
import MacFanKit
import Observation

/// Samples the sensors on a timer and publishes the latest snapshot to the UI.
@MainActor
@Observable
final class SystemMonitor {
    static let refreshIntervalKey = "refreshInterval"

    private(set) var snapshot = SystemSnapshot()
    /// Set when the SMC cannot be opened; the panel shows it instead of readings.
    private(set) var errorMessage: String?

    /// Seconds between samples, within `RefreshInterval.range`. Saved to user defaults; the new interval
    /// applies from the next sample.
    var refreshInterval: TimeInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey)
            startRefreshing(sampleFirst: false)
        }
    }

    @ObservationIgnored private var sampler: SystemSampler?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        let storedInterval = UserDefaults.standard.double(forKey: Self.refreshIntervalKey)
        refreshInterval = RefreshInterval.clamped(storedInterval > 0 ? storedInterval : RefreshInterval.defaultValue)
        do {
            sampler = try SystemSampler()
        } catch {
            errorMessage = String(describing: error)
        }
        startRefreshing(sampleFirst: true)
    }

    /// Restarts the sampling loop. A changed interval does not trigger an extra sample, so dragging the interval
    /// slider does not hammer the SMC.
    private func startRefreshing(sampleFirst: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if !sampleFirst, let interval = self?.refreshInterval {
                try? await Task.sleep(for: .seconds(interval))
            }
            while !Task.isCancelled {
                guard let interval = await self?.refresh() else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Takes one sample and returns how long to wait before the next.
    private func refresh() async -> TimeInterval {
        if let sampler {
            snapshot = await sampler.sample()
        }
        return refreshInterval
    }
}
