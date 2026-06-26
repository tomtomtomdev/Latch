// LatchData — adapters and system I/O. Depends only on LatchDomain. (SPEC §3.2)

/// Outcome of running an external command, as a value type. No `Process` or other
/// system handle leaks past the Data boundary — adapters map raw output to Domain
/// entities. (SPEC §3.2, §6)
public struct CommandResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Abstraction over shelling out to a CLI tool (`nettop`, `leaks`, `xctrace`, …).
/// Every adapter that calls a system binary goes through this seam so tests inject
/// canned stdout via a fake instead of touching the OS. (SPEC §6)
public protocol CommandRunner: Sendable {
    func run(_ executablePath: String, arguments: [String]) async throws -> CommandResult
}
