import AppKit
import SwiftUI
import LifeCore

struct TimelineSurface: NSViewRepresentable {
    @ObservedObject var store: EditorStore
    func makeNSView(context:Context) -> NSScrollView {
        let scroll=NSScrollView(); scroll.hasHorizontalScroller=true; scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true; scroll.drawsBackground=false
        let timeline=TimelineCanvas(store:store); scroll.documentView=timeline
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let timeline=scroll.documentView as? TimelineCanvas else{return}
        timeline.store=store
        timeline.frame.size=NSSize(width:max(scroll.contentSize.width,140+max(20,store.document.sequence.duration.seconds+5)*store.pixelsPerSecond),height:max(scroll.contentSize.height,32+Double(store.document.sequence.tracks.count)*76))
        timeline.refreshAccessibility()
        timeline.loadWaveforms()
        timeline.needsDisplay=true
    }
}

@MainActor final class TimelineCanvas: NSView {
    var store: EditorStore
    let header:Double=140, lane:Double=76, ruler:Double=32
    var drag: Drag?
    var ghost: NSRect?
    var snapX: Double?
    var snapLabel: String?
    var transitionResize:(id:UUID,origin:Double,duration:Double,maximum:Double,sign:Double)?
    var dropGuide:Double?
    var waveforms: [UUID:[Float]] = [:]
    var requested: [UUID:URL] = [:]
    private var accessibilityItems:[NSAccessibilityElement]=[]
    private struct AccessibilitySignature: Equatable {
        var document: ProjectDocument; var selection: Set<UUID>; var frame: NSRect; var bounds: NSRect; var viewport: NSRect; var windowFrame: NSRect; var pixelsPerSecond: Double
    }
    private var accessibilitySignature: AccessibilitySignature?
    private(set) var accessibilityRebuildCount=0
    func refreshAccessibility(){
        let signature=AccessibilitySignature(document:store.document,selection:store.selectedIDs,frame:frame,bounds:bounds,viewport:visibleRect,windowFrame:window?.frame ?? .zero,pixelsPerSecond:store.pixelsPerSecond)
        guard signature != accessibilitySignature else { return }
        accessibilitySignature=signature; accessibilityRebuildCount += 1
        var elements:[NSAccessibilityElement]=[]
        for (row,track) in tracks.enumerated(){
            for clip in track.clips {
                let element=TimelineActionElement { [weak self] in
                    guard let self else { return false }
                    self.store.selectedIDs=[clip.id];self.store.selection=clip.id;self.store.panel = .clip
                    self.window?.makeFirstResponder(self);return true
                }
                element.setAccessibilityRole(.button)
                element.setAccessibilityParent(self)
                element.setAccessibilityLabel(track.name+": "+clip.name)
                element.setAccessibilityValue(String(format:"%.3f seconds, %.3f seconds long",clip.start.seconds,clip.duration.seconds)+(track.isLocked ? ", locked":"")+(store.selectedIDs.contains(clip.id) ? ", selected":""))
                let frame=convert(rect(clip,row:row),to:nil)
                element.setAccessibilityFrame(window?.convertToScreen(frame) ?? frame)
                elements.append(element)
            }
            for (index,label) in ["Mute","Hide","Lock"].enumerated(){
                let element=TimelineActionElement { [weak self] in
                    guard let self else { return false }
                    self.store.toggleTrack(track.id,property:["mute","hide","lock"][index]);return true
                }
                element.setAccessibilityRole(.button);element.setAccessibilityParent(self);element.setAccessibilityLabel(label+" "+track.name)
                let frame=convert(NSRect(x:visibleRect.minX+12+Double(index)*36,y:ruler+Double(row)*lane+47,width:28,height:24),to:nil)
                element.setAccessibilityFrame(window?.convertToScreen(frame) ?? frame);elements.append(element)
            }
        }
        for marker in store.document.sequence.markers {
            guard let range=MarkerResolver.sequenceRange(marker,in:store.document) else { continue }
            let element=TimelineActionElement { [weak self] in
                guard let self else { return false };self.store.seek(range.start.seconds);return true
            }
            element.setAccessibilityRole(.button); element.setAccessibilityParent(self)
            element.setAccessibilityLabel(marker.name.isEmpty ? "Marker" : marker.name)
            element.setAccessibilityValue(String(format:"%.3f seconds",range.start.seconds)+(range.duration > .zero ? String(format:", %.3f seconds long",range.duration.seconds):"")+(marker.note.isEmpty ? "":", "+marker.note))
            let frame=convert(NSRect(x:x(range.start.seconds)-5,y:0,width:max(12,range.duration.seconds*store.pixelsPerSecond),height:ruler),to:nil)
            element.setAccessibilityFrame(window?.convertToScreen(frame) ?? frame); elements.append(element)
        }
        accessibilityItems=elements;setAccessibilityChildren(elements)
    }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); observeGeometry() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observeGeometry(); refreshAccessibility() }
    private func observeGeometry() {
        let center=NotificationCenter.default
        for name in [NSView.boundsDidChangeNotification,NSWindow.didMoveNotification,NSWindow.didResizeNotification] { center.removeObserver(self,name:name,object:nil) }
        if let clip=enclosingScrollView?.contentView { clip.postsBoundsChangedNotifications=true; center.addObserver(self,selector:#selector(geometryChanged),name:NSView.boundsDidChangeNotification,object:clip) }
        if let window { for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] { center.addObserver(self,selector:#selector(geometryChanged),name:name,object:window) } }
    }
    @objc private func geometryChanged(_ notification:Notification) { refreshAccessibility(); needsDisplay=true }

    func loadWaveforms() {
        for asset in store.document.assets where requested[asset.id] != (asset.preparedURL ?? asset.url) {
            let decodeURL=asset.preparedURL ?? asset.url
            requested[asset.id]=decodeURL
            Task { [weak self] in
                let peaks=await WaveformCache.shared.peaks(for:decodeURL)
                guard let self,self.requested[asset.id]==decodeURL else{return}
                self.waveforms[asset.id]=peaks;self.needsDisplay=true
            }
        }
    }
    enum Mode { case move, left, right, fadeIn, fadeOut }
    struct Drag { var clip:Clip; var track:Track; var origin:NSPoint; var mode:Mode; var target:Double }
    init(store:EditorStore) { self.store=store; super.init(frame:.zero); setAccessibilityElement(false); setAccessibilityRole(.group); setAccessibilityLabel("Layered timeline. Select clips by clicking; use Clip panel for keyboard positioning.");registerForDraggedTypes([.string]) }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    var tracks:[Track] { Array(store.document.sequence.tracks.reversed()) }
    func x(_ time:Double)->Double { header+time*store.pixelsPerSecond }
    func rect(_ clip:Clip,row:Int)->NSRect { NSRect(x:x(clip.start.seconds),y:ruler+Double(row)*lane+7,width:max(3,clip.duration.seconds*store.pixelsPerSecond),height:62) }
    func text(_ string:String,_ point:NSPoint,color:NSColor = .secondaryLabelColor,size:CGFloat=11) {
        (string as NSString).draw(at:point,withAttributes:[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color])
    }
    override func draw(_ dirtyRect:NSRect) {
        refreshAccessibility()
        NSColor(calibratedWhite:0.075,alpha:1).setFill(); bounds.fill()
        let pps=store.pixelsPerSecond
        let visible=visibleRect
        let lower=max(0,(visible.minX-header)/pps), upper=max(lower,(visible.maxX-header)/pps)
        if store.gridVisible {
            if let grid=store.document.sequence.musicalGrid {
                var displayed=grid
                let beatPixels=60/grid.bpm*4/Double(grid.beatUnit ?? 4)*pps
                if beatPixels/Double(grid.subdivision)<5 { displayed.subdivision=1 }
                var divisions=displayed.divisions(from:store.time(lower,audio:true),to:store.time(upper,audio:true),maximumCount:10000)
                if divisions.count == 10000, (divisions.last?.time.seconds ?? 0)<upper {
                    // Dense overview: sample exact musical targets at screen-space intervals rather than allocating every beat.
                    var seen=Set<RationalTime>()
                    divisions=stride(from:visible.minX,through:visible.maxX,by:8).compactMap { pixel in
                        guard let division=displayed.nearestDivision(to:store.time(max(0,(pixel-header)/pps),audio:true)), seen.insert(division.time).inserted else { return nil }
                        return division
                    }
                }
                for division in divisions {
                    let xx=x(division.time.seconds), major=division.isBar, beat=division.subdivisionIndex == 0
                    NSColor(white:major ? 0.34 : (beat ? 0.24:0.17),alpha:1).setStroke()
                    let path=NSBezierPath();path.move(to:NSPoint(x:xx,y:0));path.line(to:NSPoint(x:xx,y:bounds.height));path.lineWidth=major ? 1:0.5;path.stroke()
                    if (major && beatPixels*Double(grid.beatsPerBar)>50) || (beat && beatPixels>60) {
                        let bar=division.beatIndex/Int64(grid.beatsPerBar)+1, beat=division.beatIndex%Int64(grid.beatsPerBar)+1
                        text("\(bar).\(beat)",NSPoint(x:xx+5,y:9),size:10)
                    }
                }
            } else {
                let step=timeGridStep
                let first=max(0,Int((lower/step).rounded(.down))), last=max(0,Int((upper/step).rounded(.up)))
                if last >= first && last-first<2000 { for i in first...last {
                    let xx=x(Double(i)*step);NSColor(white:0.22,alpha:1).setStroke()
                    let path=NSBezierPath();path.move(to:NSPoint(x:xx,y:0));path.line(to:NSPoint(x:xx,y:bounds.height));path.lineWidth=0.5;path.stroke()
                    text(String(format:step<1 ? "%.2fs":"%.0fs",Double(i)*step),NSPoint(x:xx+5,y:9),size:10)
                } }
            }
        }
        for (row,track) in tracks.enumerated() {
            let top=ruler+Double(row)*lane
            NSColor(white:0.2,alpha:1).setStroke();let divider=NSBezierPath();divider.move(to:NSPoint(x:0,y:top+lane));divider.line(to:NSPoint(x:bounds.width,y:top+lane));divider.stroke()
            for clip in track.clips {
                let box=rect(clip,row:row)
                guard box.intersects(visibleRect) else{continue}
                let startPixel=max(0,visibleRect.minX-box.minX)
                let endPixel=min(box.width,visibleRect.maxX-box.minX)
                let selected=store.selectedIDs.contains(clip.id)
                let fill:NSColor = track.kind == .audio ? NSColor(red:0.19,green:0.34,blue:0.31,alpha:1) : track.kind == .title ? NSColor(red:0.36,green:0.30,blue:0.41,alpha:1) : NSColor(red:0.24,green:0.30,blue:0.36,alpha:1)
                fill.withAlphaComponent(track.isHidden ? 0.35 : 1).setFill(); NSBezierPath(roundedRect:box,xRadius:5,yRadius:5).fill()
                if selected { NSColor.white.withAlphaComponent(0.8).setStroke();let outline=NSBezierPath(roundedRect:box.insetBy(dx:1,dy:1),xRadius:4,yRadius:4);outline.lineWidth=1.5;outline.stroke() }
                NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:box.insetBy(dx:4,dy:2)).addClip()
                text(clip.name,NSPoint(x:box.minX+8,y:box.minY+6),color:.white)
                if let assetID=clip.assetID,let peaks=waveforms[assetID],!peaks.isEmpty,let asset=store.document.assets.first(where:{$0.id == assetID}) {
                    let waveform=NSBezierPath()
                    for pixel in stride(from:startPixel,through:endPixel,by:2) {
                        let source=clip.sourceStart.seconds + pixel/pps*clip.speed
                        let index=min(peaks.count-1,max(0,Int(source/max(0.001,asset.duration.seconds)*Double(peaks.count))))
                        let height=Double(min(1,peaks[index]))*14
                        waveform.move(to:NSPoint(x:box.minX+pixel,y:box.midY-height+7));waveform.line(to:NSPoint(x:box.minX+pixel,y:box.midY+height+7))
                    }
                    NSColor.white.withAlphaComponent(0.22).setStroke();waveform.stroke()
                }

                let envelope=(track.kind == .video || track.kind == .audio) ? clip.volume:clip.opacity
                let path=NSBezierPath()
                for pixel in stride(from:startPixel,through:endPixel,by:2) {
                    let local=RationalTime(value:Int64((pixel/pps*48000).rounded()),timescale:48000)
                    let y=box.maxY-8-min(2,max(0,envelope.value(at:local)))/2*28
                    if pixel==startPixel { path.move(to:NSPoint(x:box.minX,y:y)) } else { path.line(to:NSPoint(x:box.minX+pixel,y:y)) }
                }
                NSColor.white.withAlphaComponent(0.65).setStroke();path.lineWidth=1;path.stroke()
                if selected {
                    for xx in [box.minX+8,box.maxX-8] { NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:xx-4,y:box.maxY-17,width:8,height:8)).fill() }
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor(white:0.10,alpha:1).setFill();NSRect(x:visible.minX,y:top,width:header,height:lane).fill()
            text(track.name,NSPoint(x:visible.minX+12,y:top+11),color:.labelColor)
            text(track.isLocked ? "● Locked" : (track.kind == .audio ? "Audio" : "Video"),NSPoint(x:visible.minX+12,y:top+30),size:10)
            for (i,symbol) in [track.isMuted ? "speaker.slash.fill" : "speaker.wave.2",track.isHidden ? "eye.slash" : "eye",track.isLocked ? "lock.fill" : "lock.open"].enumerated() {
                let r=NSRect(x:visible.minX+12+Double(i)*36,y:top+47,width:24,height:20)
                NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.draw(in:r)
            }
        }
        NSColor(white:0.1,alpha:1).setFill();NSRect(x:visible.minX,y:0,width:header,height:ruler).fill()
        text("TRACKS",NSPoint(x:visible.minX+12,y:10),size:9)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:NSRect(x:visible.minX+header,y:0,width:max(0,visible.width-header),height:bounds.height)).addClip()
        for marker in store.document.sequence.markers {
            guard let range=MarkerResolver.sequenceRange(marker,in:store.document) else { continue }
            let xx=x(range.start.seconds), end=x(range.end.seconds)
            if range.duration > .zero {
                NSColor.systemOrange.withAlphaComponent(0.14).setFill();NSRect(x:xx,y:22,width:max(1,end-xx),height:bounds.height-22).fill()
                NSColor.systemOrange.withAlphaComponent(0.6).setFill();NSRect(x:end,y:22,width:1,height:bounds.height-22).fill()
            }
            NSColor.systemOrange.setFill();NSRect(x:xx,y:22,width:2,height:bounds.height-22).fill()
            text("◆",NSPoint(x:xx-5,y:4),color:.systemOrange)
            if !marker.name.isEmpty { text(marker.name,NSPoint(x:xx+7,y:4),color:.systemOrange,size:10) }
        }
        NSGraphicsContext.restoreGraphicsState()
        for transition in store.document.sequence.transitions ?? [] {
            guard let trackIndex=tracks.firstIndex(where:{$0.id==transition.trackID}),let left=tracks[trackIndex].clips.first(where:{$0.id==transition.leftClipID}) else{continue}
            let box=transitionRect(transition,center:left.end.seconds,row:trackIndex)
            let valid=TransitionResolver.resolve(transition,in:store.document) != nil
            (valid ? NSColor(calibratedWhite:0.65,alpha:0.9):NSColor.systemOrange.withAlphaComponent(0.7)).setFill();NSBezierPath(roundedRect:box,xRadius:3,yRadius:3).fill()
            NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:box).addClip();text("◇",NSPoint(x:box.midX-5,y:box.minY+2),color:.black,size:12);NSGraphicsContext.restoreGraphicsState()
            if store.selectedTransition==transition.id {NSColor.white.setStroke();NSBezierPath(rect:box.insetBy(dx:-1,dy:-1)).stroke()}
        }
        if let dropGuide {NSColor.white.setStroke();let path=NSBezierPath();path.move(to:NSPoint(x:dropGuide,y:0));path.line(to:NSPoint(x:dropGuide,y:bounds.height));path.lineWidth=2;path.stroke()}
        if let ghost { NSColor.white.withAlphaComponent(0.15).setFill();ghost.fill();NSColor.white.setStroke();NSBezierPath(rect:ghost).stroke() }
        if let snapX { NSColor.systemOrange.setStroke();let p=NSBezierPath();p.move(to:NSPoint(x:snapX,y:0));p.line(to:NSPoint(x:snapX,y:bounds.height));p.stroke();text(snapLabel ?? "Snap",NSPoint(x:snapX+4,y:20),color:.systemOrange) }
        let xx=x(store.playhead); NSColor(red:0.7,green:0.9,blue:0.85,alpha:1).setStroke();let p=NSBezierPath();p.move(to:NSPoint(x:xx,y:0));p.line(to:NSPoint(x:xx,y:bounds.height));p.lineWidth=1.5;p.stroke()
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        let row=Int((point.y-ruler)/lane)
        guard point.y>=ruler,row>=0,row<tracks.count else { store.seek((point.x-header)/store.pixelsPerSecond);return }
        let track=tracks[row]
        if point.x<visibleRect.minX+header {
            if point.y-(ruler+Double(row)*lane)>45 {
                let i=Int((point.x-visibleRect.minX-12)/36)
                if (0...2).contains(i) {store.toggleTrack(track.id,property:["mute","hide","lock"][i])}
            }
            return
        }
        for transition in store.document.sequence.transitions ?? [] where transition.trackID==track.id {
            guard let left=track.clips.first(where:{$0.id==transition.leftClipID}) else{continue}
            let box=transitionRect(transition,center:left.end.seconds,row:row)
            if box.contains(point){
                store.selection=left.id;store.selectedTransition=transition.id;store.panel = .effects
                if !track.isLocked,abs(point.x-box.minX)<8 || abs(point.x-box.maxX)<8,
                   let maximum=try? TransitionResolver.availableDuration(leftClipID:transition.leftClipID,rightClipID:transition.rightClipID,in:store.document,excluding:transition.id){
                    transitionResize=(transition.id,Double(point.x),transition.duration.seconds,maximum.seconds,point.x<box.midX ? -1.0:1.0);store.beginGesture()
                }
                needsDisplay=true;return
            }
        }
        store.selectedTransition=nil
        guard let clip=track.clips.first(where:{rect($0,row:row).contains(point)}) else { store.selection=nil;store.seek((point.x-header)/store.pixelsPerSecond);return }
        if event.modifierFlags.contains(.shift){store.toggleSelection(clip.id)}else if !store.selectedIDs.contains(clip.id){store.selectedIDs=[clip.id];store.selection=clip.id}else{store.selection=clip.id}
        if event.clickCount==2 { store.panel=clip.title == nil ? .clip : .title;return }
        guard !track.isLocked else{return}
        let box=rect(clip,row:row)
        let fade=point.y>box.maxY-24
        let mode:Mode = point.x<box.minX+12 ? (fade ? .fadeIn:.left) : point.x>box.maxX-12 ? (fade ? .fadeOut:.right) : .move
        drag=Drag(clip:clip,track:track,origin:point,mode:mode,target:mode == .right ? clip.end.seconds : clip.start.seconds)
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        if let resize=transitionResize {
            let point=convert(event.locationInWindow,from:nil)
            let minimum=store.document.sequence.settings.frameRate.frameDuration.seconds
            let duration=max(minimum,min(resize.maximum,resize.duration+(point.x-resize.origin)/store.pixelsPerSecond*2*resize.sign))
            store.apply(.setTransitionDuration(id:resize.id,duration:store.time(duration)));return
        }
        guard var drag else{return};let point=convert(event.locationInWindow,from:nil)
        let delta=(point.x-drag.origin.x)/store.pixelsPerSecond
        var target=max(0,(drag.mode == .right ? drag.clip.end.seconds : drag.clip.start.seconds)+delta)
        snapX=nil;snapLabel=nil
        if store.snapping && !event.modifierFlags.contains(.option) && drag.mode != .fadeIn && drag.mode != .fadeOut {
            if let snap=snappedTime(target,excluding:snapExclusions(for:drag)) { target=snap.time;snapX=x(target);snapLabel=snap.label }
        }
        drag.target=target;self.drag=drag
        if let row=tracks.firstIndex(where:{$0.id == drag.track.id}) {
            var box=rect(drag.clip,row:row)
            switch drag.mode {case .move:box.origin.x=x(target);case .left:box.origin.x=x(target);box.size.width=max(1,x(drag.clip.end.seconds)-box.minX);case .right:box.size.width=max(1,x(target)-box.minX);case .fadeIn,.fadeOut:break}
            ghost=box
        }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        if transitionResize != nil {transitionResize=nil;store.endGesture();return}
        defer{drag=nil;ghost=nil;snapX=nil;snapLabel=nil;needsDisplay=true}
        guard let drag else{return}
        let audio=drag.track.kind == .audio
        switch drag.mode {
        case .move:if abs(drag.target-drag.clip.start.seconds)>0.000001 {store.apply(.moveMany(clipIDs:store.selectedIDs,delta:store.time(drag.target,audio:audio)-drag.clip.start))}
        case .left:if abs(drag.target-drag.clip.start.seconds)>0.000001 {store.apply(.trim(clipID:drag.clip.id,start:store.time(drag.target,audio:audio),end:drag.clip.end))}
        case .right:if abs(drag.target-drag.clip.end.seconds)>0.000001 {store.apply(.trim(clipID:drag.clip.id,start:drag.clip.start,end:store.time(drag.target,audio:audio)))}
        case .fadeIn,.fadeOut:
            let point=convert(event.locationInWindow,from:nil)
            let local=min(drag.clip.duration.seconds,max(0,(point.x-header)/store.pixelsPerSecond-drag.clip.start.seconds))
            store.editSelected { clip in
                let level=1.0
                var envelope=(drag.track.kind == .video || drag.track.kind == .audio) ? clip.volume:clip.opacity
                let offset=envelope.evaluationOffset
                // Both handles edit the same envelope used by every volume control.
                if drag.mode == .fadeIn {
                    let t=store.time(local,audio:true)
                    envelope.points.removeAll{$0.time<=t+offset}
                    envelope.points += [.init(time:offset,value:0),.init(time:t+offset,value:level)]
                } else {
                    let t=store.time(local,audio:true)
                    envelope.points.removeAll{$0.time>=t+offset}
                    envelope.points += [.init(time:t+offset,value:level),.init(time:clip.duration+offset,value:0)]
                }
                if drag.track.kind == .video || drag.track.kind == .audio{clip.volume=envelope}else{clip.opacity=envelope}
            }
        }
    }
    private var timeGridStep: Double { [0.01,0.05,0.1,0.25,0.5,1,2,5,10,30,60,120,300].first { $0>=80/store.pixelsPerSecond } ?? 600 }
    /// Explicit edits take priority over a closer ordinary grid division, within eight screen pixels.
    func snappedTime(_ target: Double, excluding: Set<UUID> = []) -> (time:Double,label:String)? {
        var explicit:[(time:Double,label:String)]=store.document.sequence.tracks.flatMap(\.clips).filter { !excluding.contains($0.id) }.flatMap { [($0.start.seconds,"Clip"),($0.end.seconds,"Clip")] }
        for marker in store.document.sequence.markers {
            guard let range=MarkerResolver.sequenceRange(marker,in:store.document) else { continue }
            let label=marker.name.isEmpty ? "Marker":marker.name
            explicit.append((range.start.seconds,label));if range.duration > .zero { explicit.append((range.end.seconds,label)) }
        }
        explicit.append((store.playhead,"Playhead"))
        let candidates=explicit.filter { $0.time >= 0 && abs($0.time-target)*store.pixelsPerSecond<=8 }
        if let nearest=candidates.min(by:{abs($0.time-target)<abs($1.time-target)}) { return nearest }
        let gridTarget:Double
        let label:String
        if let grid=store.document.sequence.musicalGrid,let nearest=grid.nearestDivision(to:store.time(max(0,target),audio:true)) { gridTarget=nearest.time.seconds;label=nearest.isBar ? "Bar":"Beat" }
        else { gridTarget=(target/timeGridStep).rounded()*timeGridStep;label="Grid" }
        return gridTarget >= 0 && abs(gridTarget-target)*store.pixelsPerSecond<=8 ? (gridTarget,label):nil
    }
    private func snapExclusions(for drag:Drag)->Set<UUID> {
        let clips=store.document.sequence.tracks.flatMap(\.clips)
        var ids=drag.mode == .move ? store.selectedIDs.union([drag.clip.id]):[drag.clip.id]
        while true {
            let members=clips.filter { ids.contains($0.id) }, links=Set(members.compactMap(\.linkID)),groups=Set(members.compactMap(\.groupID)), prior=ids
            for clip in clips where clip.linkID.map(links.contains) == true || (drag.mode == .move && clip.groupID.map(groups.contains) == true) { ids.insert(clip.id) }
            if ids == prior { return ids }
        }
    }
    private func transitionRect(_ transition:VideoTransition,center:Double,row:Int)->NSRect{
        NSRect(x:x(center-transition.duration.seconds/2),y:ruler+Double(row)*lane+29,width:max(12,transition.duration.seconds*store.pixelsPerSecond),height:22)
    }
    private func dropPair(_ sender:any NSDraggingInfo)->(Clip,Clip)? {
        guard let value=sender.draggingPasteboard.string(forType:.string),value.hasPrefix("life.transition."),TransitionKind(rawValue:String(value.dropFirst("life.transition.".count))) != nil else{return nil}
        let point=convert(sender.draggingLocation,from:nil),row=Int((point.y-ruler)/lane)
        guard point.y>=ruler,row>=0,row<tracks.count,tracks[row].kind != .audio,!tracks[row].isLocked else{return nil}
        let sorted=tracks[row].clips.sorted{$0.start<$1.start}
        let pairs=Array(zip(sorted,sorted.dropFirst())).filter{$0.end==$1.start && abs(x($0.end.seconds)-point.x)<24}
        return pairs.min{abs(x($0.0.end.seconds)-point.x)<abs(x($1.0.end.seconds)-point.x)}
    }
    override func draggingEntered(_ sender:any NSDraggingInfo)->NSDragOperation {draggingUpdated(sender)}
    override func draggingUpdated(_ sender:any NSDraggingInfo)->NSDragOperation {
        if let pair=dropPair(sender){dropGuide=x(pair.0.end.seconds);needsDisplay=true;return .copy}
        dropGuide=nil;needsDisplay=true;return []
    }
    override func draggingExited(_ sender:(any NSDraggingInfo)?){dropGuide=nil;needsDisplay=true}
    override func performDragOperation(_ sender:any NSDraggingInfo)->Bool {
        defer{dropGuide=nil;needsDisplay=true}
        guard let pair=dropPair(sender),let raw=sender.draggingPasteboard.string(forType:.string),let kind=TransitionKind(rawValue:String(raw.dropFirst("life.transition.".count))) else{return false}
        let prior=store.document;store.applyTransition(kind,left:pair.0.id,right:pair.1.id);return prior != store.document
    }
    override func keyDown(with event:NSEvent) {
        if !event.isARepeat,store.panel == .multicam,let chars=event.charactersIgnoringModifiers,let digit=Int(chars),(1...9).contains(digit),store.visibleAngles.indices.contains(digit-1) {store.chooseAngle(store.visibleAngles[digit-1].id);return}
        if event.keyCode==123 {store.step(-1)} else if event.keyCode==124 {store.step(1)} else if event.keyCode==49 {store.togglePlayback()} else if event.keyCode==51 {store.deleteSelection()} else {super.keyDown(with:event)}
    }
}

/// AppKit's synchronous accessibility callback enters an immutable Sendable action on its main-thread boundary.
@MainActor private final class TimelineActionElement:NSAccessibilityElement {
    nonisolated let action: @MainActor @Sendable () -> Bool
    init(action: @escaping @MainActor @Sendable () -> Bool) { self.action=action;super.init() }
    nonisolated override func accessibilityPerformPress()->Bool {
        let action=self.action
        return MainActor.assumeIsolated { action() }
    }
}
