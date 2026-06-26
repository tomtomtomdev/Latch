import Testing
@testable import LatchDomain

struct MetricSampleTests {
    private func reading(
        cpuTimeNanos: UInt64 = 0,
        physFootprintBytes: UInt64 = 0,
        residentBytes: UInt64 = 0,
        threadCount: Int = 0,
        wallClockNanos: UInt64 = 0
    ) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpuTimeNanos,
            physFootprintBytes: physFootprintBytes,
            residentBytes: residentBytes,
            threadCount: threadCount,
            wallClockNanos: wallClockNanos
        )
    }

    // CPU% is the cumulative-CPU-time delta over the wall-clock delta, as a percentage
    // of one core: 0.5 s of CPU burned across a 1 s interval is 50%. (PLAN slice 2)
    @Test func derive_computesCPUPercentOfOneCore() {
        let previous = reading(cpuTimeNanos: 1_000_000_000, wallClockNanos: 0)
        let current = reading(cpuTimeNanos: 1_500_000_000, wallClockNanos: 1_000_000_000)

        let sample = MetricSample.derive(from: previous, to: current)

        #expect(sample.cpuPercent == 50)
    }

    // Burning more CPU time than wall-clock time means more than one core is busy, so
    // CPU% exceeds 100 — the threshold in SPEC §3.3 is "% of one core". (PLAN slice 2)
    @Test func derive_reportsOverOneHundredPercentForMultipleCores() {
        let previous = reading(cpuTimeNanos: 0, wallClockNanos: 0)
        let current = reading(cpuTimeNanos: 2_000_000_000, wallClockNanos: 1_000_000_000)

        let sample = MetricSample.derive(from: previous, to: current)

        #expect(sample.cpuPercent == 200)
    }

    // Two readings with the same timestamp would divide by zero; report 0% instead.
    @Test func derive_returnsZeroPercentWhenNoTimeElapsed() {
        let reading = reading(cpuTimeNanos: 5, wallClockNanos: 7)

        let sample = MetricSample.derive(from: reading, to: reading)

        #expect(sample.cpuPercent == 0)
    }

    // A counter that goes backwards (pid reuse) must not produce a negative CPU%.
    @Test func derive_clampsCPUPercentToZeroWhenCounterRewinds() {
        let previous = reading(cpuTimeNanos: 2_000_000_000, wallClockNanos: 0)
        let current = reading(cpuTimeNanos: 1_000_000_000, wallClockNanos: 1_000_000_000)

        let sample = MetricSample.derive(from: previous, to: current)

        #expect(sample.cpuPercent == 0)
    }

    // Memory + thread fields come straight from the latest reading; footprint bytes are
    // carried losslessly and also surfaced as MiB for the gauge. (PLAN slice 2)
    @Test func derive_carriesMemoryAndThreadsFromCurrentReading() {
        let previous = reading(wallClockNanos: 0)
        let current = reading(
            physFootprintBytes: 2_097_152,
            residentBytes: 1_048_576,
            threadCount: 9,
            wallClockNanos: 1_000_000_000
        )

        let sample = MetricSample.derive(from: previous, to: current)

        #expect(sample.physFootprintBytes == 2_097_152)
        #expect(sample.physFootprintMegabytes == 2)
        #expect(sample.residentBytes == 1_048_576)
        #expect(sample.threadCount == 9)
    }

    // A freshly derived sample carries no network rate until one is attached. (PLAN slice 4)
    @Test func derive_defaultsNetworkRateToZero() {
        let sample = MetricSample.derive(from: reading(), to: reading(wallClockNanos: 1))

        #expect(sample.netInBytesPerSec == 0)
        #expect(sample.netOutBytesPerSec == 0)
        #expect(sample.networkMegabytesPerSecond == 0)
    }

    // Attaching a network rate sets the in/out byte rates and surfaces their sum as MB/s,
    // the figure the network threshold compares against. (PLAN slice 4; SPEC §3.3)
    @Test func withNetwork_attachesRateAndSurfacesCombinedMegabytesPerSecond() {
        let base = MetricSample.derive(from: reading(), to: reading(wallClockNanos: 1))
        let rate = NetworkRate(inBytesPerSec: 4_000_000, outBytesPerSec: 2_000_000)

        let sample = base.withNetwork(rate)

        #expect(sample.netInBytesPerSec == 4_000_000)
        #expect(sample.netOutBytesPerSec == 2_000_000)
        #expect(sample.networkMegabytesPerSecond == 6)
    }
}
