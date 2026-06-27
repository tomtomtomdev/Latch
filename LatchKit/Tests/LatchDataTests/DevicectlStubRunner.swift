import Foundation
import LatchData

/// Test double emulating `devicectl`'s actual contract: it writes JSON results to the file
/// path given via `--json-output` (per `devicectl --help`, "JSON output to a user-provided
/// file on disk is the ONLY supported interface for scripts/programs to consume command
/// output"). The double writes the canned fixture to that path and records the invocation so
/// tests can both feed parsed output and pin the exact command. Single-threaded test use,
/// hence `@unchecked Sendable`. (SPEC §6; PLAN slice 9)
final class DevicectlStubRunner: CommandRunner, @unchecked Sendable {
    let json: String
    let exitCode: Int32
    private(set) var executablePath: String?
    private(set) var arguments: [String] = []

    init(json: String = "", exitCode: Int32 = 0) {
        self.json = json
        self.exitCode = exitCode
    }

    func run(_ executablePath: String, arguments: [String]) async throws -> CommandResult {
        self.executablePath = executablePath
        self.arguments = arguments
        if exitCode == 0,
           let index = arguments.firstIndex(of: "--json-output"),
           index + 1 < arguments.count {
            try json.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
        }
        return CommandResult(stdout: "", stderr: exitCode == 0 ? "" : "devicectl failed", exitCode: exitCode)
    }
}
