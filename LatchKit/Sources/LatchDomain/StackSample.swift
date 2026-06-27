// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// One snapshot of a thread's call stack at a sampling instant, outermost-first
/// (`frames.first` is the entry point, `frames.last` is the leaf — what the thread was
/// actually doing). A series of these from a fixed-interval sampler is what the hang
/// heuristic scans for stalls. (SPEC §3.3; PLAN slice 8)
public struct StackSample: Sendable, Equatable {
    public let frames: [String]

    public init(frames: [String]) {
        self.frames = frames
    }

    /// The leaf frame — the deepest frame, where the thread was executing (or blocked).
    public var leaf: String? { frames.last }
}
