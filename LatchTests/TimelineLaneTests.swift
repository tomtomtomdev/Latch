import Testing
import LatchDomain
@testable import Latch

/// The timeline lanes (and the toolbar chips that mirror them) are a *formatting* of the
/// latest `MetricSample` — nothing synthesized. Frame time is the one gated lane: it is not a
/// cheap live counter for an external attach, so it is a hint/deep-run, never a live value.
/// (SPEC §1, §8 reconciliation; PLAN slice 11)
struct TimelineLaneTests {
    private func sample(
        cpu: Double = 0, footprintMB: Double = 0, netMBps: Double = 0, watts: Double = 0
    ) -> MetricSample {
        MetricSample(
            cpuPercent: cpu,
            physFootprintBytes: UInt64(footprintMB * 1_048_576),
            residentBytes: 0,
            threadCount: 0,
            netInBytesPerSec: netMBps * 1_000_000,
            netOutBytesPerSec: 0,
            energyWatts: watts
        )
    }

    // Each live lane reads its value straight from the latest sample.
    @Test func liveLanes_bindValuesFromSample() {
        let sample = sample(cpu: 73, footprintMB: 512, netMBps: 12, watts: 4.5)
        #expect(LaneKind.cpu.value(from: sample) == 73)
        #expect(LaneKind.memory.value(from: sample) == 512)
        #expect(LaneKind.network.value(from: sample) == 12)
        #expect(LaneKind.energy.value(from: sample) == 4.5)
    }

    // The four cheap signals are genuine live lanes.
    @Test func cheapSignals_areLiveLanes() {
        for lane in [LaneKind.cpu, .memory, .network, .energy] {
            #expect(lane.isLive)
        }
    }

    // Frame time is gated: not live, no live value, and its readout is an honest em-dash —
    // the ground truth is the on-demand Time Profiler run, not a faked live counter. (SPEC §8)
    @Test func frameLane_isGatedAsHint_withNoLiveValue() {
        let sample = sample(cpu: 99)
        #expect(LaneKind.frame.isLive == false)
        #expect(LaneKind.frame.value(from: sample) == nil)
        #expect(LaneKind.frame.formattedValue(from: sample) == "—")
    }

    // Before any sample is polled, a live lane reads an em-dash, not a fake zero.
    @Test func liveLane_readsDashWhenNoSampleYet() {
        #expect(LaneKind.cpu.formattedValue(from: nil) == "—")
    }

    // Chips mirror the five lanes in order (CPU · MEM · NET · ENERGY · FRAME). (Design handoff)
    @Test func lanes_coverTheFiveHandoffChips() {
        #expect(LaneKind.allCases == [.cpu, .memory, .network, .energy, .frame])
    }
}
