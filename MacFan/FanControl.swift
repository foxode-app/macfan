import Foundation
import MacFanKit
import Observation
import ServiceManagement
import os

/// Helper status changes and errors; `log stream --info --predicate 'subsystem BEGINSWITH "com.foxode.MacFan"'`.
private let logger = Logger(subsystem: "com.foxode.MacFan", category: "FanControl")

/// The user's fan settings, and the privileged helper that applies them.
///
/// Custom control needs the helper, a launchd daemon inside the app bundle. The first registration asks the user
/// to allow it in System Settings; until they do, the settings are kept but not applied. Quitting the app closes
/// the connection, and the helper then hands the fans back to macOS.
@MainActor
@Observable
final class FanControl {
    enum HelperState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
    }

    static let configurationKey = "fanControl"

    var configuration: FanControlConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(configuration), forKey: Self.configurationKey)
            scheduleApply()
        }
    }

    private(set) var helperState: HelperState = .notRegistered
    /// The last error from registering the helper or from fan control itself.
    private(set) var errorMessage: String?

    @ObservationIgnored private let daemon = SMAppService.daemon(plistName: FanHelper.daemonPlistName)
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(FanControlConfiguration.self, from: $0) }
        configuration = stored.flatMap { $0.isValid ? $0 : nil } ?? FanControlConfiguration()
        refreshHelperState()
        if configuration.mode == .custom {
            if helperState == .notRegistered {
                register()
            }
            startMonitoring()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refreshHelperState() {
        let status = daemon.status
        let state: HelperState =
            switch status {
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            // A daemon that has never been registered reports notFound, not only notRegistered. If the helper is
            // really missing, register() fails and its error is shown.
            default: .notRegistered
            }
        if state != helperState {
            let name = String(describing: state)
            logger.info("helper status \(status.rawValue, privacy: .public): \(name, privacy: .public)")
        }
        helperState = state
    }

    /// Applies the settings once a slider has settled.
    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.apply()
        }
    }

    private func apply() async {
        refreshHelperState()
        guard configuration.mode == .custom else {
            monitorTask?.cancel()
            // Only a connected helper can be holding the fans; tell it to hand them back.
            if connection != nil {
                errorMessage = await send(configuration)
            } else {
                errorMessage = nil
            }
            return
        }
        if helperState == .notRegistered {
            register()
        }
        if helperState == .enabled {
            errorMessage = await send(configuration)
        }
        startMonitoring()
    }

    private func register() {
        do {
            try daemon.register()
            logger.info("helper registered")
            errorMessage = nil
        } catch {
            logger.error("helper registration failed: \(String(describing: error), privacy: .public)")
            refreshHelperState()
            // Registration reports an error while it waits for the user's approval; that is not worth showing.
            if helperState != .requiresApproval {
                errorMessage = error.localizedDescription
            }
        }
        refreshHelperState()
    }

    /// While custom control is on, watches for the user's approval and for errors the helper reports.
    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkHelper()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func checkHelper() async {
        let wasEnabled = helperState == .enabled
        refreshHelperState()
        guard helperState == .enabled else { return }
        if !wasEnabled || connection == nil {
            errorMessage = await send(configuration)
        } else {
            errorMessage = await call { helper, reply in helper.lastError(reply: reply) }
        }
    }

    private func send(_ configuration: FanControlConfiguration) async -> String? {
        guard let data = try? JSONEncoder().encode(configuration) else { return "could not encode the fan settings" }
        let error = await call { helper, reply in helper.apply(configuration: data, reply: reply) }
        if let error {
            logger.error("helper could not apply the settings: \(error, privacy: .public)")
        }
        return error
    }

    /// Calls the helper and waits for its reply: an error description, or `nil`.
    private func call(_ body: (FanHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void) async -> String? {
        let connection = currentConnection()
        return await withCheckedContinuation { continuation in
            let reply = SingleReply(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                reply.send(error.localizedDescription)
            }
            guard let helper = proxy as? FanHelperProtocol else {
                reply.send("the helper's interface is unavailable")
                return
            }
            body(helper) { reply.send($0) }
        }
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: FanHelper.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            // The helper restarted, which handed the fans back to macOS; send the settings again.
            Task { @MainActor in
                guard let self, self.configuration.mode == .custom else { return }
                self.errorMessage = await self.send(self.configuration)
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// Resumes a continuation once, with whichever of the reply and the connection error arrives first.
private final class SingleReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func send(_ message: String?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: message)
    }
}
