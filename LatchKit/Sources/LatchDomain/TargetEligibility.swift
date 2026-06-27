// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Why a target cannot be profiled. iOS profiling is tightly constrained (SPEC §1): only
/// development-signed apps on a paired iOS device with Developer Mode on. Each case carries
/// an honest, actionable message — the UI shows it verbatim and must never imply a
/// capability Latch doesn't have (e.g. profiling App Store apps). (SPEC §1, §8; PLAN slice 9)
public enum IneligibilityReason: Sendable, Equatable {
    /// The target isn't an iOS device (e.g. the host Mac, which `devicectl` can also list).
    case notIOSDevice
    /// The device isn't paired with this host.
    case deviceNotPaired
    /// Developer Mode is off on the device.
    case developerModeDisabled
    /// The app isn't development-signed — App Store / distribution-signed apps can't be profiled.
    case appNotDevelopmentSigned

    /// User-facing copy for the ineligible-target UI.
    public var message: String {
        switch self {
        case .notIOSDevice:
            "This isn't an iOS device. Latch profiles development-signed iOS apps on a connected device."
        case .deviceNotPaired:
            "This device isn't paired with this Mac. Pair and trust it (connect it and confirm "
                + "the trust prompt), then try again."
        case .developerModeDisabled:
            "Developer Mode is off on this device. Enable it in Settings › Privacy & Security › "
                + "Developer Mode and restart the device, then try again."
        case .appNotDevelopmentSigned:
            "This app isn't development-signed. Only apps built with your own development "
                + "provisioning profile can be profiled — App Store and distribution-signed apps cannot."
        }
    }
}

/// The verdict of whether a target can be profiled. Pure value produced by the Domain
/// eligibility checks below and consumed by both discovery (to tag targets) and the UI
/// (to gate the attach action and explain refusals). (SPEC §1; PLAN slice 9)
public enum TargetEligibility: Sendable, Equatable {
    case eligible
    case ineligible(IneligibilityReason)

    public var isEligible: Bool {
        if case .eligible = self { true } else { false }
    }
}

extension Device {
    /// Whether this device is *configured* such that a development-signed app on it could be
    /// profiled: an iOS device, paired, with Developer Mode enabled. Connection is deliberately
    /// excluded — it is transient readiness (`isConnected`), not an intrinsic eligibility fact.
    /// (SPEC §1)
    public var profilingEligibility: TargetEligibility {
        guard platform == "iOS" else { return .ineligible(.notIOSDevice) }
        guard isPaired else { return .ineligible(.deviceNotPaired) }
        guard developerModeEnabled else { return .ineligible(.developerModeDisabled) }
        return .eligible
    }

    /// Eligibility of a specific app on this device: the device must be eligible *and* the app
    /// development-signed. A device-level problem wins (fix the device before the app matters).
    /// (SPEC §1)
    public func eligibility(forApp isDevelopmentSigned: Bool) -> TargetEligibility {
        guard profilingEligibility.isEligible else { return profilingEligibility }
        return isDevelopmentSigned ? .eligible : .ineligible(.appNotDevelopmentSigned)
    }
}
