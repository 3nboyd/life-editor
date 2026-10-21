import Foundation

public enum TitleAnimationKind: String, Codable, CaseIterable, Sendable {
    case fade, slide, pop, scale, bounce, typewriter
}

/// Original entrance animation. Its rational clock follows content through trims,
/// splits and retiming; moving a clip never restarts an already-trimmed entrance.
/// Exit and word-highlight animations are separate future additions.
public struct TitleAnimation: Codable, Equatable, Sendable {
    public var kind: TitleAnimationKind
    public var duration: Double
    public var evaluationOffset: RationalTime
    public var timeScale: RationalTime
    /// Slide entry: 0 right, 1 left, 2 bottom, 3 top.
    public var direction: Int
    public init(kind: TitleAnimationKind, duration: Double = 0.5, evaluationOffset: RationalTime = .zero,
                timeScale: RationalTime = .init(value: 1, timescale: 1), direction: Int = 0) {
        self.kind=kind; self.duration=duration; self.evaluationOffset=evaluationOffset; self.timeScale=timeScale; self.direction=direction
    }
    public var isValid: Bool {
        duration.isFinite && (0.05...10).contains(duration) && (0...3).contains(direction) &&
        timeScale.value > 0 && timeScale.timescale <= 1_000_000_000 && timeScale.seconds.isFinite && (0.0001...10000).contains(timeScale.seconds) &&
        evaluationOffset.timescale <= 1_000_000_000 && evaluationOffset.seconds.isFinite && abs(evaluationOffset.seconds) <= 86400
    }
    public func elapsedTime(at localTime: RationalTime) throws -> RationalTime {
        try localTime.checkedScaled(by: timeScale.value, over: timeScale.timescale).checkedAdding(evaluationOffset)
    }
    public func windowed(by delta: RationalTime) throws -> Self {
        var result=self; result.evaluationOffset=try elapsedTime(at:delta); return result
    }
    public func retimed(by numerator: Int64, over denominator: Int64) throws -> Self {
        var result=self; result.timeScale=try timeScale.checkedScaled(by:numerator,over:denominator); return result
    }
}
