import Testing
import LatchDomain
@testable import Latch

@MainActor
struct VitalsModelTests {
    private func reading(cpu: UInt64, wall: UInt64, footprint: UInt64 = 0, threads: Int = 0) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpu,
            physFootprintBytes: footprint,
            residentBytes: 0,
            threadCount: threads,
            wallClockNanos: wall
        )
    }

    // CPU% needs two readings to form a delta, so the first poll only records a baseline
    // and emits no chartable sample yet. (PLAN slice 2)
    @Test func poll_firstTickEstablishesBaselineOnly() {
        let source = FakeMetricsSource(readings: [reading(cpu: 1_000_000_000, wall: 0)])
        let model = VitalsModel(source: source, pid: 1)

        model.poll()

        #expect(model.samples.isEmpty)
        #expect(model.errorMessage == nil)
    }

    // The second poll derives a sample from the delta between the two readings. (PLAN slice 2)
    @Test func poll_secondTickDerivesSampleFromDelta() {
        let source = FakeMetricsSource(readings: [
            reading(cpu: 1_000_000_000, wall: 0),
            reading(cpu: 1_500_000_000, wall: 1_000_000_000, footprint: 2_097_152, threads: 4),
        ])
        let model = VitalsModel(source: source, pid: 1)

        model.poll()
        model.poll()

        #expect(model.samples.count == 1)
        #expect(model.latest?.cpuPercent == 50)
        #expect(model.latest?.threadCount == 4)
        #expect(model.latest?.physFootprintMegabytes == 2)
    }

    // The live history is a ring buffer: once full, the oldest sample is dropped so memory
    // stays bounded (SPEC §4 caps retention). (PLAN slice 2)
    @Test func poll_capsHistoryAtCapacity() {
        let source = FakeMetricsSource(readings: (0...4).map { i in
            reading(cpu: UInt64(i) * 1_000_000_000, wall: UInt64(i) * 1_000_000_000)
        })
        let model = VitalsModel(source: source, pid: 1, capacity: 2)

        for _ in 0..<5 { model.poll() }

        #expect(model.samples.count == 2)
    }

    // A source failure (target exited / unreadable) surfaces as a message instead of a crash.
    @Test func poll_recordsErrorWhenSourceThrows() {
        let source = FakeMetricsSource(readings: [reading(cpu: 0, wall: 0)], errorOnCall: 0)
        let model = VitalsModel(source: source, pid: 1)

        model.poll()

        #expect(model.errorMessage != nil)
        #expect(model.samples.isEmpty)
    }
}
