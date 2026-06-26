// LatchData — adapters and system I/O. Depends only on LatchDomain. (SPEC §3.2)

/// A raw process record as read from libproc, before mapping to a Domain `Target`.
/// `proc_*` types do not escape the adapter — this value type is the Data-layer seam.
/// (SPEC §3.2)
public struct ProcessEntry: Sendable, Equatable {
    public let pid: Int32
    public let uid: UInt32
    public let executablePath: String

    public init(pid: Int32, uid: UInt32, executablePath: String) {
        self.pid = pid
        self.uid = uid
        self.executablePath = executablePath
    }
}

/// Abstraction over enumerating local processes via libproc (`proc_listpids`,
/// `proc_pidpath`, `proc_pidinfo`). Behind a protocol so discovery's same-UID filter
/// and name mapping are tested with canned entries instead of the live kernel.
/// (SPEC §6; PLAN slice 1)
public protocol ProcessLister: Sendable {
    /// The UID of the current user — the only processes that are attachable. (SPEC §1)
    var currentUID: UInt32 { get }
    func listProcesses() throws -> [ProcessEntry]
}
