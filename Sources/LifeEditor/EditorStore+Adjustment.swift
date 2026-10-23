import AppKit
import LifeCore

extension EditorStore {
    var selectedIsAdjustment:Bool{document.sequence.tracks.contains{$0.kind == .adjustment && $0.clips.contains{$0.id==selection}}}
    var selectionIncludesAdjustment:Bool{
        let ids=selectedIDs.union(selection.map{[$0]} ?? [])
        return document.sequence.tracks.contains{$0.kind == .adjustment && $0.clips.contains{ids.contains($0.id)}}
    }
    var selectedAcceptsVisualEffects:Bool {
        guard let clip=selectedClip else{return false}
        return selectedIsAdjustment || clip.title != nil || clip.graphic != nil || document.assets.contains{$0.id==clip.assetID && $0.kind != .audio}
    }
    func addAdjustmentLayer(){
        do{
            let start=try document.sequence.settings.frameRate.checkedQuantized(playheadTime)
            let remaining=try document.sequence.duration.checkedSubtracting(start)
            let frame=document.sequence.settings.frameRate.frameDuration
            let duration=remaining>=frame ? remaining:RationalTime(value:3,timescale:1)
            let oldIDs=Set(document.sequence.tracks.flatMap(\.clips).map(\.id))
            let candidate=try AdjustmentLayers.adding(at:start,duration:duration,in:document)
            replace(candidate)
            guard document==candidate,let added=document.sequence.tracks.flatMap(\.clips).first(where:{!oldIDs.contains($0.id)}) else{return}
            selectedTransition=nil;selection=added.id;automationLane = .opacity;selectedAutomationPoint=nil;panel = .effects
        }catch{self.error=error.localizedDescription}
    }
    func setAdjustmentDuration(_ seconds:Double){
        guard selectedIsAdjustment,let clip=selectedClip,seconds.isFinite,seconds>0,seconds<=86400 else{error="Enter a positive duration up to 24 hours.";return}
        do{let duration=try document.sequence.settings.frameRate.checkedQuantized(.init(value:Int64((seconds*48000).rounded()),timescale:48000));guard duration>=document.sequence.settings.frameRate.frameDuration else{error="Use at least one project frame.";return};apply(.trim(clipID:clip.id,start:clip.start,end:try clip.start.checkedAdding(duration)))}catch{self.error=error.localizedDescription}
    }
    func setEffectEnabled(id:UUID,enabled:Bool){editSelected{clip in if let index=clip.effects?.firstIndex(where:{$0.id==id}){clip.effects?[index].isEnabled=enabled}}}
    func resetAdjustments(){editSelected{$0.effects?.removeAll{$0.stableID.hasPrefix("life.adjust.")}}}
    static var effectSettingsPasteboardType:NSPasteboard.PasteboardType{.init("org.lifeeditor.effect-settings")}
    func copyEffectSettings(to pasteboard:NSPasteboard = .general){
        guard selectedAcceptsVisualEffects else{return}
        do{let data=try JSONEncoder().encode(EffectSettingsClipboard(effects:selectedClip?.effects ?? []));pasteboard.clearContents();guard pasteboard.setData(data,forType:Self.effectSettingsPasteboardType) else{throw EffectClipboardError.invalid}}catch{self.error=error.localizedDescription}
    }
    func pasteEffectSettings(from pasteboard:NSPasteboard = .general){
        guard selectedAcceptsVisualEffects else{return}
        do{
            guard let data=pasteboard.data(forType:Self.effectSettingsPasteboardType),data.count<=1_048_576 else{throw EffectClipboardError.invalid}
            let payload=try JSONDecoder().decode(EffectSettingsClipboard.self,from:data)
            guard payload.version==1,payload.effects.count<=256 else{throw EffectClipboardError.invalid}
            let effects=payload.effects.map{effect in var effect=effect;effect.id=UUID();return effect}
            editSelected{$0.effects=effects}
        }catch{self.error=error.localizedDescription}
    }
}
private struct EffectSettingsClipboard:Codable{var version=1;var effects:[EffectInstance]}
private enum EffectClipboardError:LocalizedError{case invalid;var errorDescription:String?{"Copy effect settings before pasting."}}
