import Foundation
import AppKit
import LifeCore

extension EditorStore {
    var currentAutomationEnvelope: AutomationEnvelope {
        guard let clip=selectedClip else { return .init() }
        return automationLane == .volume ? clip.volume:clip.opacity
    }
    var visibleAutomationPoints: [AutomationPoint] {
        guard let clip=selectedClip else { return [] }
        let envelope=currentAutomationEnvelope
        return envelope.points.filter { $0.time >= envelope.evaluationOffset && $0.time <= envelope.evaluationOffset+clip.duration }.sorted { $0.time < $1.time }
    }
    var currentAutomationPoint: AutomationPoint? { visibleAutomationPoints.first { $0.id == selectedAutomationPoint } }
    func automationLocalTime(_ point:AutomationPoint)->Double { (point.time-currentAutomationEnvelope.evaluationOffset).seconds }
    func copyAutomationPoint(to pasteboard:NSPasteboard = .general){
        guard let point=currentAutomationPoint else{error=AutomationClipboardError.selection.localizedDescription;return}
        copyAutomationPoints([point],to:pasteboard)
    }
    func copyVisibleAutomationPoints(to pasteboard:NSPasteboard = .general){copyAutomationPoints(visibleAutomationPoints,to:pasteboard)}
    private func copyAutomationPoints(_ points:[AutomationPoint],to pasteboard:NSPasteboard){
        do{
            guard points.count<=10000 else{throw AutomationClipboardError.limit}
            let ordered=points.sorted{$0.time<$1.time}
            guard let first=ordered.first else{throw AutomationClipboardError.selection}
            let envelope=currentAutomationEnvelope
            let copied=try ordered.map{point in
                AutomationClipboardPoint(offset:.init(try point.time.checkedSubtracting(first.time)),effectiveValue:envelope.baseValue*point.value,interpolation:point.interpolation)
            }
            let payload=AutomationPointClipboard(version:1,lane:automationLane.rawValue,points:copied)
            _ = try payload.checked(for:automationLane)
            let data=try JSONEncoder().encode(payload);guard data.count<=AutomationPointClipboard.maximumBytes else{throw AutomationClipboardError.limit}
            pasteboard.clearContents();guard pasteboard.setData(data,forType:AutomationPointClipboard.type) else{throw AutomationClipboardError.invalid}
        }catch{self.error=(error as? LocalizedError)?.errorDescription ?? "Cannot copy these automation points."}
    }
    func pasteAutomationPoints(from pasteboard:NSPasteboard = .general){
        guard placementProposal == nil else{error="Apply or cancel the placement preview first.";return}
        guard let clip=selectedClip else{return}
        do{
            let copied=try AutomationPointClipboard.read(from:pasteboard).checked(for:automationLane)
            guard (1...1_000_000_000).contains(playheadTime.timescale),playheadTime >= .zero,playheadTime.seconds<=86400 else{throw AutomationClipboardError.range}
            let anchor=try playheadTime.checkedSubtracting(clip.start)
            guard anchor >= .zero,try anchor.checkedAdding(copied.last!.offset)<=clip.duration else{throw AutomationClipboardError.range}
            var selected:UUID?
            let success=modifyAutomation{envelope,_ in
                try self.rebaseAutomationIfNeeded(&envelope,local:anchor)
                var indices:[RationalTime:Int]=[:]
                for (index,point) in envelope.points.enumerated(){
                    let canonical=try AutomationClipboardTime(point.time).checked()
                    guard indices.updateValue(index,forKey:canonical)==nil else{throw AutomationClipboardError.invalid}
                }
                for point in copied{
                    self.ensureAutomationBase(&envelope,for:point.value)
                    if envelope.baseValue>0,!(point.value/envelope.baseValue).isFinite{
                        let old=envelope.baseValue;for index in envelope.points.indices{envelope.points[index].value*=old};envelope.baseValue=1
                    }
                    let time=try anchor.checkedAdding(point.offset).checkedAdding(envelope.evaluationOffset)
                    let value=envelope.baseValue>0 ? point.value/envelope.baseValue:0
                    if let index=indices[time]{
                        envelope.points[index].value=value;envelope.points[index].interpolation=point.curve
                        if selected==nil{selected=envelope.points[index].id}
                    }else{
                        let added=AutomationPoint(time:time,value:value,interpolation:point.curve);indices[time]=envelope.points.count;envelope.points.append(added);if selected==nil{selected=added.id}
                    }
                }
            }
            if success{selectedAutomationPoint=selected}
        }catch{self.error=(error as? LocalizedError)?.errorDescription ?? "The clipboard contains invalid automation points."}
    }
    func setAutomationBase(_ value:Double) {
        guard value.isFinite,value>=0 else { error="Enter a finite level.";return }
        _ = modifyAutomation { envelope,_ in
            let peak=max(1,envelope.points.map(\.value).max() ?? 1)
            envelope.baseValue=min(value,self.automationLane.maximumValue/peak)
        }
    }
    @discardableResult func addAutomationPoint(at sequenceTime:Double,effectiveValue:Double? = nil)->UUID? {
        guard sequenceTime.isFinite,effectiveValue?.isFinite ?? true else { error="Enter a finite point time and value.";return nil }
        var added:UUID?
        let success=modifyAutomation { envelope,clip in
            let local=min(clip.duration,self.time(min(clip.duration.seconds,max(0,sequenceTime-clip.start.seconds)),audio:true))
            try self.rebaseAutomationIfNeeded(&envelope,local:local)
            let time=try local.checkedAdding(envelope.evaluationOffset)
            let effective=effectiveValue ?? envelope.value(at:local)
            guard (0...self.automationLane.maximumValue).contains(effective) else { throw DocumentError.invalidTiming }
            self.ensureAutomationBase(&envelope,for:effective)
            let value=envelope.baseValue > 0 ? effective/envelope.baseValue:0
            if let index=envelope.points.firstIndex(where: { $0.time == time }) {
                envelope.points[index].value=value;added=envelope.points[index].id
            } else {
                let point=AutomationPoint(time:time,value:value);envelope.points.append(point);added=point.id
            }
        }
        if success { selectedAutomationPoint=added };return success ? added:nil
    }
    func updateAutomationPoint(id:UUID,sequenceTime:Double? = nil,effectiveValue:Double? = nil,interpolation:Interpolation? = nil) {
        guard sequenceTime?.isFinite ?? true,effectiveValue?.isFinite ?? true else { error="Enter a finite point time and value.";return }
        let success=modifyAutomation { envelope,clip in
            guard envelope.points.contains(where: { $0.id == id }) else { throw DocumentError.clipNotFound }
            if let sequenceTime {
                let local=min(clip.duration,self.time(min(clip.duration.seconds,max(0,sequenceTime-clip.start.seconds)),audio:true))
                try self.rebaseAutomationIfNeeded(&envelope,local:local)
                let time=try local.checkedAdding(envelope.evaluationOffset)
                guard !envelope.points.contains(where: { $0.id != id && $0.time == time }) else { throw DocumentError.invalidTiming }
                let index=envelope.points.firstIndex(where: { $0.id == id })!
                envelope.points[index].time=time
            }
            if let effectiveValue {
                guard (0...self.automationLane.maximumValue).contains(effectiveValue) else { throw DocumentError.invalidTiming }
                self.ensureAutomationBase(&envelope,for:effectiveValue)
                let index=envelope.points.firstIndex(where: { $0.id == id })!
                envelope.points[index].value=envelope.baseValue > 0 ? effectiveValue/envelope.baseValue:0
            }
            if let interpolation,let index=envelope.points.firstIndex(where: { $0.id == id }) { envelope.points[index].interpolation=interpolation }
        }
        if success { selectedAutomationPoint=id }
    }
    func deleteAutomationPoint() {
        guard let id=currentAutomationPoint?.id else { return }
        if modifyAutomation({ envelope,_ in envelope.points.removeAll { $0.id == id } }) { selectedAutomationPoint=nil }
    }
    func selectAdjacentAutomationPoint(_ direction:Int) {
        guard let clip=selectedClip else { return }
        let points=visibleAutomationPoints
        let point:AutomationPoint?
        if let index=points.firstIndex(where: { $0.id == selectedAutomationPoint }) {
            let next=index+(direction<0 ? -1:1);point=points.indices.contains(next) ? points[next]:points[index]
        } else if direction<0 { point=points.last(where: { clip.start.seconds+automationLocalTime($0)<playhead }) ?? points.first }
        else { point=points.first(where: { clip.start.seconds+automationLocalTime($0)>playhead }) ?? points.last }
        selectedAutomationPoint=point?.id
        if let point { seek(clip.start.seconds+automationLocalTime(point)) }
    }
    func setLaneFade(_ seconds:Double,incoming:Bool,source:AutomationEnvelope? = nil) {
        guard seconds.isFinite,seconds>=0 else { error="Enter a finite fade duration.";return }
        _ = modifyAutomation { envelope,clip in
            if let source { envelope=source }
            let duration=min(seconds,clip.duration.seconds), local=min(clip.duration,self.time(incoming ? duration:clip.duration.seconds-duration,audio:true))
            try self.rebaseAutomationIfNeeded(&envelope,local:.zero)
            let start=envelope.evaluationOffset,end=try start.checkedAdding(clip.duration),time=try start.checkedAdding(local)
            envelope.points.removeAll { point in
                point.time>=start && point.time<=end && (incoming ? point.time<=time:point.time>=time)
            }
            if duration == 0 { envelope.points.append(.init(time:incoming ? start:end,value:1)) }
            else if incoming { envelope.points += [.init(time:start,value:0),.init(time:time,value:1)] }
            else { envelope.points += [.init(time:time,value:1),.init(time:end,value:0)] }
        }
        selectedAutomationPoint=nil
    }
    func automationFadeDuration(incoming:Bool)->Double {
        guard let clip=selectedClip else { return 0 }
        let envelope=currentAutomationEnvelope,points=visibleAutomationPoints,offset=envelope.evaluationOffset
        if incoming {
            guard envelope.value(at:.zero)==0,let next=points.first(where: { $0.time>offset && $0.value>0 }) else { return 0 }
            return min(clip.duration.seconds,(next.time-offset).seconds)
        }
        guard envelope.value(at:clip.duration)==0,let prior=points.last(where: { $0.time<offset+clip.duration && $0.value>0 }) else { return 0 }
        return min(clip.duration.seconds,clip.duration.seconds-(prior.time-offset).seconds)
    }
    private func modifyAutomation(_ mutation:(inout AutomationEnvelope,Clip)throws->Void)->Bool {
        guard let clip=selectedClip,let track=document.sequence.tracks.first(where: { $0.clips.contains { $0.id == clip.id } }) else { return false }
        guard !track.isLocked else { error="Unlock the track to edit.";return false }
        var envelope=automationLane == .volume ? clip.volume:clip.opacity
        do { try mutation(&envelope,clip) } catch { self.error="The automation point time or value is unavailable.";return false }
        var next=document
        for t in next.sequence.tracks.indices {
            if let c=next.sequence.tracks[t].clips.firstIndex(where: { $0.id == clip.id }) {
                if automationLane == .volume { next.sequence.tracks[t].clips[c].volume=envelope }
                else { next.sequence.tracks[t].clips[c].opacity=envelope }
            }
        }
        do { try next.validate() } catch { self.error="The automation value exceeds the supported range.";return false }
        replace(next);return document == next
    }
    private func rebaseAutomationIfNeeded(_ envelope:inout AutomationEnvelope,local:RationalTime)throws {
        let position=try envelope.evaluationOffset.checkedAdding(local)
        guard position < .zero else { return }
        let shift=try RationalTime.zero.checkedSubtracting(position)
        envelope.evaluationOffset=try envelope.evaluationOffset.checkedAdding(shift)
        for i in envelope.points.indices { envelope.points[i].time=try envelope.points[i].time.checkedAdding(shift) }
    }
    private func ensureAutomationBase(_ envelope:inout AutomationEnvelope,for effective:Double) {
        if envelope.baseValue == 0 && effective > 0 { envelope.baseValue=1;for i in envelope.points.indices { envelope.points[i].value=0 } }
    }
}
