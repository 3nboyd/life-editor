import Foundation

public enum MulticamSwitchMode:String,Codable,CaseIterable,Sendable { case video,audio,both }
public enum MulticamSwitching {
    /// Explicit silence when a range resumes a group which has no master audio.
    public static let silenceAudioID=UUID(uuidString:"00000000-0000-0000-0000-000000000000")!
    public static func selectedAudio(in group:MulticamGroup,at time:RationalTime)->UUID? {
        let selected=(group.audioCuts ?? []).filter{$0.time<=time}.max{$0.time<$1.time}?.angleID ?? group.masterAudioAssetID
        return selected == silenceAudioID ? nil : selected
    }
    public static func applying(angleID:UUID,at time:RationalTime,mode:MulticamSwitchMode,to group:MulticamGroup,frameRate:FrameRate,availableAudioAssetIDs:Set<UUID>) throws -> MulticamGroup {
        guard group.angleAssetIDs.contains(angleID),time >= .zero else {throw DocumentError.invalidTiming}
        if mode != .video && !availableAudioAssetIDs.contains(angleID) {throw DocumentError.sourceBoundary}
        let time=frameRate.quantized(time)
        var result=group
        func inserting(_ prior:[MulticamCut])->[MulticamCut] {
            var cuts=prior
            if let index=cuts.firstIndex(where:{$0.time==time}) {cuts[index].angleID=angleID}
            else {cuts.append(.init(time:time,angleID:angleID))}
            return cuts.sorted{$0.time<$1.time}
        }
        if mode != .audio, (result.cuts.filter{$0.time<=time}.max{$0.time<$1.time}?.angleID ?? result.angleAssetIDs.first) != angleID {result.cuts=inserting(result.cuts)}
        if mode != .video, selectedAudio(in:result,at:time) != angleID {result.audioCuts=inserting(result.audioCuts ?? [])}
        return result
    }
    public static func replacingAudioCuts(in group:MulticamGroup,from start:RationalTime,to end:RationalTime,with decisions:[MulticamCut]) throws -> MulticamGroup {
        let allowed=Set(group.angleAssetIDs + [group.masterAudioAssetID,silenceAudioID].compactMap{$0})
        guard start >= .zero,end>start,decisions.allSatisfy({$0.time>=start && $0.time<end && allowed.contains($0.angleID)}),Set(decisions.map(\.time)).count==decisions.count else {throw DocumentError.invalidTiming}
        let original=group.audioCuts ?? []
        let initial=selectedAudio(in:group,at:start) ?? silenceAudioID
        let resumed=selectedAudio(in:group,at:end) ?? silenceAudioID
        var inside=decisions
        if !inside.contains(where:{$0.time==start}) {inside.append(.init(time:start,angleID:initial))}
        var result=group
        result.audioCuts=original.filter{$0.time<start || $0.time>=end}+inside
        if !result.audioCuts!.contains(where:{$0.time==end}) {result.audioCuts!.append(.init(time:end,angleID:resumed))}
        result.audioCuts!.sort{$0.time<$1.time}
        return result
    }
}
