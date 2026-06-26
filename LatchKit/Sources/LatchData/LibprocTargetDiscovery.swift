import LatchDomain

/// Discovers attachable local targets by enumerating same-UID processes and mapping
/// them to Domain `Target`s. The same-UID filter enforces SPEC §1: a debugger-entitled
/// tool can only attach to the current user's processes. (SPEC §1, §3.2; PLAN slice 1)
public struct LibprocTargetDiscovery: TargetDiscovery {
    private let lister: ProcessLister

    public init(lister: ProcessLister) {
        self.lister = lister
    }

    public func localProcesses() async throws -> [Target] {
        let ownUID = lister.currentUID
        return try lister.listProcesses()
            .filter { $0.uid == ownUID }
            .compactMap(Self.target(from:))
    }

    private static func target(from entry: ProcessEntry) -> Target? {
        guard let name = displayName(forPath: entry.executablePath) else { return nil }
        return Target(
            id: String(entry.pid),
            kind: .localMac,
            pid: entry.pid,
            displayName: name
        )
    }

    /// The executable's last path component, or `nil` when the path is empty.
    private static func displayName(forPath path: String) -> String? {
        path.split(separator: "/").last.map(String.init)
    }
}
