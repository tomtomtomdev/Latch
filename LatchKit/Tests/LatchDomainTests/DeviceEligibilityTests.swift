import Testing
import LatchDomain

/// Slice 9: the pure eligibility/messaging logic that gates iOS targets. A device is
/// profile-eligible only when it is an iOS device, paired, and has Developer Mode on; an
/// app on it is eligible only when the device is *and* the app is development-signed —
/// App Store / distribution-signed apps cannot be profiled. Each ineligible reason carries
/// an honest, actionable message for the UI. (SPEC §1; PLAN slice 9)
struct DeviceEligibilityTests {
    private func device(
        platform: String = "iOS",
        paired: Bool = true,
        developerMode: Bool = true,
        connected: Bool = false
    ) -> Device {
        Device(
            udid: "00008030-000000000000002E",
            name: "Latch Test iPhone",
            platform: platform,
            osVersion: "18.1.1",
            isPaired: paired,
            developerModeEnabled: developerMode,
            isConnected: connected
        )
    }

    // A paired iOS device with Developer Mode enabled is eligible — connection is a separate
    // runtime-readiness concern, not part of the intrinsic eligibility verdict.
    @Test func device_isEligible_whenPairedIOSWithDeveloperMode() {
        #expect(device().profilingEligibility == .eligible)
    }

    // Developer Mode off is the most common real blocker (one of the two captured fixture
    // devices is in exactly this state). (SPEC §1)
    @Test func device_isIneligible_whenDeveloperModeDisabled() {
        #expect(device(developerMode: false).profilingEligibility == .ineligible(.developerModeDisabled))
    }

    @Test func device_isIneligible_whenNotPaired() {
        #expect(device(paired: false).profilingEligibility == .ineligible(.deviceNotPaired))
    }

    // A non-iOS entry (e.g. the host Mac, which `devicectl list devices` can include) is not
    // an iOS profiling target.
    @Test func device_isIneligible_whenNotIOS() {
        #expect(device(platform: "macOS").profilingEligibility == .ineligible(.notIOSDevice))
    }

    // App-level gate: an eligible device + a development-signed app is eligible.
    @Test func app_isEligible_whenDeviceEligibleAndDevelopmentSigned() {
        #expect(device().eligibility(forApp: true) == .eligible)
    }

    // The headline iOS constraint: App Store / distribution-signed apps cannot be profiled. (SPEC §1)
    @Test func app_isIneligible_whenNotDevelopmentSigned() {
        #expect(device().eligibility(forApp: false) == .ineligible(.appNotDevelopmentSigned))
    }

    // A device-level failure short-circuits the app gate (the device reason wins — fix the
    // device before the app even matters).
    @Test func app_propagatesDeviceIneligibility() {
        #expect(device(developerMode: false).eligibility(forApp: true) == .ineligible(.developerModeDisabled))
    }

    // Every reason must carry a non-empty, honest message — this is the user-facing copy the
    // ineligible-target UI shows. (PLAN slice 9: "clear messaging when a target is ineligible")
    @Test func everyReason_hasANonEmptyMessage() {
        let reasons: [IneligibilityReason] = [
            .notIOSDevice, .deviceNotPaired, .developerModeDisabled, .appNotDevelopmentSigned,
        ]
        for reason in reasons {
            #expect(!reason.message.isEmpty)
        }
    }

    // The dev-signing message must name the honest constraint so the UI doesn't imply App
    // Store apps are profilable. (SPEC §1, §8 honesty)
    @Test func appNotDevelopmentSigned_messageNamesTheConstraint() {
        #expect(IneligibilityReason.appNotDevelopmentSigned.message.contains("development-signed"))
    }

    @Test func eligibility_isEligible_reflectsTheCase() {
        #expect(TargetEligibility.eligible.isEligible)
        #expect(!TargetEligibility.ineligible(.deviceNotPaired).isEligible)
    }
}
