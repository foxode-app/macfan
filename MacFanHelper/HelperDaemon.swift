import Foundation
import MacFanKit

enum HelperDaemon {
    static func run() -> Never {
        let service = FanControlService()
        let delegate = ListenerDelegate(service: service)
        let listener = NSXPCListener(machServiceName: FanHelper.machServiceName)
        listener.delegate = delegate
        listener.resume()

        // launchd sends SIGTERM when the helper is unregistered or the Mac shuts down; hand the fans back first.
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler {
            service.shutDown()
            exit(0)
        }
        termination.resume()

        // The listener holds its delegate weakly; keep everything alive for the life of the process.
        withExtendedLifetime((listener, delegate, termination)) {
            dispatchMain()
        }
    }
}
