import LifeCore

extension EditorStore {
    var selectedCaptionTrack:Track? {
        document.sequence.tracks.first{$0.kind == .caption && $0.clips.contains{$0.id==selection}}
    }
    func applyCaptionPreset(_ preset:CaptionPreset){
        guard selectedCaptionTrack != nil,let clip=selectedClip else{return}
        do{let styled=try preset.applying(to:clip,canvasHeight:document.sequence.settings.height);editSelected{$0=styled}}
        catch{self.error=Self.message(error)}
    }
    /// Match appearance only. Words, cue times, entrance clocks, effects and
    /// envelopes remain individual; the entire track change undoes once.
    func matchCaptionTrackStyle(){
        guard let track=selectedCaptionTrack,let title=selectedClip?.title else{return}
        guard !track.isLocked else{error="Unlock the track to edit.";return}
        var next=document
        guard let index=next.sequence.tracks.firstIndex(where:{$0.id==track.id}) else{return}
        for clip in next.sequence.tracks[index].clips.indices where next.sequence.tracks[index].clips[clip].title != nil {
            next.sequence.tracks[index].clips[clip].title?.style=title.style
            next.sequence.tracks[index].clips[clip].title?.fontSize=title.fontSize
        }
        replace(next)
    }
}
