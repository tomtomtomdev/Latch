import LatchDomain

/// Test double: hands back a scripted sequence of raw readings, one per `sample` call,
/// or throws a scripted error — so `VitalsModel`'s delta derivation and ring buffer are
/// exercised without touching libproc. Single-threaded and main-actor confined in tests,
/// hence `@unchecked Sendable`. Throws once the script is exhausted to catch over-polling.
/// (SPEC §6)
final class FakeMetricsSource: MetricsSource, @unchecked Sendable {
    enum Failure: Error { case scriptExhausted, scripted }

    private let readings: [VitalsReading]
    private let errorOnCall: Int?
    private var callCount = 0

    init(readings: [VitalsReading], errorOnCall: Int? = nil) {
        self.readings = readings
        self.errorOnCall = errorOnCall
    }

    func sample(pid: Int32) throws -> VitalsReading {
        defer { callCount += 1 }
        if callCount == errorOnCall { throw Failure.scripted }
        guard callCount < readings.count else { throw Failure.scriptExhausted }
        return readings[callCount]
    }
}
