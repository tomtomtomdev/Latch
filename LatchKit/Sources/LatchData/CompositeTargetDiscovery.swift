import LatchDomain

/// Fuses several single-purpose `TargetDiscovery` adapters into one the picker can depend on:
/// `LibprocTargetDiscovery` serves local processes, `DevicectlTargetDiscovery` serves iOS
/// devices, and each falls through to the protocol's empty defaults for the kinds it doesn't
/// serve. Results are concatenated in source order. (SPEC §3.1, §3.2; PLAN slices 1, 9)
public struct CompositeTargetDiscovery: TargetDiscovery {
    private let sources: [TargetDiscovery]

    public init(_ sources: [TargetDiscovery]) {
        self.sources = sources
    }

    public func localProcesses() async throws -> [Target] {
        try await merge { try await $0.localProcesses() }
    }

    public func devices() async throws -> [Device] {
        try await merge { try await $0.devices() }
    }

    public func apps(on device: Device) async throws -> [Target] {
        try await merge { try await $0.apps(on: device) }
    }

    private func merge<Element>(
        _ each: (TargetDiscovery) async throws -> [Element]
    ) async rethrows -> [Element] {
        var merged: [Element] = []
        for source in sources {
            merged += try await each(source)
        }
        return merged
    }
}
