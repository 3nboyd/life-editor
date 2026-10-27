import Foundation
import LifeCore

struct MulticamCutProposal:Sendable {
    let baseline:ProjectDocument
    let document:ProjectDocument
    let cutID:UUID
    let audio:Bool
    let time:RationalTime
}
private struct CutEditFailure:LocalizedError {
    let message:String
    var errorDescription:String? {message}
}

extension EditorStore {
    var canRefineMulticamCuts:Bool { !playing && !switchArmed && !checkingCameraAudio && placementProposal == nil }
    private func requireCutEditing() throws {
        guard canRefineMulticamCuts else {throw CutEditFailure(message:"Stop and disarm switching; finish the current preview first.")}
    }
    /// Pure document proposal: pointer movement never commits edits or starts an undo gesture.
    func proposeMulticamCut(_ id:UUID,audio:Bool,seconds:Double?,assetID:UUID? = nil,baseline:ProjectDocument) throws -> MulticamCutProposal {
        try requireCutEditing()
        guard document==baseline, var group=baseline.sequence.multicamGroups.last else{throw CutEditFailure(message:"The project changed. Drag the cut again.")}
        var cuts=(audio ? group.audioCuts ?? []:group.cuts).sorted{$0.time<$1.time}
        guard let index=cuts.firstIndex(where:{$0.id==id}) else{throw CutEditFailure(message:"This cut is no longer available.")}
        let original=cuts[index]
        if let seconds {
            guard seconds.isFinite,seconds>=0,seconds<baseline.sequence.duration.seconds else{throw CutEditFailure(message:"Keep cuts inside the sequence.")}
            let position=try baseline.sequence.settings.frameRate.checkedQuantized(time(seconds,audio:true))
            guard position<baseline.sequence.duration else{throw CutEditFailure(message:"Keep cuts inside the sequence.")}
            guard original.time != .zero || position == .zero else{throw CutEditFailure(message:"The opening cut stays at zero.")}
            guard (index==0 || cuts[index-1].time<position),(index+1==cuts.count || position<cuts[index+1].time) else{throw CutEditFailure(message:"Keep this cut between its neighbors.")}
            cuts[index].time=position
        }
        if let assetID {cuts[index].angleID=assetID}
        if cuts[index]==original{return MulticamCutProposal(baseline:baseline,document:baseline,cutID:id,audio:audio,time:original.time)}
        try validateCutSources(cuts,group:group,audio:audio,in:baseline)
        if audio{group.audioCuts=cuts}else{group.cuts=cuts}
        var next=baseline;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1]=group
        try next.validate()
        return MulticamCutProposal(baseline:baseline,document:next,cutID:id,audio:audio,time:cuts[index].time)
    }
    @discardableResult func commitMulticamCut(_ proposal:MulticamCutProposal)->Bool {
        do {
            let verified=try proposeMulticamCut(proposal.cutID,audio:proposal.audio,seconds:proposal.time.seconds,assetID:(proposal.audio ? proposal.document.sequence.multicamGroups.last?.audioCuts:proposal.document.sequence.multicamGroups.last?.cuts)?.first(where:{$0.id==proposal.cutID})?.angleID,baseline:proposal.baseline)
            guard verified.document==proposal.document else{throw CutEditFailure(message:"The cut preview changed. Try again.")}
            if document != proposal.document {replace(proposal.document)}
            return document==proposal.document
        } catch {self.error=Self.message(error);return false}
    }
    func editMulticamCut(_ id:UUID,audio:Bool,seconds:Double?,assetID:UUID?){
        do{let proposal=try proposeMulticamCut(id,audio:audio,seconds:seconds,assetID:assetID,baseline:document);_ = commitMulticamCut(proposal)}catch{self.error=Self.message(error)}
    }
    func removeMulticamCut(_ id:UUID,audio:Bool){
        do {
            try requireCutEditing()
            guard var group=multicamGroup else{return}
            var cuts=(audio ? group.audioCuts ?? []:group.cuts).sorted{$0.time<$1.time}
            guard let index=cuts.firstIndex(where:{$0.id==id}) else{return}
            guard cuts[index].time != .zero else{throw CutEditFailure(message:"The opening cut stays at zero.")}
                cuts.remove(at:index)
            try validateCutSources(cuts,group:group,audio:audio,in:document)
            if audio{group.audioCuts=cuts}else{group.cuts=cuts}
            var next=document;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1]=group;try next.validate();replace(next)
        }catch{self.error=Self.message(error)}
    }
    private func validateCutSources(_ cuts:[MulticamCut],group:MulticamGroup,audio:Bool,in baseline:ProjectDocument)throws {
        let tracks=baseline.sequence.tracks
        let oldCuts=(audio ? group.audioCuts ?? []:group.cuts).sorted{$0.time<$1.time}
        let initial=audio ? group.masterAudioAssetID:group.angleAssetIDs.first
        func selected(_ events:[MulticamCut],at time:RationalTime)->UUID? {events.last(where:{$0.time<=time})?.angleID ?? initial}
        let boundaries=Set((oldCuts+cuts).map(\.time)+[.zero,baseline.sequence.duration]).sorted()
        func requireCoverage(_ source:UUID?,from start:RationalTime,to end:RationalTime)throws {
            guard let source,source != MulticamSwitching.silenceAudioID else{return}
            guard audio ? cameraAudioIDs.contains(source):group.angleAssetIDs.contains(source) else{throw CutEditFailure(message:"This source is unavailable.")}
            var cursor=start
            for clip in tracks.flatMap(\.clips).filter({$0.assetID==source}).sorted(by:{$0.start<$1.start}) where clip.end>cursor && clip.start<=cursor {
                cursor=max(cursor,clip.end);if cursor>=end{break}
            }
            guard cursor>=end else{throw CutEditFailure(message:"This source is unavailable in the changed interval.")}
        }
        func requireUnlocked(_ sources:Set<UUID>,from start:RationalTime,to end:RationalTime)throws {
            guard !tracks.contains(where:{track in track.isLocked && track.clips.contains(where:{clip in
                guard let asset=clip.assetID,sources.contains(asset) else{return false}
                return clip.start<end && clip.end>start
            })}) else{throw CutEditFailure(message:"Unlock the affected source track first.")}
        }
        for (start,end) in zip(boundaries,boundaries.dropFirst()) where selected(oldCuts,at:start) != selected(cuts,at:start) {
            try requireUnlocked(Set([selected(oldCuts,at:start),selected(cuts,at:start)].compactMap{$0}),from:start,to:end)
            try requireCoverage(selected(cuts,at:start),from:start,to:end)
        }
        // A newly placed boundary must address an available source even if its neighbors
        // already select that source. Unchanged missing tails elsewhere remain editable.
        for cut in cuts where !oldCuts.contains(cut) && cut.angleID != MulticamSwitching.silenceAudioID {
            try requireUnlocked([cut.angleID],from:cut.time,to:try cut.time.checkedAdding(baseline.sequence.settings.frameRate.frameDuration))
            guard (!audio || cameraAudioIDs.contains(cut.angleID)),tracks.flatMap(\.clips).contains(where:{$0.assetID==cut.angleID && $0.start<=cut.time && cut.time<$0.end}) else{throw CutEditFailure(message:"This source is unavailable at the cut.")}
        }
    }
}
