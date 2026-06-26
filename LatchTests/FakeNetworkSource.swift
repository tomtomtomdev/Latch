import LatchDomain

/// Test double: hands back a scripted sequence of raw network readings, one per `sample`
/// call, so `VitalsModel`'s rate derivation and network alerting are exercised without
/// shelling out to `nettop`. Main-actor confined in tests, hence `@unchecked Sendable`.
/// Returns a zero reading once the script is exhausted (network is best-effort). (SPEC §6)
final class FakeNetworkSource: NetworkSource, @unchecked Sendable {
    private let readings: [NetworkReading]
    private var callCount = 0

    init(readings: [NetworkReading]) {
        self.readings = readings
    }

    func sample(pid: Int32) async throws -> NetworkReading {
        defer { callCount += 1 }
        guard callCount < readings.count else {
            return NetworkReading(bytesIn: 0, bytesOut: 0, wallClockNanos: 0)
        }
        return readings[callCount]
    }
}
