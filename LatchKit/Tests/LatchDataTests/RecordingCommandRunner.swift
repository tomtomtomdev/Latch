import LatchData

/// Test double that records the last invocation and returns a canned result, so adapter
/// tests can both inject stdout and assert the exact command (path + flags) that ran.
/// Single-threaded use in tests, hence `@unchecked Sendable`. (SPEC §6)
final class RecordingCommandRunner: CommandRunner, @unchecked Sendable {
    let result: CommandResult
    private(set) var executablePath: String?
    private(set) var arguments: [String] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ executablePath: String, arguments: [String]) async throws -> CommandResult {
        self.executablePath = executablePath
        self.arguments = arguments
        return result
    }
}
