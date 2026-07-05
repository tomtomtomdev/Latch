import Testing
import LatchDomain
@testable import Latch

/// Slice 11 timeline controls on the per-target stream: pause freezes sampling, resume
/// rebaselines cleanly, and the range control trims the visible window without discarding
/// the ring buffer. (SPEC §4, §8; PLAN slice 11)
@MainActor
struct VitalsModelTimelineTests {
    private func reading(cpu: UInt64, wall: UInt64) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpu,
            physFootprintBytes: 0,
            residentBytes: 0,
            threadCount: 0,
            energyNanojoules: 0,
            wallClockNanos: wall
        )
    }

    /// `n + 1` readings advancing the wall clock by one second each — enough for `n` derived
    /// samples across `n + 1` polls.
    private func readings(_ n: Int) -> [VitalsReading] {
        (0...n).map { reading(cpu: 0, wall: UInt64($0) * 1_000_000_000) }
    }

    // Pausing freezes the stream: polls while paused advance nothing. (SPEC §8)
    @Test func poll_whilePaused_doesNotAppend() async {
        let model = VitalsModel(source: FakeMetricsSource(readings: readings(4)), pid: 1)
        await model.poll()
        await model.poll()
        let before = model.samples.count

        model.setPaused(true)
        await model.poll()
        await model.poll()

        #expect(model.samples.count == before)
    }

    // Resuming rebaselines: the first poll after resume only re-establishes the baseline (no
    // bogus delta spanning the paused gap), then sampling continues normally.
    @Test func resume_rebaselinesBeforeSampling() async {
        let model = VitalsModel(source: FakeMetricsSource(readings: readings(5)), pid: 1)
        await model.poll()
        await model.poll() // 1 sample

        model.setPaused(true)
        await model.poll() // ignored
        model.setPaused(false)
        await model.poll() // rebaseline — no new sample
        #expect(model.samples.count == 1)

        await model.poll() // now derives again
        #expect(model.samples.count == 2)
    }

    // The range control trims the visible window to its sample count; the full ring buffer is
    // retained but the timeline shows only the selected span. (SPEC §4, §8)
    @Test func range_trimsVisibleWindow() async {
        let model = VitalsModel(source: FakeMetricsSource(readings: readings(120)), pid: 1)
        for _ in 0...120 { await model.poll() }
        #expect(model.samples.count == 120)

        model.range = .thirtySeconds
        #expect(model.visibleSamples.count == 30)

        model.range = .oneMinute
        #expect(model.visibleSamples.count == 60)
    }

    // A window longer than the history shows the whole (short) history, not padding.
    @Test func visibleWindow_isWholeHistoryWhenShorterThanRange() async {
        let model = VitalsModel(source: FakeMetricsSource(readings: readings(5)), pid: 1)
        for _ in 0...5 { await model.poll() }

        model.range = .fiveMinutes

        #expect(model.visibleSamples.count == model.samples.count)
    }
}
