// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A detected main-thread stall: the thread sat in one unchanged `stack` across a run of
/// consecutive samples long enough to be a hitch/hang. An *honest hint*, not proof — a main
/// thread legitimately parked in its run loop waiting for events presents the same way, so
/// the leaf frame is surfaced (a blocking syscall vs. compute reads very differently) and the
/// deep trace is the ground truth. (SPEC §1, §3.3; PLAN slice 8)
public struct Hang: Sendable, Equatable {
    /// The wedged call stack, outermost-first.
    public let stack: [String]
    /// How many consecutive samples shared this stack.
    public let sampleCount: Int
    /// `sampleCount × samplingInterval` — how long the stall lasted.
    public let duration: Duration

    public init(stack: [String], sampleCount: Int, duration: Duration) {
        self.stack = stack
        self.sampleCount = sampleCount
        self.duration = duration
    }

    /// The leaf frame — where the thread was wedged.
    public var leaf: String { stack.last ?? "" }
}
