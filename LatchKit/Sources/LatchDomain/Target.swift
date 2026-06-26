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
    /// Full on-disk path to the target's executable, when known. Local-Mac targets carry it
    /// (read via `proc_pidpath` during discovery); it is what a relaunch-only diagnostic like
    /// Zombies relaunches. `nil` for targets with no resolvable path. (SPEC §1; PLAN slice 7)
    public let executablePath: String?
    public let bundleID: String?
    public let displayName: String
    public let deviceUDID: String?

    public init(
        id: String,
        kind: Kind,
        pid: Int32? = nil,
        executablePath: String? = nil,
        bundleID: String? = nil,
        displayName: String,
        deviceUDID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.pid = pid
        self.executablePath = executablePath
        self.bundleID = bundleID
        self.displayName = displayName
        self.deviceUDID = deviceUDID
    }
}
