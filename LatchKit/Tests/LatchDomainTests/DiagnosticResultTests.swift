import Testing
import LatchDomain

struct DiagnosticResultTests {
    private func finding(_ title: String, backtrace: [String] = []) -> Finding {
        Finding(title: title, byteCount: 16, instanceCount: 1, backtrace: backtrace)
    }

    // A leak report with at least one backtraced finding knows its backtraces are present —
    // the UI uses this to decide whether to show the MallocStackLogging caveat. (PLAN slice 6)
    @Test func hasBacktraces_isTrue_whenAnyFindingCarriesAStack() {
        let result = DiagnosticResult(
            kind: .leaks,
            summary: "1 leak for 16 total leaked bytes",
            findings: [finding("ROOT LEAK: <malloc in foo>", backtrace: ["0 libfoo bar + 1"])]
        )

        #expect(result.hasBacktraces)
    }

    // Leaks found without launch-time MallocStackLogging carry no stacks — the report reports
    // that honestly so the UI can tell the user how to get backtraces. (SPEC §1)
    @Test func hasBacktraces_isFalse_whenLeaksHaveNoStacks() {
        let result = DiagnosticResult(
            kind: .leaks,
            summary: "4 leaks for 416 total leaked bytes",
            findings: [finding("0x102d29b60"), finding("0xb6ec00940")]
        )

        #expect(!result.hasBacktraces)
        #expect(result.hasFindings)
    }

    // A clean run carries no findings at all — distinct from "leaks without stacks".
    @Test func hasFindings_isFalse_forACleanRun() {
        let result = DiagnosticResult(kind: .leaks, summary: "0 leaks for 0 total leaked bytes", findings: [])

        #expect(!result.hasFindings)
        #expect(!result.hasBacktraces)
    }
}
