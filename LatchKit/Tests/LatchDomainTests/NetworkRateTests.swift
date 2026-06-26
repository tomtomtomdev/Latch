import Testing
@testable import LatchDomain

struct NetworkRateTests {
    private func reading(in bytesIn: UInt64, out bytesOut: UInt64, wall: UInt64) -> NetworkReading {
        NetworkReading(bytesIn: bytesIn, bytesOut: bytesOut, wallClockNanos: wall)
    }

    // The rate is the cumulative-byte delta over the wall-clock delta: 1 MB received and
    // 0.5 MB sent across a 1 s interval is 1 MB/s in, 0.5 MB/s out. (PLAN slice 4; SPEC §6)
    @Test func derive_computesBytesPerSecondFromDeltas() {
        let previous = reading(in: 0, out: 0, wall: 0)
        let current = reading(in: 1_000_000, out: 500_000, wall: 1_000_000_000)

        let rate = NetworkRate.derive(from: previous, to: current)

        #expect(rate.inBytesPerSec == 1_000_000)
        #expect(rate.outBytesPerSec == 500_000)
    }

    // A half-second interval doubles the per-second rate.
    @Test func derive_scalesByElapsedTime() {
        let previous = reading(in: 0, out: 0, wall: 0)
        let current = reading(in: 1_000_000, out: 0, wall: 500_000_000)

        let rate = NetworkRate.derive(from: previous, to: current)

        #expect(rate.inBytesPerSec == 2_000_000)
    }

    // Two readings with the same timestamp would divide by zero; report a zero rate.
    @Test func derive_returnsZeroWhenNoTimeElapsed() {
        let sample = reading(in: 10, out: 20, wall: 7)

        let rate = NetworkRate.derive(from: sample, to: sample)

        #expect(rate == .zero)
    }

    // Counters that go backwards (pid reuse, nettop reset) must not produce a negative rate.
    @Test func derive_clampsToZeroWhenCountersRewind() {
        let previous = reading(in: 2_000_000, out: 2_000_000, wall: 0)
        let current = reading(in: 1_000_000, out: 1_000_000, wall: 1_000_000_000)

        let rate = NetworkRate.derive(from: previous, to: current)

        #expect(rate == .zero)
    }
}
