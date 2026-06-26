import Foundation

/// Real `CommandRunner` backed by `Foundation.Process`. Captures stdout/stderr and
/// the termination status and maps them to a `CommandResult` — the `Process` instance
/// never escapes this method. (SPEC §3.2)
///
/// The blocking process work runs off the cooperative pool so an `await`ing caller is
/// not stalled. Output is read on a background thread before `waitUntilExit()` to avoid
/// a pipe-buffer deadlock on large stdout.
public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executablePath: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self),
                    exitCode: process.terminationStatus
                ))
            }
        }
    }
}
