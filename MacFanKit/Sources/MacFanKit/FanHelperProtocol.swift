import Foundation

/// The privileged helper's XPC interface. Settings travel as JSON so the interface stays the same as they grow.
@objc public protocol FanHelperProtocol {
    /// Applies a JSON-encoded `FanControlConfiguration`. Replies with an error description, or `nil`.
    func apply(configuration: Data, reply: @escaping @Sendable (String?) -> Void)

    /// Replies with the error that stopped fan control, or `nil` while it works.
    func lastError(reply: @escaping @Sendable (String?) -> Void)
}

public enum FanHelper {
    public static let machServiceName = "com.foxode.MacFan.FanHelper"
    public static let daemonPlistName = "com.foxode.MacFan.FanHelper.plist"
    /// The helper accepts connections only from this app, signed by the same team as the helper itself.
    public static let appBundleIdentifier = "com.foxode.MacFan"
}
