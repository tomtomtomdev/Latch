import Testing
import Darwin
@testable import LatchData

struct LibprocMetricsSourceTests {
    // Sampling our own running process must return plausible, non-zero vitals. This
    // exercises the real libproc interop (struct flavor, field offsets, units) against
    // the live kernel — the parsing logic the headers were verified for. (PLAN slice 2)
    @Test func sample_readsLiveVitalsForCurrentProcess() throws {
        let source = LibprocMetricsSource()

        let reading = try source.sample(pid: getpid())

        #expect(reading.threadCount >= 1)
        #expect(reading.physFootprintBytes > 0)
        #expect(reading.residentBytes > 0)
        #expect(reading.cpuTimeNanos > 0)
        #expect(reading.energyNanojoules > 0)
        #expect(reading.wallClockNanos > 0)
    }

    // A pid that cannot exist must surface as a thrown error, not bogus zeros — the
    // model relies on this to stop polling a target that has exited. (SPEC §1)
    @Test func sample_throwsForAnUnreadablePid() {
        let source = LibprocMetricsSource()

        #expect(throws: (any Error).self) {
            try source.sample(pid: -1)
        }
    }
}
