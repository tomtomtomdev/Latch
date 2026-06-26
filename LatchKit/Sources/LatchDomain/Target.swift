// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// An attachable target: a local macOS process, or an app on a connected iOS device.
/// Device-backed targets arrive in the iOS slice; for now only `.localMac` is produced.
/// (SPEC §4)
public struct Target: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case localMac
        case iOSDevice
    }

    public let id: String
    public let kind: Kind
    public let pid: Int32?
    public let bundleID: String?
    public let displayName: String
    public let deviceUDID: String?

    public init(
        id: String,
        kind: Kind,
        pid: Int32? = nil,
        bundleID: String? = nil,
        displayName: String,
        deviceUDID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.pid = pid
        self.bundleID = bundleID
        self.displayName = displayName
        self.deviceUDID = deviceUDID
    }
}
