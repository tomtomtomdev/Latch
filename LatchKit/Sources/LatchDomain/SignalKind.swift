// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// The six health signals Latch surfaces for an attached target. (SPEC §3.3, §4)
public enum SignalKind: String, CaseIterable, Sendable, Codable {
    case memoryLeak
    case zombies
    case hitch
    case cpuSpike
    case networkIO
    case battery
}
