import AppKit
import SwiftUI
import LifeCore
import LifeAnalysis

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
        timeline.synchronizeLayout()
        timeline.frame.size=NSSize(width:max(scroll.contentSize.width,140+max(20,store.timelineDocument.sequence.duration.seconds+5)*store.pixelsPerSecond),height:max(scroll.contentSize.height,timeline.layout.totalHeight(for:timeline.tracks)))
        timeline.refreshAccessibility()
        timeline.loadWaveforms()
        timeline.loadThumbnails()
        timeline.needsDisplay=true
    }
}

@MainActor final class TimelineCanvas: NSView {
    var store: EditorStore
    let header:Double=140,ruler:Double=32
    let layout:TimelineLayout
    private var resizingTrack:(id:UUID,originY:Double,height:Double)?
    private var layoutTrackSelection:UUID?
    private struct ThumbnailRequest {let key:String;let asset:MediaAsset;let stamp:String;let cell:TimelineThumbnailCell;let effects:[EffectInstance]}
    private struct ThumbnailPlanSignature:Equatable {var document:ProjectDocument;var viewport:NSRect;var pps:Double;var layoutRevision:Int;var stamps:[UUID:String]}
    private var thumbnailSignature:ThumbnailPlanSignature?
    private var thumbnailRequests:[ThumbnailRequest]=[]
    private var thumbnailImages:[String:CGImage]=[:]
    private var thumbnailJobs:[String:Task<Void,Never>]=[:]
    private var thumbnailFailures=Set<String>()
    private var thumbnailStamps:[UUID:String]=[:]
    private var thumbnailURLs:[UUID:URL]=[:]
    private var thumbnailMetadataTask:Task<Void,Never>?
    private var thumbnailMetadataPoll=Date.distantPast
    var drag: Drag?
    private enum AutomationDragMode { case point(UUID),base,fadeIn,fadeOut }
    private struct AutomationDrag { var clipID:UUID;var lane:AutomationLane;var mode:AutomationDragMode;var origin:NSPoint;var envelope:AutomationEnvelope }
    private var automationDrag:AutomationDrag?
    var ghost: NSRect?
    var snapX: Double?
    var snapLabel: String?
    var transitionResize:(id:UUID,origin:Double,duration:Double,maximum:Double,sign:Double)?
    var dropGuide:Double?
    var waveforms: [UUID:WaveformOverview] = [:]
    var requested: [UUID:URL] = [:]
    private var waveformTasks:[UUID:Task<Void,Never>]=[:]
    private var waveformPoll:[UUID:Date]=[:]
    private var sampleWindows:[String:WaveformSampleWindow]=[:]
    private var sampleTasks:[String:Task<Void,Never>]=[:]
    private var accessibilityItems:[NSAccessibilityElement]=[]
    private struct AccessibilitySignature: Equatable {
        var document: ProjectDocument; var selection: Set<UUID>; var frame: NSRect; var bounds: NSRect; var viewport: NSRect; var windowFrame: NSRect; var pixelsPerSecond: Double;var layoutRevision:Int
    }
    private var accessibilitySignature: AccessibilitySignature?
    private(set) var accessibilityRebuildCount=0
    func refreshAccessibility(){
        let signature=AccessibilitySignature(document:store.timelineDocument,selection:store.selectedIDs.union(store.placementProposal?.insertedClipIDs ?? []),frame:frame,bounds:bounds,viewport:visibleRect,windowFrame:window?.frame ?? .zero,pixelsPerSecond:store.pixelsPerSecond,layoutRevision:layout.revision)
        guard signature != accessibilitySignature else { return }
        accessibilitySignature=signature; accessibilityRebuildCount += 1
        var elements:[NSAccessibilityElement]=[]
        for (row,track) in tracks.enumerated(){
            for clip in track.clips {
                let element=TimelineActionElement { [weak self] in
                    guard let self,self.store.placementProposal == nil else { return false }
                    self.store.selectedIDs=[clip.id];self.store.selection=clip.id;self.store.panel = .clip
                    self.window?.makeFirstResponder(self);return true
                }
                element.setAccessibilityRole(.button)
                element.setAccessibilityParent(self)
                element.setAccessibilityLabel(track.name+": "+clip.name)
                element.setAccessibilityValue(String(format:"%.3f seconds, %.3f seconds long",clip.start.seconds,clip.duration.seconds)+(track.isLocked ? ", locked":"")+((store.selectedIDs.contains(clip.id) || store.placementProposal?.insertedClipIDs.contains(clip.id) == true) ? ", selected":""))
                let frame=convert(rect(clip,row:row),to:nil)
                element.setAccessibilityFrame(window?.convertToScreen(frame) ?? frame)
                elements.append(element)
            }
            for (index,label) in ["Mute","Hide","Lock"].enumerated(){
                let element=TimelineActionElement { [weak self] in
                    guard let self,self.store.placementProposal == nil else { return false }
                    self.store.toggleTrack(track.id,property:["mute","hide","lock"][index]);return true
                }
                element.setAccessibilityRole(.button);element.setAccessibilityParent(self);element.setAccessibilityLabel(label+" "+track.name)
                let frame=convert(NSRect(x:visibleRect.minX+12+Double(index)*36,y:rowLayout(row).bottom-26,width:28,height:24),to:nil)
                element.setAccessibilityFrame(window?.convertToScreen(frame) ?? frame);elements.append(element)
            }
            let height=TimelineHeightElement(increment:{[weak self] in self?.resizeTrack(track.id,by:16) ?? false},decrement:{[weak self] in self?.resizeTrack(track.id,by:-16) ?? false})
            height.setAccessibilityRole(.slider);height.setAccessibilityParent(self);height.setAccessibilityLabel("Height "+track.name);height.setAccessibilityValue(layout.height(for:track.id));height.setAccessibilityMinValue(56);height.setAccessibilityMaxValue(240)
            let heightFrame=convert(NSRect(x:visibleRect.minX,y:rowLayout(row).bottom-4,width:header,height:8),to:nil)
            height.setAccessibilityFrame(window?.convertToScreen(heightFrame) ?? heightFrame);elements.append(height)
        }
        for marker in store.timelineDocument.sequence.markers {
            guard let range=MarkerResolver.sequenceRange(marker,in:store.timelineDocument) else { continue }
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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow();observeGeometry();refreshAccessibility()
        if window == nil {for task in waveformTasks.values{task.cancel()};for task in sampleTasks.values{task.cancel()};waveformTasks.removeAll();sampleTasks.removeAll();for task in thumbnailJobs.values{task.cancel()};thumbnailJobs.removeAll();thumbnailMetadataTask?.cancel();thumbnailMetadataTask=nil}
    }
    private func observeGeometry() {
        let center=NotificationCenter.default
        for name in [NSView.boundsDidChangeNotification,NSWindow.didMoveNotification,NSWindow.didResizeNotification] { center.removeObserver(self,name:name,object:nil) }
        if let clip=enclosingScrollView?.contentView { clip.postsBoundsChangedNotifications=true; center.addObserver(self,selector:#selector(geometryChanged),name:NSView.boundsDidChangeNotification,object:clip) }
        if let window { for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] { center.addObserver(self,selector:#selector(geometryChanged),name:name,object:window) } }
    }
    @objc private func geometryChanged(_ notification:Notification) { refreshAccessibility();loadWaveforms();loadThumbnails();needsDisplay=true }

    @discardableResult func setTrackHeight(_ height:Double,for id:UUID)->Bool {
        guard layout.setHeight(height,for:id) else{return false}
        setFrameSize(NSSize(width:frame.width,height:max(enclosingScrollView?.contentSize.height ?? 0,layout.totalHeight(for:tracks))))
        refreshAccessibility();loadWaveforms();loadThumbnails();window?.invalidateCursorRects(for:self);needsDisplay=true;return true
    }
    @discardableResult func resizeTrack(_ id:UUID,by delta:Double)->Bool {setTrackHeight(layout.height(for:id)+delta,for:id)}
    override func resetCursorRects(){super.resetCursorRects();for row in layout.rows(for:tracks){addCursorRect(NSRect(x:visibleRect.minX,y:row.bottom-4,width:header,height:8),cursor:.resizeUpDown)}}
    override func menu(for event:NSEvent)->NSMenu? {
        let point=convert(event.locationInWindow,from:nil)
        guard point.x<visibleRect.minX+header,let row=layout.row(at:point.y,tracks:tracks) else{return super.menu(for:event)}
        let menu=NSMenu();for (label,height) in [("Compact",56.0),("Medium",76.0),("Large",140.0),("Tall",220.0)] {
            let item=NSMenuItem(title:label,action:#selector(heightPreset(_:)),keyEquivalent:"");item.target=self;item.representedObject=["id":tracks[row].id.uuidString,"height":String(height)];menu.addItem(item)
        };return menu
    }
    @objc private func heightPreset(_ sender:NSMenuItem){guard let data=sender.representedObject as? [String:String],let raw=data["id"],let id=UUID(uuidString:raw),let value=data["height"].flatMap(Double.init) else{return};_ = setTrackHeight(value,for:id)}
    func loadThumbnails(){
        let visible=tracks.enumerated().flatMap{row,track in track.clips.filter{rect($0,row:row).intersects(visibleRect)}}
        let ids=Set(visible.compactMap(\.assetID));let assets=store.timelineDocument.assets.filter{ids.contains($0.id) && $0.kind != .audio}
        var changed=false
        for asset in assets {let url=asset.preparedURL ?? asset.url;if thumbnailURLs[asset.id] != url{thumbnailURLs[asset.id]=url;thumbnailStamps.removeValue(forKey:asset.id);changed=true}}
        if changed{thumbnailMetadataPoll = .distantPast}
        if thumbnailMetadataTask == nil,Date().timeIntervalSince(thumbnailMetadataPoll)>2 {
            thumbnailMetadataPoll=Date();let project=store.timelineDocument.id
            thumbnailMetadataTask=Task{[weak self] in
                for asset in assets {
                    let stamp=try? await TimelineThumbnailCache.shared.sourceStamp(for:asset)
                    guard !Task.isCancelled,let self,self.store.timelineDocument.id==project else{return}
                    if self.thumbnailURLs[asset.id]==(asset.preparedURL ?? asset.url){self.thumbnailStamps[asset.id]=stamp}
                }
                guard let self else{return};self.thumbnailMetadataTask=nil;self.loadThumbnails()
            }
        }
        let signature=ThumbnailPlanSignature(document:store.timelineDocument,viewport:visibleRect,pps:store.pixelsPerSecond,layoutRevision:layout.revision,stamps:thumbnailStamps)
        if signature != thumbnailSignature {
            thumbnailSignature=signature;thumbnailRequests=[]
            let range=max(0,(visibleRect.minX-header)/store.pixelsPerSecond)...max(0,(visibleRect.maxX-header)/store.pixelsPerSecond)
            for clip in visible {
                guard thumbnailRequests.count<128,let asset=assets.first(where:{$0.id==clip.assetID}),let stamp=thumbnailStamps[asset.id] else{continue}
                let effects=clip.effects ?? []
                for cell in FilmstripPlanner.cells(clip:clip,assetKind:asset.kind,visibleRange:range,pixelsPerSecond:store.pixelsPerSecond,maximumCount:min(24,128-thumbnailRequests.count)) {
                    if let key=try? TimelineThumbnailCache.logicalKey(sourceStamp:stamp,sourceTime:cell.sourceTime,effects:effects){thumbnailRequests.append(ThumbnailRequest(key:key,asset:asset,stamp:stamp,cell:cell,effects:effects))}
                }
            }
            let keys=Set(thumbnailRequests.map(\.key))
            for (key,job) in thumbnailJobs where !keys.contains(key){job.cancel();thumbnailJobs.removeValue(forKey:key)}
            thumbnailImages=thumbnailImages.filter{keys.contains($0.key)};thumbnailFailures.formIntersection(keys)
        }
        for request in thumbnailRequests where thumbnailJobs.count<2 && thumbnailImages[request.key]==nil && thumbnailJobs[request.key]==nil && !thumbnailFailures.contains(request.key) {
            thumbnailJobs[request.key]=Task{[weak self] in
                do {
                    let result=try await TimelineThumbnailCache.shared.image(for:request.asset,sourceTime:request.cell.sourceTime,effects:request.effects)
                    guard !Task.isCancelled,let self,self.thumbnailRequests.contains(where:{$0.key==request.key}),self.thumbnailStamps[request.asset.id]==request.stamp else{return}
                    self.thumbnailImages[request.key]=result.image
                } catch {if !Task.isCancelled{self?.thumbnailFailures.insert(request.key)}}
                guard !Task.isCancelled,let self else{return};self.thumbnailJobs.removeValue(forKey:request.key);self.needsDisplay=true;self.loadThumbnails()
            }
        }
    }
    private func drawFilmstrip(_ clip:Clip,in box:NSRect){
        guard let context=NSGraphicsContext.current?.cgContext else{return}
        var drawn=false
        for request in thumbnailRequests where request.cell.clipID==clip.id {
            guard let image=thumbnailImages[request.key] else{continue};drawn=true
            let cell=NSRect(x:box.minX+request.cell.offsetPixels,y:box.minY,width:request.cell.widthPixels,height:box.height)
            let scale=max(cell.width/Double(image.width),cell.height/Double(image.height))
            let size=NSSize(width:Double(image.width)*scale,height:Double(image.height)*scale)
            context.saveGState();context.clip(to:cell)
            NSImage(cgImage:image,size:.zero).draw(in:NSRect(x:cell.midX-size.width/2,y:cell.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:0.48,respectFlipped:true,hints:nil)
            context.restoreGState()
        }
        if drawn{NSColor.black.withAlphaComponent(0.3).setFill();NSRect(x:box.minX,y:box.minY,width:box.width,height:23).fill()}
    }

    func loadWaveforms() {
        let visibleIDs=Set(tracks.enumerated().flatMap { row,track in track.clips.filter { rect($0,row:row).intersects(visibleRect) }.compactMap(\.assetID) })
        let assets=store.timelineDocument.assets.filter { $0.kind != .image && visibleIDs.contains($0.id) }
        let active=Set(assets.map(\.id))
        for id in Array(waveformTasks.keys) where !active.contains(id) { waveformTasks.removeValue(forKey:id)?.cancel() }
        waveforms=waveforms.filter { active.contains($0.key) };requested=requested.filter { active.contains($0.key) }
        for asset in assets {
            let url=asset.preparedURL ?? asset.url
            if requested[asset.id] != url {
                waveformTasks.removeValue(forKey:asset.id)?.cancel();waveforms.removeValue(forKey:asset.id);waveformPoll.removeValue(forKey:asset.id);requested[asset.id]=url
            }
            guard waveformTasks[asset.id] == nil,Date().timeIntervalSince(waveformPoll[asset.id] ?? .distantPast)>=2 else{continue}
            guard waveforms[asset.id] != nil || waveforms.values.reduce(0,{$0+$1.pyramid.memoryBytes})<128_000_000 else{continue}
            guard waveformTasks.count<2 else{continue}
            waveformPoll[asset.id]=Date()
            waveformTasks[asset.id]=Task { [weak self] in
                do {
                    let overview=try await WaveformCache.shared.overview(for:url)
                    guard !Task.isCancelled,let self,self.requested[asset.id]==url else{return}
                    self.waveformTasks[asset.id]=nil
                    if self.waveforms[asset.id]?.sourceKey != overview.sourceKey { self.waveforms[asset.id]=overview;self.needsDisplay=true }
                    self.loadWaveforms()
                } catch {
                    guard !Task.isCancelled,let self,self.requested[asset.id]==url else{return};self.waveformTasks[asset.id]=nil
                }
            }
        }
        loadSampleWindows()
    }
    private func sampleKey(_ assetID:UUID,_ source:String,_ chunk:Int64)->String { assetID.uuidString+"|"+source+"|\(chunk)" }
    private func loadSampleWindows() {
        var requests:[(String,UUID,URL,String,Double,Double)]=[],seen=Set<String>(),bytes=0
        for (row,track) in tracks.enumerated() {
            for clip in track.clips where rect(clip,row:row).intersects(visibleRect) {
                guard let id=clip.assetID,let overview=waveforms[id],let url=requested[id] else{continue}
                let rate=overview.pyramid.sampleRate
                guard rate*clip.speed/store.pixelsPerSecond<=64 else{continue}
                let lower=max(clip.start.seconds,(visibleRect.minX-header)/store.pixelsPerSecond),upper=min(clip.end.seconds,(visibleRect.maxX-header)/store.pixelsPerSecond)
                guard upper>lower else{continue}
                let first=max(0,Int64(floor((clip.sourceStart.seconds+(lower-clip.start.seconds)*clip.speed)*rate)))
                let last=min(overview.pyramid.sampleCount,Int64(ceil((clip.sourceStart.seconds+(upper-clip.start.seconds)*clip.speed)*rate)))
                guard last>first else{continue}
                let firstChunk=first/65536,lastChunk=(last-1)/65536
                guard lastChunk-firstChunk<64 else{continue}
                for chunk in firstChunk...lastChunk {
                    let key=sampleKey(id,overview.sourceKey,chunk),end=min(overview.pyramid.sampleCount,(chunk+1)*65536)
                    let size=Int(end-chunk*65536)*overview.pyramid.channelCount*4
                    guard seen.insert(key).inserted,bytes+size<=24_000_000 else{continue}
                    bytes+=size;requests.append((key,id,url,overview.sourceKey,Double(chunk*65536)/rate,Double(end)/rate))
                }
            }
        }
        let needed=Set(requests.map{$0.0})
        for key in Array(sampleTasks.keys) where !needed.contains(key) { sampleTasks.removeValue(forKey:key)?.cancel() }
        sampleWindows=sampleWindows.filter { needed.contains($0.key) }
        for (key,id,url,source,lower,upper) in requests where sampleWindows[key] == nil && sampleTasks[key] == nil {
            guard sampleTasks.count<2 else{break}
            sampleTasks[key]=Task { [weak self] in
                do {
                    let window=try await WaveformCache.shared.samples(for:url,from:lower,to:upper)
                    guard !Task.isCancelled,let self,self.requested[id]==url,self.waveforms[id]?.sourceKey==source,window.sourceKey==source else{return}
                    self.sampleTasks[key]=nil;self.sampleWindows[key]=window;self.needsDisplay=true;self.loadSampleWindows()
                } catch {
                    guard !Task.isCancelled,let self else{return};self.sampleTasks[key]=nil
                }
            }
        }
    }
    enum Mode { case move, left, right, fadeIn, fadeOut }
    struct Drag { var clip:Clip; var track:Track; var origin:NSPoint; var mode:Mode; var target:Double }
    init(store:EditorStore,layout:TimelineLayout? = nil) { self.store=store;self.layout=layout ?? TimelineLayout(projectID:store.timelineDocument.id); super.init(frame:.zero); setAccessibilityElement(false); setAccessibilityRole(.group); setAccessibilityLabel("Layered timeline. Select clips by clicking; use Clip panel for keyboard positioning.");registerForDraggedTypes([.string]) }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    var tracks:[Track] { Array(store.timelineDocument.sequence.tracks.reversed()) }
    func x(_ time:Double)->Double { header+time*store.pixelsPerSecond }
    private func rowLayout(_ index:Int)->TimelineTrackRow { layout.rows(for:tracks)[index] }
    func synchronizeLayout(){
        guard layout.projectID != store.timelineDocument.id else{return}
        layout.useProject(store.timelineDocument.id)
        thumbnailMetadataTask?.cancel();thumbnailMetadataTask=nil
        for task in thumbnailJobs.values{task.cancel()};thumbnailJobs.removeAll()
        thumbnailURLs.removeAll();thumbnailStamps.removeAll();thumbnailImages.removeAll();thumbnailFailures.removeAll();thumbnailRequests=[];thumbnailSignature=nil;thumbnailMetadataPoll = .distantPast
    }
    func rect(_ clip:Clip,row:Int)->NSRect {let row=rowLayout(row);return NSRect(x:x(clip.start.seconds),y:row.top+7,width:max(3,clip.duration.seconds*store.pixelsPerSecond),height:max(1,row.height-14))}
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
            if store.gridMode == .beats,let grid=store.timelineDocument.sequence.musicalGrid {
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
                let step=store.gridMode == .frames ? frameGridStep:timeGridStep
                let first=max(0,Int((lower/step).rounded(.down))), last=max(0,Int((upper/step).rounded(.up)))
                if last >= first && last-first<2000 { for i in first...last {
                    let xx=x(Double(i)*step);NSColor(white:0.22,alpha:1).setStroke()
                    let path=NSBezierPath();path.move(to:NSPoint(x:xx,y:0));path.line(to:NSPoint(x:xx,y:bounds.height));path.lineWidth=0.5;path.stroke()
                    let label=store.gridMode == .frames ? "\(Int64((Double(i)*step/store.timelineDocument.sequence.settings.frameRate.frameDuration.seconds).rounded()))f":String(format:step<1 ? "%.2fs":"%.0fs",Double(i)*step)
                    text(label,NSPoint(x:xx+5,y:9),size:10)
                } }
            }
        }
        for (row,track) in tracks.enumerated() {
            let geometry=rowLayout(row),top=geometry.top
            NSColor(white:0.2,alpha:1).setStroke();let divider=NSBezierPath();divider.move(to:NSPoint(x:0,y:geometry.bottom));divider.line(to:NSPoint(x:bounds.width,y:geometry.bottom));divider.stroke()
            for clip in track.clips {
                let box=rect(clip,row:row)
                guard box.intersects(visibleRect) else{continue}
                let startPixel=max(0,visibleRect.minX-box.minX)
                let endPixel=min(box.width,visibleRect.maxX-box.minX)
                let selected=store.selectedIDs.contains(clip.id) || store.placementProposal?.insertedClipIDs.contains(clip.id) == true
                let fill:NSColor = track.kind == .audio ? NSColor(red:0.19,green:0.34,blue:0.31,alpha:1) : track.kind == .title ? NSColor(red:0.36,green:0.30,blue:0.41,alpha:1) : NSColor(red:0.24,green:0.30,blue:0.36,alpha:1)
                fill.withAlphaComponent(track.isHidden ? 0.35 : 1).setFill(); NSBezierPath(roundedRect:box,xRadius:5,yRadius:5).fill()
                if selected { NSColor.white.withAlphaComponent(0.8).setStroke();let outline=NSBezierPath(roundedRect:box.insetBy(dx:1,dy:1),xRadius:4,yRadius:4);outline.lineWidth=1.5;outline.stroke() }
                NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:box.insetBy(dx:4,dy:2)).addClip()
                drawFilmstrip(clip,in:box)
                text(clip.name,NSPoint(x:box.minX+8,y:box.minY+6),color:.white)
                if let assetID=clip.assetID,let overview=waveforms[assetID] {
                    drawWaveform(overview,assetID:assetID,clip:clip,box:box,from:startPixel,to:endPixel)
                }

                let automationLane=displayedAutomationLane(for:clip,track:track)
                let envelope=automationLane == .volume ? clip.volume:clip.opacity
                let path=NSBezierPath()
                for pixel in stride(from:startPixel,through:endPixel,by:2) {
                    let local=RationalTime(value:Int64((pixel/pps*48000).rounded()),timescale:48000)
                    let y=automationY(envelope.value(at:local),box:box,lane:automationLane)
                    if pixel==startPixel { path.move(to:NSPoint(x:box.minX+pixel,y:y)) } else { path.line(to:NSPoint(x:box.minX+pixel,y:y)) }
                }
                NSColor.white.withAlphaComponent(0.65).setStroke();path.lineWidth=1;path.stroke()
                if store.selection == clip.id {
                    for point in envelope.points where point.time>=envelope.evaluationOffset && point.time<=envelope.evaluationOffset+clip.duration {
                        let center=automationPointPosition(point,envelope:envelope,clip:clip,box:box,lane:automationLane)
                        let selected=store.selectedAutomationPoint == point.id
                        NSColor(white:selected ? 1:0.7,alpha:1).setFill()
                        let marker=NSBezierPath();marker.move(to:NSPoint(x:center.x,y:center.y-4));marker.line(to:NSPoint(x:center.x+4,y:center.y));marker.line(to:NSPoint(x:center.x,y:center.y+4));marker.line(to:NSPoint(x:center.x-4,y:center.y));marker.close();marker.fill()
                        if selected { NSColor.black.setStroke();marker.lineWidth=1;marker.stroke() }
                    }
                    for (xx,incoming) in [(box.minX+8,true),(box.maxX-8,false)] {
                        let y=box.minY+24;let handle=NSBezierPath();handle.move(to:NSPoint(x:xx+(incoming ? -3:3),y:y-4));handle.line(to:NSPoint(x:xx+(incoming ? -3:3),y:y+4));handle.line(to:NSPoint(x:xx+(incoming ? 4:-4),y:y));handle.close();NSColor.white.setFill();handle.fill()
                    }
                    if automationDrag?.clipID == clip.id {
                        let value=store.currentAutomationPoint.map { $0.value*envelope.baseValue } ?? envelope.baseValue
                        text(AutomationScale.label(value,lane:automationLane),NSPoint(x:max(box.minX+8,visibleRect.minX+header+6),y:box.minY+20),color:.white,size:10)
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor(white:0.10,alpha:1).setFill();NSRect(x:visible.minX,y:top,width:header,height:geometry.height).fill()
            text(track.name,NSPoint(x:visible.minX+12,y:top+11),color:.labelColor)
            if geometry.height>=72 {text(track.isLocked ? "● Locked" : (track.kind == .audio ? "Audio" : "Video"),NSPoint(x:visible.minX+12,y:top+30),size:10)}
            for (i,symbol) in [track.isMuted ? "speaker.slash.fill" : "speaker.wave.2",track.isHidden ? "eye.slash" : "eye",track.isLocked ? "lock.fill" : "lock.open"].enumerated() {
                let r=NSRect(x:visible.minX+12+Double(i)*36,y:geometry.bottom-26,width:24,height:20)
                NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[NSColor(calibratedWhite:0.75,alpha:1)]))?.draw(in:r)
            }
        }
        NSColor(white:0.1,alpha:1).setFill();NSRect(x:visible.minX,y:0,width:header,height:ruler).fill()
        text("TRACKS",NSPoint(x:visible.minX+12,y:10),size:9)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:NSRect(x:visible.minX+header,y:0,width:max(0,visible.width-header),height:bounds.height)).addClip()
        for marker in store.timelineDocument.sequence.markers {
            guard let range=MarkerResolver.sequenceRange(marker,in:store.timelineDocument) else { continue }
            let xx=x(range.start.seconds), end=x(range.end.seconds)
            let markerColor=marker.color.map { NSColor(srgbRed:$0.red,green:$0.green,blue:$0.blue,alpha:$0.alpha) } ?? NSColor.systemOrange
            if range.duration > .zero {
                markerColor.withAlphaComponent(markerColor.alphaComponent*0.14).setFill();NSRect(x:xx,y:22,width:max(1,end-xx),height:bounds.height-22).fill()
                markerColor.withAlphaComponent(markerColor.alphaComponent*0.6).setFill();NSRect(x:end,y:22,width:1,height:bounds.height-22).fill()
            }
            markerColor.setFill();NSRect(x:xx,y:22,width:2,height:bounds.height-22).fill()
            text("◆",NSPoint(x:xx-5,y:4),color:markerColor)
            if !marker.name.isEmpty { text(marker.name,NSPoint(x:xx+7,y:4),color:markerColor,size:10) }
        }
        NSGraphicsContext.restoreGraphicsState()
        for transition in store.timelineDocument.sequence.transitions ?? [] {
            guard let trackIndex=tracks.firstIndex(where:{$0.id==transition.trackID}),let left=tracks[trackIndex].clips.first(where:{$0.id==transition.leftClipID}) else{continue}
            let box=transitionRect(transition,center:left.end.seconds,row:trackIndex)
            let valid=TransitionResolver.resolve(transition,in:store.timelineDocument) != nil
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
        if store.placementProposal != nil {let point=convert(event.locationInWindow,from:nil);if point.x>=visibleRect.minX+header{store.seek(max(0,(point.x-header)/store.pixelsPerSecond))};return}
        window?.makeFirstResponder(self)
        let point=convert(event.locationInWindow,from:nil)
        if point.x<visibleRect.minX+header,let boundary=layout.rows(for:tracks).first(where:{abs($0.bottom-point.y)<=4}) {
            layoutTrackSelection=boundary.trackID;resizingTrack=(boundary.trackID,Double(point.y),boundary.height);NSCursor.resizeUpDown.set();return
        }
        guard let row=layout.row(at:point.y,tracks:tracks) else {store.seek((point.x-header)/store.pixelsPerSecond);return}
        let track=tracks[row];layoutTrackSelection=track.id
        if point.x<visibleRect.minX+header {
            if point.y>=rowLayout(row).bottom-28 {
                let i=Int((point.x-visibleRect.minX-12)/36)
                if (0...2).contains(i) {store.toggleTrack(track.id,property:["mute","hide","lock"][i])}
            }
            return
        }
        for transition in store.timelineDocument.sequence.transitions ?? [] where transition.trackID==track.id {
            guard let left=track.clips.first(where:{$0.id==transition.leftClipID}) else{continue}
            let box=transitionRect(transition,center:left.end.seconds,row:row)
            if box.contains(point){
                store.selection=left.id;store.selectedTransition=transition.id;store.panel = .effects
                if !track.isLocked,abs(point.x-box.minX)<8 || abs(point.x-box.maxX)<8,
                   let maximum=try? TransitionResolver.availableDuration(leftClipID:transition.leftClipID,rightClipID:transition.rightClipID,in:store.timelineDocument,excluding:transition.id){
                    transitionResize=(transition.id,Double(point.x),transition.duration.seconds,maximum.seconds,point.x<box.midX ? -1.0:1.0);store.beginGesture()
                }
                needsDisplay=true;return
            }
        }
        store.selectedTransition=nil
        guard let clip=track.clips.first(where:{rect($0,row:row).contains(point)}) else { store.selection=nil;store.seek((point.x-header)/store.pixelsPerSecond);return }
        if event.modifierFlags.contains(.shift){store.toggleSelection(clip.id)}else if !store.selectedIDs.contains(clip.id){store.selectedIDs=[clip.id];store.selection=clip.id}else{store.selection=clip.id}
        if event.clickCount==2 { store.panel=clip.title == nil ? .clip : .title;return }
        let box=rect(clip,row:row),automationLane=displayedAutomationLane(for:clip,track:track)
        let envelope=automationLane == .volume ? clip.volume:clip.opacity
        let keyframes=envelope.points.filter { $0.time>=envelope.evaluationOffset && $0.time<=envelope.evaluationOffset+clip.duration }
        if let keyframe=keyframes.first(where: { keyframe in
            let center=automationPointPosition(keyframe,envelope:envelope,clip:clip,box:box,lane:automationLane)
            return hypot(center.x-point.x,center.y-point.y)<=7
        }) {
            store.selectedAutomationPoint=keyframe.id
            if !track.isLocked { automationDrag=AutomationDrag(clipID:clip.id,lane:automationLane,mode:.point(keyframe.id),origin:point,envelope:envelope);store.beginGesture() }
            needsDisplay=true;return
        }
        let local=min(clip.duration.seconds,max(0,(point.x-header)/store.pixelsPerSecond-clip.start.seconds))
        let lineY=automationY(envelope.value(at:store.time(local,audio:true)),box:box,lane:automationLane)
        if event.modifierFlags.contains(.command),abs(point.y-lineY)<=9 {
            var sequenceTime=clip.start.seconds+local
            if store.snapping && !event.modifierFlags.contains(.option),let snap=snappedTime(sequenceTime) { sequenceTime=snap.time }
            store.addAutomationPoint(at:sequenceTime,effectiveValue:automationValue(point.y,box:box,lane:automationLane));needsDisplay=true;return
        }
        guard !track.isLocked else{return}
        let fadeIn=abs(point.x-(box.minX+8))<=8 && abs(point.y-(box.minY+24))<=7
        let fadeOut=abs(point.x-(box.maxX-8))<=8 && abs(point.y-(box.minY+24))<=7
        if fadeIn || fadeOut || (abs(point.y-lineY)<=5 && point.x>box.minX+12 && point.x<box.maxX-12) {
            store.selectedAutomationPoint=nil
            automationDrag=AutomationDrag(clipID:clip.id,lane:automationLane,mode:fadeIn ? .fadeIn:(fadeOut ? .fadeOut:.base),origin:point,envelope:envelope);store.beginGesture();needsDisplay=true;return
        }
        store.selectedAutomationPoint=nil
        let mode:Mode = point.x<box.minX+12 ? .left : point.x>box.maxX-12 ? .right : .move
        drag=Drag(clip:clip,track:track,origin:point,mode:mode,target:mode == .right ? clip.end.seconds : clip.start.seconds)
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard store.placementProposal == nil else{return}
        if let resize=resizingTrack {let point=convert(event.locationInWindow,from:nil);_ = setTrackHeight(resize.height+point.y-resize.originY,for:resize.id);return}
        if let gesture=automationDrag,let clip=store.selectedClip,clip.id == gesture.clipID,let row=tracks.firstIndex(where: { $0.clips.contains { $0.id == clip.id } }) {
            let point=convert(event.locationInWindow,from:nil),box=rect(clip,row:row)
            snapX=nil;snapLabel=nil
            var sequenceTime=min(clip.end.seconds,max(clip.start.seconds,(point.x-header)/store.pixelsPerSecond))
            let excludedPoint:UUID?
            if case .point(let id)=gesture.mode { excludedPoint=id } else { excludedPoint=nil }
            if store.snapping && !event.modifierFlags.contains(.option),let snap=snappedTime(sequenceTime,excludingPoint:excludedPoint) {
                sequenceTime=min(clip.end.seconds,max(clip.start.seconds,snap.time));snapX=x(sequenceTime);snapLabel=snap.label
            }
            switch gesture.mode {
            case .point(let id):store.updateAutomationPoint(id:id,sequenceTime:sequenceTime,effectiveValue:automationValue(point.y,box:box,lane:gesture.lane))
            case .base:
                let value=gesture.lane == .volume ? (gesture.envelope.baseValue == 0 ? AutomationScale.value((gesture.origin.y-point.y)/40,lane:.volume):gesture.envelope.baseValue*pow(10,(gesture.origin.y-point.y)*0.75/20)):gesture.envelope.baseValue+(gesture.origin.y-point.y)/30
                store.setAutomationBase(max(0,min(gesture.lane.maximumValue,value)));snapX=nil;snapLabel=nil
            case .fadeIn:store.setLaneFade(sequenceTime-clip.start.seconds,incoming:true,source:gesture.envelope)
            case .fadeOut:store.setLaneFade(clip.end.seconds-sequenceTime,incoming:false,source:gesture.envelope)
            }
            needsDisplay=true;return
        }
        if let resize=transitionResize {
            let point=convert(event.locationInWindow,from:nil)
            let minimum=store.timelineDocument.sequence.settings.frameRate.frameDuration.seconds
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
        guard store.placementProposal == nil else{drag=nil;automationDrag=nil;transitionResize=nil;resizingTrack=nil;ghost=nil;snapX=nil;snapLabel=nil;return}
        if resizingTrack != nil {resizingTrack=nil;NSCursor.arrow.set();return}
        if automationDrag != nil { automationDrag=nil;snapX=nil;snapLabel=nil;store.endGesture();needsDisplay=true;return }
        if transitionResize != nil {transitionResize=nil;store.endGesture();return}
        defer{drag=nil;ghost=nil;snapX=nil;snapLabel=nil;needsDisplay=true}
        guard let drag else{return}
        let audio=drag.track.kind == .audio
        switch drag.mode {
        case .move:if abs(drag.target-drag.clip.start.seconds)>0.000001 {store.apply(.moveMany(clipIDs:store.selectedIDs,delta:store.time(drag.target,audio:audio)-drag.clip.start))}
        case .left:if abs(drag.target-drag.clip.start.seconds)>0.000001 {store.apply(.trim(clipID:drag.clip.id,start:store.time(drag.target,audio:audio),end:drag.clip.end))}
        case .right:if abs(drag.target-drag.clip.end.seconds)>0.000001 {store.apply(.trim(clipID:drag.clip.id,start:drag.clip.start,end:store.time(drag.target,audio:audio)))}
        case .fadeIn,.fadeOut:break // Fade handles use the shared automation gesture above.
        }
    }
    private func drawWaveform(_ overview:WaveformOverview,assetID:UUID,clip:Clip,box:NSRect,from lower:Double,to upper:Double) {
        let pyramid=overview.pyramid,rate=pyramid.sampleRate,samplesPerPixel=rate*clip.speed/store.pixelsPerSecond
        guard let level=pyramid.level(samplesPerPixel:samplesPerPixel),lower<=upper else{return}
        let channelHeight=max(8,box.height-29)/Double(max(1,pyramid.channelCount)),top=box.minY+24
        for channel in 0..<pyramid.channelCount {
            let center=top+(Double(channel)+0.5)*channelHeight,amplitude=max(1,channelHeight/2-1)
            let path=NSBezierPath()
            if samplesPerPixel<=1 {
                var began=false
                let first=max(0,Int64(floor((clip.sourceStart.seconds+lower/store.pixelsPerSecond*clip.speed)*rate)))
                let last=min(pyramid.sampleCount-1,Int64(ceil((clip.sourceStart.seconds+upper/store.pixelsPerSecond*clip.speed)*rate)))
                if last>=first,last-first<10000 {
                    for index in first...last {
                        let key=sampleKey(assetID,overview.sourceKey,index/65536)
                        guard let window=sampleWindows[key],window.channels.indices.contains(channel) else{began=false;continue}
                        let offset=Int(index-window.firstSample);guard window.channels[channel].indices.contains(offset) else{began=false;continue}
                        let xx=box.minX+(Double(index)/rate-clip.sourceStart.seconds)/clip.speed*store.pixelsPerSecond,y=center-Double(min(1,max(-1,window.channels[channel][offset])))*amplitude
                        if began{path.line(to:NSPoint(x:xx,y:y))}else{path.move(to:NSPoint(x:xx,y:y));began=true}
                        if samplesPerPixel<0.2 {NSColor.white.withAlphaComponent(0.45).setFill();NSBezierPath(ovalIn:NSRect(x:xx-1.5,y:y-1.5,width:3,height:3)).fill()}
                    }
                }
            } else {
                for pixel in stride(from:lower,through:upper,by:1) {
                    let index=max(0,Int64(floor((clip.sourceStart.seconds+pixel/store.pixelsPerSecond*clip.speed)*rate)))
                    let end=min(pyramid.sampleCount,max(index+1,index+Int64(ceil(samplesPerPixel))))
                    var low:Float=0,high:Float=0
                    if let detailed=sampleBin(assetID:assetID,source:overview.sourceKey,channel:channel,from:index,to:end) {
                        low=detailed.minimum;high=detailed.maximum
                    } else {
                        let bin=Int(index/level.samplesPerBin)
                        if level.channels[channel].indices.contains(bin) {low=level.channels[channel][bin].minimum;high=level.channels[channel][bin].maximum}
                    }
                    let y1=center-Double(max(-1,min(1,high)))*amplitude,y2=center-Double(max(-1,min(1,low)))*amplitude
                    path.move(to:NSPoint(x:box.minX+pixel,y:y1));path.line(to:NSPoint(x:box.minX+pixel,y:max(y1+0.5,y2)))
                }
            }
            NSColor.white.withAlphaComponent(0.24).setStroke();path.lineWidth=0.75;path.stroke()
            if pyramid.channelCount>1 && channelHeight>=10 {text(pyramid.channelCount == 2 ? (channel == 0 ? "L":"R") : "\(channel+1)",NSPoint(x:box.minX+5,y:center-5),color:.white.withAlphaComponent(0.5),size:8)}
        }
    }
    private func sampleBin(assetID:UUID,source:String,channel:Int,from first:Int64,to last:Int64)->WaveformBin? {
        guard last>first,last-first<=128 else{return nil}
        var cursor=first,low=Float.infinity,high = -Float.infinity
        while cursor<last {
            let key=sampleKey(assetID,source,cursor/65536)
            guard let window=sampleWindows[key],window.channels.indices.contains(channel),cursor>=window.firstSample,cursor<window.lastSample else{return nil}
            let end=min(last,window.lastSample)
            for index in Int(cursor-window.firstSample)..<Int(end-window.firstSample) {
                let value=window.channels[channel][index];guard value.isFinite else{continue};low=min(low,value);high=max(high,value)
            }
            cursor=end
        }
        return low.isFinite && high.isFinite ? WaveformBin(minimum:low,maximum:high):nil
    }
    private func displayedAutomationLane(for clip:Clip,track:Track)->AutomationLane {
        if store.selection == clip.id { return store.automationLane }
        return (track.kind == .audio || track.kind == .video) ? .volume:.opacity
    }
    private func automationY(_ value:Double,box:NSRect,lane:AutomationLane)->Double { box.maxY-8-AutomationScale.position(value,lane:lane)*max(12,min(80,box.height-34)) }
    private func automationValue(_ y:Double,box:NSRect,lane:AutomationLane)->Double { AutomationScale.value((box.maxY-8-y)/max(12,min(80,box.height-34)),lane:lane) }
    private func automationPointPosition(_ point:AutomationPoint,envelope:AutomationEnvelope,clip:Clip,box:NSRect,lane:AutomationLane)->NSPoint {
        NSPoint(x:x(clip.start.seconds+(point.time-envelope.evaluationOffset).seconds),y:automationY(point.value*envelope.baseValue,box:box,lane:lane))
    }
    private var frameGridStep:Double {
        let frame=store.timelineDocument.sequence.settings.frameRate.frameDuration.seconds
        return frame*max(1,ceil(80/store.pixelsPerSecond/frame))
    }
    private var timeGridStep: Double { [0.01,0.05,0.1,0.25,0.5,1,2,5,10,30,60,120,300].first { $0>=80/store.pixelsPerSecond } ?? 600 }
    /// Explicit edits take priority over a closer ordinary grid division, within eight screen pixels.
    func snappedTime(_ target: Double, excluding: Set<UUID> = [], excludingPoint:UUID? = nil) -> (time:Double,label:String)? {
        var explicit:[(time:Double,label:String)]=store.timelineDocument.sequence.tracks.flatMap(\.clips).filter { !excluding.contains($0.id) }.flatMap { [($0.start.seconds,"Clip"),($0.end.seconds,"Clip")] }
        for marker in store.timelineDocument.sequence.markers {
            guard let range=MarkerResolver.sequenceRange(marker,in:store.timelineDocument) else { continue }
            let label=marker.name.isEmpty ? "Marker":marker.name
            explicit.append((range.start.seconds,label));if range.duration > .zero { explicit.append((range.end.seconds,label)) }
        }
        for clip in store.timelineDocument.sequence.tracks.flatMap(\.clips) where !excluding.contains(clip.id) {
            for envelope in [clip.volume,clip.opacity] {
                for point in envelope.points where point.id != excludingPoint && point.time>=envelope.evaluationOffset && point.time<=envelope.evaluationOffset+clip.duration {
                    explicit.append((clip.start.seconds+(point.time-envelope.evaluationOffset).seconds,"Point"))
                }
            }
        }
        explicit.append((store.playhead,"Playhead"))
        let candidates=explicit.filter { $0.time >= 0 && abs($0.time-target)*store.pixelsPerSecond<=8 }
        if let nearest=candidates.min(by:{abs($0.time-target)<abs($1.time-target)}) { return nearest }
        let gridTarget:Double
        let label:String
        if store.gridMode == .beats,let grid=store.timelineDocument.sequence.musicalGrid,let nearest=grid.nearestDivision(to:store.time(max(0,target),audio:true)) { gridTarget=nearest.time.seconds;label=nearest.isBar ? "Bar":"Beat" }
        else if store.gridMode == .frames { gridTarget=store.timelineDocument.sequence.settings.frameRate.quantized(store.time(target,audio:true)).seconds;label="Frame" }
        else { gridTarget=(target/timeGridStep).rounded()*timeGridStep;label="Grid" }
        return gridTarget >= 0 && abs(gridTarget-target)*store.pixelsPerSecond<=8 ? (gridTarget,label):nil
    }
    private func snapExclusions(for drag:Drag)->Set<UUID> {
        let clips=store.timelineDocument.sequence.tracks.flatMap(\.clips)
        var ids=drag.mode == .move ? store.selectedIDs.union([drag.clip.id]):[drag.clip.id]
        while true {
            let members=clips.filter { ids.contains($0.id) }, links=Set(members.compactMap(\.linkID)),groups=Set(members.compactMap(\.groupID)), prior=ids
            for clip in clips where clip.linkID.map(links.contains) == true || (drag.mode == .move && clip.groupID.map(groups.contains) == true) { ids.insert(clip.id) }
            if ids == prior { return ids }
        }
    }
    private func transitionRect(_ transition:VideoTransition,center:Double,row:Int)->NSRect{
        NSRect(x:x(center-transition.duration.seconds/2),y:rowLayout(row).top+29,width:max(12,transition.duration.seconds*store.pixelsPerSecond),height:22)
    }
    private func dropPair(_ sender:any NSDraggingInfo)->(Clip,Clip)? {
        guard store.placementProposal == nil else{return nil}
        guard let value=sender.draggingPasteboard.string(forType:.string),value.hasPrefix("life.transition."),TransitionKind(rawValue:String(value.dropFirst("life.transition.".count))) != nil else{return nil}
        let point=convert(sender.draggingLocation,from:nil)
        guard let row=layout.row(at:point.y,tracks:tracks),tracks[row].kind != .audio,!tracks[row].isLocked else{return nil}
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
        if store.placementProposal != nil {if event.keyCode==123{store.step(-1)}else if event.keyCode==124{store.step(1)};return}
        if !event.isARepeat,store.panel == .multicam,let chars=event.charactersIgnoringModifiers,let digit=Int(chars),(1...9).contains(digit),store.visibleAngles.indices.contains(digit-1) {store.chooseAngle(store.visibleAngles[digit-1].id);return}
        if event.modifierFlags.contains(.option),(event.keyCode==125 || event.keyCode==126) {
            let id=layoutTrackSelection ?? tracks.first(where:{$0.clips.contains{$0.id==store.selection}})?.id ?? tracks.first?.id
            if let id{_ = resizeTrack(id,by:event.keyCode==126 ? -16:16)};return
        }
        if event.keyCode==51,store.currentAutomationPoint != nil {store.deleteAutomationPoint();return}
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

@MainActor private final class TimelineHeightElement:NSAccessibilityElement {
    nonisolated let incrementAction:@MainActor @Sendable()->Bool
    nonisolated let decrementAction:@MainActor @Sendable()->Bool
    init(increment:@escaping @MainActor @Sendable()->Bool,decrement:@escaping @MainActor @Sendable()->Bool){incrementAction=increment;decrementAction=decrement;super.init()}
    nonisolated override func accessibilityPerformIncrement()->Bool{let action=incrementAction;return MainActor.assumeIsolated{action()}}
    nonisolated override func accessibilityPerformDecrement()->Bool{let action=decrementAction;return MainActor.assumeIsolated{action()}}
}
