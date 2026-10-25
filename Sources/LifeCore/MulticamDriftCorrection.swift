import Foundation

public struct DriftAnchor:Equatable,Sendable {
    public var sourceSeconds:Double
    public var referenceSeconds:Double
    public var confidence:Double
    public var uncertaintySeconds:Double
    public init(sourceSeconds:Double,referenceSeconds:Double,confidence:Double,uncertaintySeconds:Double){self.sourceSeconds=sourceSeconds;self.referenceSeconds=referenceSeconds;self.confidence=confidence;self.uncertaintySeconds=uncertaintySeconds}
    var isValid:Bool{[sourceSeconds,referenceSeconds,confidence,uncertaintySeconds].allSatisfy(\.isFinite) && (0...86400).contains(sourceSeconds) && (0...86400).contains(referenceSeconds) && (0.6...1).contains(confidence) && (0...1).contains(uncertaintySeconds)}
}
public enum DriftCorrectionError:LocalizedError,Equatable {
    case unreliable,nonlinear,unsupportedContext,negativePreroll,invalidRange
    public var errorDescription:String?{switch self{
    case .unreliable:return "Use clear, separated synchronization anchors."
    case .nonlinear:return "Clock drift is inconsistent. Align this recording manually."
    case .unsupportedContext:return "Correct an unretimed camera in one multicam group with no external links, groups, or transitions."
    case .negativePreroll:return "Correction starts before zero. Trim the camera preroll and analyze again."
    case .invalidRange:return "Correction exceeds the available recording or project timing limits."
    }}
}
public struct AffineDriftCorrection:Equatable,Sendable {
    /// referenceSourceSeconds = sourceOrigin + targetSourceSeconds / speed.
    public let sourceOrigin:Double
    public let speed:Double
    public let confidence:Double
    public let uncertaintySeconds:Double
    public let maxResidualSeconds:Double
    public let early:DriftAnchor
    public let middle:DriftAnchor
    public let late:DriftAnchor
    public static func fit(early:DriftAnchor,middle:DriftAnchor,late:DriftAnchor)throws->Self {
        guard early.isValid,middle.isValid,late.isValid,late.sourceSeconds-early.sourceSeconds>=120,
              middle.sourceSeconds>early.sourceSeconds,middle.sourceSeconds<late.sourceSeconds else{throw DriftCorrectionError.unreliable}
        let slope=(late.referenceSeconds-early.referenceSeconds)/(late.sourceSeconds-early.sourceSeconds)
        guard slope.isFinite,(0.99...1.01).contains(slope) else{throw DriftCorrectionError.unreliable}
        let speed=(1/slope*1_000_000).rounded()/1_000_000
        let origin=early.referenceSeconds-early.sourceSeconds/speed
        let residual=max(abs(origin+middle.sourceSeconds/speed-middle.referenceSeconds),abs(origin+late.sourceSeconds/speed-late.referenceSeconds))
        let uncertainty=max(early.uncertaintySeconds,middle.uncertaintySeconds,late.uncertaintySeconds)
        guard residual<=max(0.04,2*uncertainty) else{throw DriftCorrectionError.nonlinear}
        return .init(sourceOrigin:origin,speed:speed,confidence:min(early.confidence,middle.confidence,late.confidence),uncertaintySeconds:uncertainty,maxResidualSeconds:residual,early:early,middle:middle,late:late)
    }
}
public struct DriftCorrectionProposal:Sendable {
    public let document:ProjectDocument
    public let trimmedPrerollSeconds:Double
}
public enum MulticamDriftCorrection {
    public static func applying(_ correction:AffineDriftCorrection,to assetID:UUID,referenceID:UUID,in document:ProjectDocument,offsetAdjustmentSeconds:Double=0)throws->DriftCorrectionProposal {
        try document.validate()
        guard offsetAdjustmentSeconds.isFinite,abs(offsetAdjustmentSeconds)<=86400 else{throw DriftCorrectionError.invalidRange}
        let groups=document.sequence.multicamGroups.filter{$0.angleAssetIDs.contains(assetID) || $0.masterAudioAssetID==assetID || ($0.audioAssetIDs?.contains(assetID) ?? false)}
        guard groups.count==1,let group=groups.first,group.angleAssetIDs.contains(assetID),group.masterAudioAssetID==referenceID,referenceID != assetID,
              let source=document.assets.first(where:{$0.id==assetID}),source.kind == .video,
              let referenceAsset=document.assets.first(where:{$0.id==referenceID}) else{throw DriftCorrectionError.unsupportedContext}
        let targetTracks=document.sequence.tracks.filter{$0.clips.contains(where:{$0.assetID==assetID})}
        let referenceTracks=document.sequence.tracks.filter{$0.clips.contains(where:{$0.assetID==referenceID})}
        guard targetTracks.count==1,targetTracks[0].kind == .video,referenceTracks.count==1 else{throw DriftCorrectionError.unsupportedContext}
        guard [correction.early,correction.middle,correction.late].allSatisfy({$0.sourceSeconds<=source.duration.seconds && $0.referenceSeconds<=referenceAsset.duration.seconds}) else{throw DriftCorrectionError.invalidRange}
        let all=document.sequence.tracks.flatMap(\.clips),targets=all.filter{$0.assetID==assetID},references=all.filter{$0.assetID==referenceID}
        guard !targets.isEmpty,!references.isEmpty,targets.allSatisfy({$0.speed==1 && $0.freezeFrame==nil}),references.allSatisfy({$0.speed==1 && $0.freezeFrame==nil}),
              let reference=references.min(by:{$0.start<$1.start}) else{throw DriftCorrectionError.unsupportedContext}
        let ids=Set(targets.map(\.id)),links=Set(targets.compactMap(\.linkID)),memberships=Set(targets.compactMap(\.groupID))
        guard !all.contains(where:{!ids.contains($0.id) && (($0.linkID.map(links.contains) ?? false) || ($0.groupID.map(memberships.contains) ?? false))}),
              !(document.sequence.transitions ?? []).contains(where:{ids.contains($0.leftClipID) || ids.contains($0.rightClipID)}) else{throw DriftCorrectionError.unsupportedContext}
        let originTolerance=0.5/Double(document.sequence.settings.audioSampleRate)
        let referenceOrigin=reference.start.seconds-reference.sourceStart.seconds
        guard references.allSatisfy({abs(($0.start.seconds-$0.sourceStart.seconds)-referenceOrigin)<=originTolerance}) else{throw DriftCorrectionError.unsupportedContext}
        let originalOrigin=targets[0].start.seconds-targets[0].sourceStart.seconds
        guard targets.allSatisfy({abs(($0.start.seconds-$0.sourceStart.seconds)-originalOrigin)<=originTolerance}) else{throw DriftCorrectionError.unsupportedContext}
        let rate=Int64((correction.speed*1_000_000).rounded())
        let firstSource=targets.map(\.sourceStart).min()!
        var relative:[UUID:RationalTime]=[:],durations:[UUID:RationalTime]=[:]
        for clip in targets {
            relative[clip.id]=try clip.sourceStart.checkedSubtracting(firstSource).checkedScaled(by:1_000_000,over:rate)
            durations[clip.id]=try clip.duration.checkedScaled(by:1_000_000,over:rate)
        }
        let grid=try DriftTimingGrid.scale(for:Array(relative.values)+Array(durations.values),sampleRate:document.sequence.settings.audioSampleRate)
        let anchorSeconds=referenceOrigin+correction.sourceOrigin+firstSource.seconds/correction.speed+offsetAdjustmentSeconds
        guard anchorSeconds>=0 else{throw DriftCorrectionError.negativePreroll}
        let anchor=try DriftTimingGrid.time(seconds:anchorSeconds,scale:grid)
        var result=document
        func retime(_ envelope:AutomationEnvelope)throws->AutomationEnvelope {
            var value=envelope;value.evaluationOffset=try envelope.evaluationOffset.checkedScaled(by:1_000_000,over:rate)
            for index in value.points.indices{value.points[index].time=try value.points[index].time.checkedScaled(by:1_000_000,over:rate)}
            return value
        }
        for track in result.sequence.tracks.indices where result.sequence.tracks[track].clips.contains(where:{ids.contains($0.id)}) {
            guard !result.sequence.tracks[track].isLocked else{throw DocumentError.lockedTrack}
            guard [.video,.audio].contains(result.sequence.tracks[track].kind),result.sequence.tracks[track].clips.allSatisfy({$0.assetID==assetID}) else{throw DriftCorrectionError.unsupportedContext}
            for index in result.sequence.tracks[track].clips.indices {
                var clip=result.sequence.tracks[track].clips[index]
                let sourceEnd=try clip.sourceStart.checkedAdding(clip.duration)
                guard sourceEnd<=source.duration else{throw DriftCorrectionError.invalidRange}
                clip.start=try anchor.checkedAdding(relative[clip.id]!)
                clip.duration=durations[clip.id]!
                clip.volume=try retime(clip.volume);clip.opacity=try retime(clip.opacity)
                clip.speed=correction.speed
                guard try clip.sourceStart.checkedAdding(clip.duration.checkedScaled(by:rate,over:1_000_000))<=source.duration else{throw DriftCorrectionError.invalidRange}
                result.sequence.tracks[track].clips[index]=clip
            }
        }
        try result.validate()
        return .init(document:result,trimmedPrerollSeconds:0)
    }
}
