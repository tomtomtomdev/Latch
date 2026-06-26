import Testing
@testable import LatchDomain

struct SignalKindTests {
    // Proves LatchDomain builds standalone (zero outward imports) and carries the
    // six health signals Latch surfaces. (SPEC §3.3, §4; PLAN slice 0)
    @Test func signalKind_coversTheSixHealthSignals() {
        #expect(Set(SignalKind.allCases) == [
            .memoryLeak, .zombies, .hitch, .cpuSpike, .networkIO, .battery,
        ])
    }
}
