import LatchData

/// Test double: returns canned output instead of touching the OS, so adapter tests
/// inject stdout/stderr/exit-code without shelling out. (SPEC §6)
struct FakeCommandRunner: CommandRunner {
    let result: CommandResult

    func run(_ executablePath: String, arguments: [String]) async throws -> CommandResult {
        result
    }
}
