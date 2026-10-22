import Foundation

public struct FreezeFrameContent:Codable,Equatable,Sendable {
    public var sourceTime:RationalTime
    public var effectTimeOffset:RationalTime
    public init(sourceTime:RationalTime,effectTimeOffset:RationalTime = .zero){self.sourceTime=sourceTime;self.effectTimeOffset=effectTimeOffset}
}
public enum FreezeFrameEditing {
    public static func extending(clipID:UUID,duration:RationalTime,sourceFrameTime:RationalTime,in document:ProjectDocument)throws->ProjectDocument {
        try document.validate();var next=document
        guard let t=next.sequence.tracks.firstIndex(where:{$0.clips.contains{$0.id==clipID}}),let original=next.sequence.tracks[t].clips.first(where:{$0.id==clipID}) else{throw DocumentError.clipNotFound}
        guard !next.sequence.tracks[t].isLocked else{throw DocumentError.lockedTrack}
        guard next.sequence.tracks[t].kind != .audio,original.freezeFrame == nil,original.title == nil,original.graphic == nil,let asset=next.assets.first(where:{$0.id==original.assetID}),asset.kind == .video else{throw DocumentError.sourceBoundary}
        guard !document.sequence.multicamGroups.contains(where:{$0.angleAssetIDs.contains(asset.id) || $0.masterAudioAssetID==asset.id || ($0.audioAssetIDs?.contains(asset.id) ?? false)}) else{throw DocumentError.sourceBoundary}
        let sourceEnd=try original.checkedSourceTime(at:original.end),remaining=try asset.duration.checkedSubtracting(sourceEnd)
        let nextFrame=try document.sequence.settings.frameRate.frameDuration.checkedScaled(by:Int64((original.speed*1_000_000).rounded()),over:1_000_000)
        guard remaining >= .zero,remaining<nextFrame,sourceFrameTime >= .zero,sourceFrameTime<asset.duration else{throw DocumentError.sourceBoundary}
        let length=try document.sequence.settings.frameRate.checkedQuantized(duration)
        guard length > .zero else{throw DocumentError.invalidTiming}
        var frozen=original;frozen.id=UUID();frozen.name=original.name+" · Freeze";frozen.start=original.end;frozen.duration=length;frozen.sourceStart=sourceFrameTime;frozen.speed=1;frozen.audioEnabled=false;frozen.audio=nil;frozen.linkID=nil;frozen.groupID=nil
        frozen.freezeFrame=FreezeFrameContent(sourceTime:sourceFrameTime,effectTimeOffset:original.duration)
        frozen.opacity=original.opacity;frozen.opacity.evaluationOffset=try original.opacity.evaluationOffset.checkedAdding(original.duration)
        frozen.volume=AutomationEnvelope(baseValue:0)
        next.sequence.tracks[t].clips.append(frozen);try next.validate();return next
    }
}
