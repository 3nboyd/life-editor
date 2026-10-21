import Foundation

public enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case crossDissolve, fadeBlack, fadeWhite, dipColor, push, slide, wipe, zoom, blur, whipPan, shake, glitch, flash, lightLeak
}
public struct VideoTransition: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID; public var kind: TransitionKind; public var trackID: UUID; public var leftClipID: UUID; public var rightClipID: UUID
    public var duration: RationalTime; public var color: RGBAColor; public var direction: Int; public var isEnabled: Bool
    public init(id: UUID = UUID(), kind: TransitionKind, trackID: UUID, leftClipID: UUID, rightClipID: UUID, duration: RationalTime, color: RGBAColor = .black, direction: Int = 0, isEnabled: Bool = true) { self.id=id; self.kind=kind; self.trackID=trackID; self.leftClipID=leftClipID; self.rightClipID=rightClipID; self.duration=duration; self.color=color; self.direction=direction; self.isEnabled=isEnabled }
}
public struct ResolvedTransition: Sendable {
    public let transition: VideoTransition; public let left: Clip; public let right: Clip
    public let start: RationalTime; public let end: RationalTime; public let center: RationalTime
}
public enum TransitionResolver {
    /// Maximum centered duration from source handles, clip bounds and neighboring transition windows.
    public static func availableDuration(leftClipID: UUID, rightClipID: UUID, in document: ProjectDocument, excluding transitionID: UUID? = nil) throws -> RationalTime {
        let (track,left,right)=try pair(leftClipID,rightClipID,in:document)
        var half=min(left.duration,right.duration)
        for (clip,isLeft) in [(left,true),(right,false)] {
            if let assetID=clip.assetID {
                guard let asset=document.assets.first(where: { $0.id == assetID }) else { throw DocumentError.sourceBoundary }
                if asset.kind == .image { continue }
                let sourceMargin=isLeft ? try asset.duration.checkedSubtracting(clip.checkedSourceTime(at:clip.end)) : clip.sourceStart
                let rate=Int64((clip.speed*1_000_000).rounded())
                let margin=try sourceMargin.checkedScaled(by:1_000_000,over:rate)
                half=min(half,max(.zero,margin))
            } else if clip.title == nil && clip.graphic == nil { throw DocumentError.sourceBoundary }
        }
        for other in document.sequence.transitions ?? [] where other.id != transitionID && other.isEnabled && other.trackID == track.id {
            guard let (_,otherLeft,_)=try? pair(other.leftClipID,other.rightClipID,in:document) else { continue }
            let distance=left.end >= otherLeft.end ? try left.end.checkedSubtracting(otherLeft.end) : try otherLeft.end.checkedSubtracting(left.end)
            let remaining=try distance.checkedSubtracting(other.duration.checkedScaled(by:1,over:2))
            half=min(half,max(.zero,remaining))
        }
        let maximum=try half.checkedScaled(by:2)
        let rate=document.sequence.settings.frameRate
        let frames=try maximum.checkedScaled(by:rate.numerator,over:rate.denominator)
        return rate.time(forFrame:frames.value/frames.timescale)
    }
    /// Disabled, orphaned and newly invalid transitions remain serialized but do not render.
    public static func resolve(_ transition: VideoTransition, in document: ProjectDocument) -> ResolvedTransition? {
        guard transition.isEnabled, transition.duration > .zero,
              let (track,left,right)=try? pair(transition.leftClipID,transition.rightClipID,in:document), track.id == transition.trackID,
              let maximum=try? availableDuration(leftClipID:left.id,rightClipID:right.id,in:document,excluding:transition.id), transition.duration <= maximum,
              let half=try? transition.duration.checkedScaled(by:1,over:2), let start=try? left.end.checkedSubtracting(half), let end=try? left.end.checkedAdding(half) else { return nil }
        return ResolvedTransition(transition:transition,left:left,right:right,start:start,end:end,center:left.end)
    }
    static func pair(_ leftID: UUID, _ rightID: UUID, in document: ProjectDocument) throws -> (Track,Clip,Clip) {
        guard let track=document.sequence.tracks.first(where: { $0.clips.contains { $0.id == leftID } }), track.kind != .audio,
              let left=track.clips.first(where: { $0.id == leftID }), let right=track.clips.first(where: { $0.id == rightID }) else { throw DocumentError.clipNotFound }
        guard left.id != right.id, left.end == right.start else { throw DocumentError.invalidSplit }
        return (track,left,right)
    }
}
