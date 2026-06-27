import Testing
import LatchDomain

/// The live hitch/hang heuristic (SPEC §3.3 "main thread blocked > 250 ms"): given a series
/// of main-thread stack samples taken at a fixed interval, flag every *consecutive* run of
/// an unchanged stack that lasts longer than the hang bar. Pure and deterministic — driven
/// here by synthetic series, which is the slice's required test. (PLAN slice 8)
struct DetectHangsTests {
    private let detect = DetectHangs(interval: .milliseconds(10))

    // The slice's required test: the main thread wedged in one stack for longer than the
    // 250 ms bar (30 samples × 10 ms = 300 ms) is flagged, naming the wedged stack, the
    // sample count, and the stall duration. (PLAN slice 8; SPEC §3.3)
    @Test func flagsMainThreadBlockOver250ms() throws {
        let wedged = StackSample(frames: ["start", "doWork", "-[Store save]", "__semwait_signal"])
        let series = Array(repeating: wedged, count: 30)

        let hangs = detect(series)

        #expect(hangs.count == 1)
        let hang = try #require(hangs.first)
        #expect(hang.stack == wedged.frames)
        #expect(hang.leaf == "__semwait_signal")
        #expect(hang.sampleCount == 30)
        #expect(hang.duration == .milliseconds(300))
    }

    // A responsive main thread changes its stack sample to sample — it never sits still long
    // enough to be a stall, so no hang is reported.
    @Test func ignoresResponsiveSeries() {
        let series = (0..<40).map { StackSample(frames: ["start", "render", "draw\($0)"]) }

        #expect(detect(series).isEmpty)
    }

    // The bar is strictly greater than 250 ms: exactly 250 ms (25 × 10 ms) is not a hang,
    // 260 ms (26 × 10 ms) is. Pins the ">" semantics in SPEC §3.3.
    @Test func usesStrictlyGreaterThanThreshold() {
        let stalled = StackSample(frames: ["start", "__ulock_wait"])

        #expect(detect(Array(repeating: stalled, count: 25)).isEmpty)
        #expect(detect(Array(repeating: stalled, count: 26)).count == 1)
    }

    // A stall is a *consecutive* block: the same stack seen 20 + 20 times either side of other
    // work is two 200 ms stretches, not one 400 ms hang. Total-time-in-a-stack is not a hang.
    @Test func foldsConsecutiveRunsNotTotalOccurrences() {
        let waiting = StackSample(frames: ["start", "poll", "__semwait_signal"])
        let working = StackSample(frames: ["start", "compute"])
        let series = Array(repeating: waiting, count: 20) + [working] + Array(repeating: waiting, count: 20)

        #expect(detect(series).isEmpty)
    }

    // Distinct stalls in one run are reported independently; a responsive stretch between them
    // ends the first run. (triangulates generality beyond a single block)
    @Test func flagsEachDistinctBlock() {
        let readBlock = StackSample(frames: ["start", "load", "__read_nocancel"])
        let lockBlock = StackSample(frames: ["start", "lock", "__psynch_mutexwait"])
        let moving = StackSample(frames: ["start", "spin"])
        let series = Array(repeating: readBlock, count: 30) + [moving] + Array(repeating: lockBlock, count: 30)

        let hangs = detect(series)

        #expect(hangs.map(\.leaf) == ["__read_nocancel", "__psynch_mutexwait"])
    }

    @Test func emptySeriesHasNoHangs() {
        #expect(detect([]).isEmpty)
    }
}
