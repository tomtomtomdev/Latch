import Darwin

/// Real `ProcessLister` backed by libproc. Enumerates all pids (`proc_listpids`),
/// then for each reads its owning UID (`proc_pidinfo(PROC_PIDTBSDINFO)`) and executable
/// path (`proc_pidpath`). The same-UID filter lives in the discovery; this only reports
/// what the kernel says. C types stay inside this adapter. (SPEC §3.2; PLAN slice 1)
///
/// Verified against the macOS SDK headers (`libproc.h`, `<sys/proc_info.h>`): UID comes
/// from `proc_bsdinfo.pbi_uid`; paths cap at `PROC_PIDPATHINFO_MAXSIZE`. (SPEC §7)
public struct LibprocProcessLister: ProcessLister {
    public init() {}

    public var currentUID: UInt32 { getuid() }

    public func listProcesses() throws -> [ProcessEntry] {
        allPIDs().compactMap(entry(for:))
    }

    /// All process identifiers, sized by a probing call then read into an exact buffer.
    private func allPIDs() -> [pid_t] {
        let probe = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard probe > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(probe) / MemoryLayout<pid_t>.stride)
        let written = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard written > 0 else { return [] }
        return Array(pids.prefix(Int(written) / MemoryLayout<pid_t>.stride))
    }

    private func entry(for pid: pid_t) -> ProcessEntry? {
        guard pid > 0, let uid = uid(of: pid) else { return nil }
        return ProcessEntry(pid: pid, uid: uid, executablePath: path(of: pid))
    }

    private func uid(of pid: pid_t) -> UInt32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard read == size else { return nil }
        return info.pbi_uid
    }

    private func path(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Self.pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : ""
    }

    // `PROC_PIDPATHINFO_MAXSIZE` (== 4 * MAXPATHLEN) is not exposed to Swift, so the
    // value is reconstructed from `MAXPATHLEN` to match `<sys/proc_info.h>`. (SPEC §7)
    private static let pathBufferSize = 4 * Int(MAXPATHLEN)
}
