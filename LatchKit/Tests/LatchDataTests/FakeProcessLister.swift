import LatchData

/// Test double: hands back canned process entries and a fixed current UID so
/// discovery tests exercise the same-UID filter without touching libproc. (SPEC §6)
struct FakeProcessLister: ProcessLister {
    let currentUID: UInt32
    let entries: [ProcessEntry]

    func listProcesses() throws -> [ProcessEntry] {
        entries
    }
}
