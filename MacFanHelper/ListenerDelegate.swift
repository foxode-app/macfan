import Foundation
import MacFanKit
import Security

/// Accepts XPC connections only from MacFan.app signed by the same team as this helper, so no other process can
/// drive the fans through it.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: FanControlService
    private let clientRequirement: String?

    init(service: FanControlService) {
        self.service = service
        clientRequirement = Self.teamIdentifier().map {
            "anchor apple generic and identifier \"\(FanHelper.appBundleIdentifier)\" "
                + "and certificate leaf[subject.OU] = \"\($0)\""
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // An ad hoc–signed helper has no team to compare against, so it accepts nobody.
        guard let clientRequirement else {
            logger.error("refusing connection: the helper is not signed with a team identifier")
            return false
        }
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = service
        let service = service
        connection.invalidationHandler = { service.connectionClosed() }
        service.connectionOpened()
        connection.resume()
        return true
    }

    /// The team identifier this process is signed with.
    private static func teamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
