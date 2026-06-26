import Testing
import LatchDomain
@testable import Latch

@MainActor
struct VitalsModelTests {
    private func reading(
        cpu: UInt64, wall: UInt64, footprint: UInt64 = 0, threads: Int = 0, energy: UInt64 = 0
    ) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpu,
            physFootprintBytes: footprint,
            residentBytes: 0,
            threadCount: threads,
            energyNanojoules: energy,
            wallClockNanos: wall
        )
    }

    private func networkReading(in bytesIn: UInt64, out bytesOut: UInt64, wall: UInt64) -> NetworkReading {
        NetworkReading(bytesIn: bytesIn, bytesOut: bytesOut, wallClockNanos: wall)
    }

    // CPU% needs two readings to form a delta, so the first poll only records a baseline
    // and emits no chartable sample yet. (PLAN slice 2)
    @Test func poll_firstTickEstablishesBaselineOnly() async {
        let source = FakeMetricsSource(readings: [reading(cpu: 1_000_000_000, wall: 0)])
        let model = VitalsModel(source: source, pid: 1)

        await model.poll()

        #expect(model.samples.isEmpty)
        #expect(model.errorMessage == nil)
    }

    // The second poll derives a sample from the delta between the two readings. (PLAN slice 2)
    @Test func poll_secondTickDerivesSampleFromDelta() async {
        let source = FakeMetricsSource(readings: [
            reading(cpu: 1_000_000_000, wall: 0),
            reading(cpu: 1_500_000_000, wall: 1_000_000_000, footprint: 2_097_152, threads: 4),
        ])
        let model = VitalsModel(source: source, pid: 1)

        await model.poll()
        await model.poll()

        #expect(model.samples.count == 1)
        #expect(model.latest?.cpuPercent == 50)
        #expect(model.latest?.threadCount == 4)
        #expect(model.latest?.physFootprintMegabytes == 2)
    }

    // The live history is a ring buffer: once full, the oldest sample is dropped so memory
    // stays bounded (SPEC §4 caps retention). (PLAN slice 2)
    @Test func poll_capsHistoryAtCapacity() async {
        let source = FakeMetricsSource(readings: (0...4).map { i in
            reading(cpu: UInt64(i) * 1_000_000_000, wall: UInt64(i) * 1_000_000_000)
        })
        let model = VitalsModel(source: source, pid: 1, capacity: 2)

        for _ in 0..<5 { await model.poll() }

        #expect(model.samples.count == 2)
    }

    // A source failure (target exited / unreadable) surfaces as a message instead of a crash.
    @Test func poll_recordsErrorWhenSourceThrows() async {
        let source = FakeMetricsSource(readings: [reading(cpu: 0, wall: 0)], errorOnCall: 0)
        let model = VitalsModel(source: source, pid: 1)

        await model.poll()

        #expect(model.errorMessage != nil)
        #expect(model.samples.isEmpty)
    }

    // With a network source attached, each derived sample carries the throughput computed
    // from consecutive nettop readings. (PLAN slice 4)
    @Test func poll_attachesNetworkRateFromConsecutiveReadings() async {
        let source = FakeMetricsSource(readings: [
            reading(cpu: 0, wall: 0),
            reading(cpu: 0, wall: 1_000_000_000),
        ])
        let network = FakeNetworkSource(readings: [
            networkReading(in: 0, out: 0, wall: 0),
            networkReading(in: 1_000_000, out: 0, wall: 1_000_000_000),
        ])
        let model = VitalsModel(source: source, networkSource: network, pid: 1)

        await model.poll()
        await model.poll()

        #expect(model.latest?.netInBytesPerSec == 1_000_000)
        #expect(model.latest?.networkMegabytesPerSecond == 1)
    }

    // Each derived sample carries the always-available energy estimate (watts) from the
    // ri_energy_nj delta: 2 J burned over 1 s is 2 W. (PLAN slice 5)
    @Test func poll_attachesEnergyEstimateFromConsecutiveReadings() async {
        let source = FakeMetricsSource(readings: [
            reading(cpu: 0, wall: 0, energy: 1_000_000_000),
            reading(cpu: 0, wall: 1_000_000_000, energy: 3_000_000_000),
        ])
        let model = VitalsModel(source: source, pid: 1)

        await model.poll()
        await model.poll()

        #expect(model.latest?.energyWatts == 2)
    }

    // The on-demand measured read upgrades the estimate to powermetrics' higher-fidelity
    // figure when privilege is granted. (PLAN slice 5; SPEC §3.3)
    @Test func measureEnergy_storesMeasuredImpactFromSource() async {
        let source = FakeMetricsSource(readings: [reading(cpu: 0, wall: 0)])
        let model = VitalsModel(source: source, energySource: FakeEnergySource(impact: 42.57), pid: 1)

        await model.measureEnergy()

        #expect(model.measuredEnergy == 42.57)
        #expect(model.energyMessage == nil)
    }

    // When powermetrics can't run (no root), the measured read degrades: no measurement is
    // shown and the user is told why — the live estimate carries on. (SPEC §1, §5)
    @Test func measureEnergy_degradesWhenSourceUnavailable() async {
        let source = FakeMetricsSource(readings: [reading(cpu: 0, wall: 0)])
        let model = VitalsModel(
            source: source, energySource: FakeEnergySource(failsWith: .unavailable), pid: 1
        )

        await model.measureEnergy()

        #expect(model.measuredEnergy == nil)
        #expect(model.energyMessage != nil)
    }

    // Readings whose CPU time grows by `percent`% of a wall-second each tick.
    private func cpuReadings(percent: Double, ticks: Int) -> [VitalsReading] {
        (0...ticks).map { i in
            reading(cpu: UInt64(Double(i) * percent / 100 * 1_000_000_000), wall: UInt64(i) * 1_000_000_000)
        }
    }

    private let cpuThreshold = Threshold(signal: .cpuSpike, comparator: .greaterThan, value: 80, window: 3)

    // Sustained high CPU across the threshold window raises an active alert. (PLAN slice 3)
    @Test func poll_raisesAlertWhenCPUSustainedAboveThreshold() async {
        let source = FakeMetricsSource(readings: cpuReadings(percent: 90, ticks: 4))
        let model = VitalsModel(source: source, pid: 1, thresholds: [cpuThreshold])

        for _ in 0..<5 { await model.poll() }

        #expect(model.alerts.map(\.signal) == [.cpuSpike])
    }

    // CPU comfortably below the threshold raises nothing.
    @Test func poll_noAlertWhenBelowThreshold() async {
        let source = FakeMetricsSource(readings: cpuReadings(percent: 50, ticks: 4))
        let model = VitalsModel(source: source, pid: 1, thresholds: [cpuThreshold])

        for _ in 0..<5 { await model.poll() }

        #expect(model.alerts.isEmpty)
    }

    // Tuning the threshold above the live load clears the breach — per-target override. (SPEC §3.3)
    @Test func updateThreshold_retunesAlerting() async {
        let source = FakeMetricsSource(readings: cpuReadings(percent: 90, ticks: 4))
        let model = VitalsModel(source: source, pid: 1, thresholds: [cpuThreshold])
        for _ in 0..<5 { await model.poll() }
        #expect(!model.alerts.isEmpty)

        model.updateThreshold(.cpuSpike, value: 95)

        #expect(model.alerts.isEmpty)
    }

    // Network throughput that holds above the threshold across the window raises an alert.
    @Test func poll_raisesNetworkAlertWhenSustainedAboveThreshold() async {
        let source = FakeMetricsSource(readings: (0...4).map { i in
            reading(cpu: 0, wall: UInt64(i) * 1_000_000_000)
        })
        // 6 MB received each second — above the 5 MB/s default.
        let network = FakeNetworkSource(readings: (0...4).map { i in
            networkReading(in: UInt64(i) * 6_000_000, out: 0, wall: UInt64(i) * 1_000_000_000)
        })
        let networkThreshold = Threshold(signal: .networkIO, comparator: .greaterThan, value: 5, window: 3)
        let model = VitalsModel(
            source: source, networkSource: network, pid: 1, thresholds: [networkThreshold]
        )

        for _ in 0..<5 { await model.poll() }

        #expect(model.alerts.map(\.signal) == [.networkIO])
    }
}
