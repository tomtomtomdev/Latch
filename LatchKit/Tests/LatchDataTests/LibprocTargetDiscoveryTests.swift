import Testing
import LatchDomain
@testable import LatchData

struct LibprocTargetDiscoveryTests {
    // Slice 1: enumerated entries map to local-Mac targets, deriving a display name
    // from the executable's last path component and carrying the pid. (PLAN slice 1)
    @Test func localProcesses_mapsEntriesToLocalMacTargets() async throws {
        let lister = FakeProcessLister(currentUID: 501, entries: [
            ProcessEntry(pid: 42, uid: 501, executablePath: "/usr/bin/foo"),
            ProcessEntry(pid: 73, uid: 501, executablePath: "/Applications/Bar.app/Contents/MacOS/Bar"),
        ])
        let discovery = LibprocTargetDiscovery(lister: lister)

        let targets = try await discovery.localProcesses()

        #expect(targets.map(\.pid) == [42, 73])
        #expect(targets.map(\.displayName) == ["foo", "Bar"])
        #expect(targets.allSatisfy { $0.kind == .localMac })
    }

    // The hard constraint from SPEC §1: only same-UID processes are attachable, so
    // discovery must drop every pid owned by another user. (SPEC §1; PLAN slice 1)
    @Test func localProcesses_filtersOutOtherUIDProcesses() async throws {
        let lister = FakeProcessLister(currentUID: 501, entries: [
            ProcessEntry(pid: 1, uid: 0, executablePath: "/sbin/launchd"),
            ProcessEntry(pid: 42, uid: 501, executablePath: "/usr/bin/mine"),
            ProcessEntry(pid: 99, uid: 88, executablePath: "/usr/sbin/other"),
        ])
        let discovery = LibprocTargetDiscovery(lister: lister)

        let targets = try await discovery.localProcesses()

        #expect(targets.map(\.pid) == [42])
    }

    // An entry with no resolvable executable path is skipped — a nameless target is
    // not something the user can meaningfully pick. (PLAN slice 1)
    @Test func localProcesses_skipsEntriesWithoutAPath() async throws {
        let lister = FakeProcessLister(currentUID: 501, entries: [
            ProcessEntry(pid: 42, uid: 501, executablePath: ""),
            ProcessEntry(pid: 73, uid: 501, executablePath: "/usr/bin/keep"),
        ])
        let discovery = LibprocTargetDiscovery(lister: lister)

        let targets = try await discovery.localProcesses()

        #expect(targets.map(\.pid) == [73])
    }
}
