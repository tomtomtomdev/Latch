// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A connected hardware device the user may profile apps on — an iOS device reached via
/// `devicectl`/`xctrace`. The `udid` is the hardware UDID, which is the identifier
/// `xctrace --device <udid>` keys on (verified against `xctrace list devices`). The fields
/// are the eligibility-relevant facts `devicectl list devices` reports; the eligibility
/// *verdict* is computed in `TargetEligibility`. (SPEC §1, §3.1, §4; PLAN slice 9)
public struct Device: Identifiable, Sendable, Equatable {
    /// Hardware UDID (`hardwareProperties.udid`) — what `xctrace --device` expects.
    public let udid: String
    /// User-assigned device name (`deviceProperties.name`).
    public let name: String
    /// Hardware platform (`hardwareProperties.platform`), e.g. `"iOS"`.
    public let platform: String
    /// Marketing OS version (`deviceProperties.osVersionNumber`), when reported.
    public let osVersion: String?
    /// Whether the device is paired with this host (`connectionProperties.pairingState == "paired"`).
    public let isPaired: Bool
    /// Whether Developer Mode is enabled (`deviceProperties.developerModeStatus == "enabled"`).
    public let developerModeEnabled: Bool
    /// Whether a live connection/tunnel to the device is established right now
    /// (`connectionProperties.tunnelState == "connected"`). This is transient runtime
    /// *readiness*, not part of the intrinsic eligibility verdict — an eligible device that
    /// is merely unplugged should say "connect to profile", not "can't be profiled".
    public let isConnected: Bool

    public var id: String { udid }

    public init(
        udid: String,
        name: String,
        platform: String,
        osVersion: String? = nil,
        isPaired: Bool,
        developerModeEnabled: Bool,
        isConnected: Bool
    ) {
        self.udid = udid
        self.name = name
        self.platform = platform
        self.osVersion = osVersion
        self.isPaired = isPaired
        self.developerModeEnabled = developerModeEnabled
        self.isConnected = isConnected
    }
}
