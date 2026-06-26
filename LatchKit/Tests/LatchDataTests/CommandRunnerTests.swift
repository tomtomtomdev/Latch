import Testing
@testable import LatchData

struct CommandRunnerTests {
    // The slice-0 contract: a fake CommandRunner hands back exactly the canned result.
    @Test func fakeCommandRunner_returnsCannedStdout() async throws {
        let canned = CommandResult(stdout: "hello\n", stderr: "", exitCode: 0)
        let runner = FakeCommandRunner(result: canned)

        let output = try await runner.run("/usr/bin/true", arguments: [])

        #expect(output == canned)
    }

    // The real runner maps a live process's output to a value type without leaking
    // `Process`. `/bin/echo` keeps it deterministic and bounded. (SPEC §3.2)
    @Test func processCommandRunner_capturesRealStdoutAndExitCode() async throws {
        let runner = ProcessCommandRunner()

        let output = try await runner.run("/bin/echo", arguments: ["hi"])

        #expect(output.stdout == "hi\n")
        #expect(output.exitCode == 0)
    }
}
