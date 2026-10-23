import SwiftUI
import AVKit
import UniformTypeIdentifiers
import LifeCore
import LifeMedia
import LifeAnalysis

enum TimelineGridMode:String {case time,frames,beats}

@MainActor
final class EditorStore: ObservableObject {
    @Published var playbackMeter:PlaybackMeterReading?
    @Published var playbackMeterClipped=false
    @Published var playbackMeterUnavailable=false
    private(set) var playbackMeterVisible=false
    private var playbackMeterTick:Task<Void,Never>?
    private var playbackMeterJob:Task<Void,Never>?
    private var playbackMeterSource:PlaybackMeterSource?
    private var playbackMeterGeneration=0
    private var lastPlaybackMeterTime:RationalTime?
    private var pendingPlaybackMeterTime:RationalTime?
    func setPlaybackMeterVisible(_ visible:Bool){
        guard visible != playbackMeterVisible else{return};playbackMeterVisible=visible
        playbackMeterTick?.cancel();playbackMeterTick=nil;invalidatePlaybackMeter()
        guard visible else{return}
        requestPlaybackMeter()
        playbackMeterTick=Task{[weak self] in
            while !Task.isCancelled{
                do{try await Task.sleep(for:.milliseconds(100))}catch{return}
                guard let self,self.playbackMeterVisible else{return};self.requestPlaybackMeter()
            }
        }
    }
    func invalidatePlaybackMeter(){
        playbackMeterGeneration+=1;playbackMeterJob?.cancel();playbackMeterJob=nil;playbackMeterSource=nil
        pendingPlaybackMeterTime=nil;lastPlaybackMeterTime=nil;playbackMeter=nil;playbackMeterUnavailable=false
    }
    private func requestPlaybackMeter(){
        guard playbackMeterVisible else{return}
        guard let item=player.currentItem else{invalidatePlaybackMeter();return}
        if playbackMeterSource?.matches(item) != true{invalidatePlaybackMeter();playbackMeterSource=PlaybackMeterSource(item:item)}
        let time=playheadTime
        if playbackMeterJob != nil{pendingPlaybackMeterTime=time;return}
        guard lastPlaybackMeterTime != time,let source=playbackMeterSource else{return}
        lastPlaybackMeterTime=time;let generation=playbackMeterGeneration
        playbackMeterJob=Task{[weak self] in
            do{
                let reading=try await PlaybackAudioMeter.read(source,at:time)
                guard !Task.isCancelled,let self,self.playbackMeterVisible,generation==self.playbackMeterGeneration,let item=self.player.currentItem,source.matches(item) else{return}
                if abs(self.playhead-time.seconds)<=0.25{
                    self.playbackMeter=reading;self.playbackMeterUnavailable=false
                    if reading.frame.leftDBFS>=0 || reading.frame.rightDBFS>=0{self.playbackMeterClipped=true}
                }else{self.playbackMeter=nil}
            }catch{
                if !Task.isCancelled,let self,generation==self.playbackMeterGeneration{self.playbackMeter=nil;self.playbackMeterUnavailable=true}
            }
            guard !Task.isCancelled,let self,generation==self.playbackMeterGeneration else{return}
            self.playbackMeterJob=nil
            if let next=self.pendingPlaybackMeterTime{self.pendingPlaybackMeterTime=nil;if next != time{self.requestPlaybackMeter()}}
        }
    }
    @Published var document = ProjectDocument()
    @Published var placementProposal:PlacementProposal?
    @Published var placementTitle="Insert"
    private var placementBaseline:ProjectDocument?
    var timelineDocument:ProjectDocument{placementProposal?.document ?? document}
    @Published var selectedTransition:UUID?{didSet{if oldValue != selectedTransition{cancelColorSampling()}}}
    @Published var selectedIDs:Set<UUID>=[]
    @Published var selectedAutomationPoint:UUID?
    @Published var automationLane:AutomationLane = .volume
    @Published var selection: UUID? {didSet{if let selection {if !selectedIDs.contains(selection){selectedIDs=[selection]}}else{selectedIDs=[]};if oldValue != selection{cancelColorSampling();selectedAutomationPoint=nil;automationLane=selectedUsesOpacity ? .opacity:.volume}}}
    @Published var playheadTime:RationalTime = .zero
    var playhead:Double {get{playheadTime.seconds}set{playheadTime=time(newValue,audio:true)}}
    @Published var playing = false
    @Published var busy = false
    @Published var importProgress:Double=0
    private var importTask:Task<Void,Never>?
    @Published var exporting = false
    @Published var showExport=false
    @Published var exportProgress:Double=0
    @Published var preparing=false
    @Published var previewUsesProxies=false
    @Published var transcribing=false
    @Published var normalization:PeakNormalizationSuggestion?
    private var normalizationClip:Clip?
    @Published var measuringAudio=false
    @Published var audioMeasurement:AudioMeasurement?
    @Published var audioMeters:[AudioMeterFrame]=[]
    private var audioMeasurementTask:Task<Void,Never>?
    @Published var cacheBytes:Int64=0
    private let transcription=LocalTranscription()
    private var transcriptionTask:Task<Void,Never>?
    private var angleProxyTasks:[UUID:Task<Void,Never>]=[:]
    @Published var error: String?
    @Published var panel: InspectorPanel? = nil
    @Published var snapping = true
    @Published var pixelsPerSecond: Double = 60
    @Published var samplingColor=false
    private var colorSampleAction:((RGBAColor)->Void)?
    private var videoOutput:AVPlayerItemVideoOutput?
    @Published var safeAreas = false
    @Published var focused = false
    @Published var autosaveError:String?
    @Published var dirty = false
    @Published var analyzing = false
    @Published var analysisConfidence: Double?
    @Published var gridMode:TimelineGridMode = .time
    @Published var gridVisible = true
    @Published var switchMode:MulticamSwitchMode = .video{didSet{if oldValue != switchMode{clearAngleAudition()}}}
    @Published var cameraAudioIDs:Set<UUID>=[]
    @Published var checkingCameraAudio=false
    private var cameraAudioTask:Task<Void,Never>?
    private var cameraAudioSignature=""
    @Published var switchArmed = false
    @Published var syncCandidates:[CameraSyncCandidate]=[]
    @Published var syncMethod:CameraSyncMethod = .waveform{didSet{if oldValue != syncMethod{cancelSynchronization()}}}
    @Published private(set) var syncReferenceID:UUID?
    private var syncBaseline:ProjectDocument?
    private var syncGeneration=0
    @Published var synchronizing=false
    @Published var syncPreviewing=false
    private var syncTask:Task<Void,Never>?
    private var previewDocument:ProjectDocument?
    private var playbackDocument:ProjectDocument{previewDocument ?? document}
    @Published var auditionAngle: UUID?
    @Published var cameraPage = 0
    @Published var recoverable:[ProjectDocument]=[]
    @Published var drawingMode=0
    @Published var drawingColor=RGBAColor.white
    @Published var drawingWidth=0.006
    let audioAnalyzer = AudioAnalyzer()
    private var analysisTask:Task<Void,Never>?
    private var tapTimes:[Date]=[]
    private var cameraPlayers:[UUID:AVPlayer]=[:]
    @Published var replaceSwitchRange=false
    @Published var switchRangeStart:Double=0
    @Published var switchRangeEnd:Double=10
    private var activeSwitchRange:(start:RationalTime,end:RationalTime)?
    private var recordedRangeCuts:[MulticamCut]=[]
    private var recordedRangeAudioCuts:[MulticamCut]=[]
    private var rangeOriginalGroup:MulticamGroup?
    private var recordingPass = false
    let player = AVPlayer()
    private let media = MediaPipeline()
    private var editor = ProjectEditor()
    private var projectURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var observer: Any?
    private var generation = 0
    private var projectGeneration = 0
    enum InspectorPanel: String, CaseIterable { case media, title, clip, audio, multicam, effects, drawing, markers }
    init() {
        player.automaticallyWaitsToMinimizeStalling=false
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.playheadTime = time.seconds.isFinite && time.timescale>0 ? RationalTime(value:time.value,timescale:Int64(time.timescale)):.zero
                if self.playing && (self.playhead >= self.playbackDocument.sequence.duration.seconds || self.activeSwitchRange.map({self.playhead >= $0.end.seconds}) == true) { self.stopPlayback() }
            }
        }
    }
    var selectedClip: Clip? { document.sequence.tracks.flatMap(\.clips).first { $0.id == selection } }
    var canUndo: Bool { placementProposal != nil || editor.canUndo }
    var canRedo: Bool { placementProposal == nil && editor.canRedo }
    func time(_ seconds: Double, audio: Bool = false) -> RationalTime {
        let bounded = seconds.isFinite ? min(86400,max(0,seconds)) : 0
        let raw = RationalTime(value: Int64((bounded * 48000).rounded()), timescale: 48000)
        return audio ? raw : document.sequence.settings.frameRate.quantized(raw)
    }
    func apply(_ command: EditCommand) {
        do { if placementProposal != nil{error="Apply or cancel the placement preview first.";return};if recordingPass {error="Stop the switching pass before editing clips.";return}; try editor.perform(command); changed() } catch { self.error = Self.message(error) }
    }
    func replace(_ new: ProjectDocument) { apply(.replace(new)) }
    func previewPlacement(_ command:EditCommand,title:String){
        guard !recordingPass else{error="Stop the switching pass before placing clips.";return}
        do{
            let proposal=try SpliceEditing.proposal(for:command,in:document)
            stopPlayback();placementBaseline=document;placementTitle=title;placementProposal=proposal
            rebuild(preview:proposal.document,synchronization:false)
            seek(proposal.start)
        }catch{self.error=Self.message(error)}
    }
    func commitPlacement(){
        guard let proposal=placementProposal,document==placementBaseline else{error="The project changed. Preview this placement again.";cancelPlacement();return}
        placementProposal=nil;placementBaseline=nil
        apply(.replace(proposal.document))
        if !proposal.insertedClipIDs.isEmpty{selectedIDs=proposal.insertedClipIDs;selection=selectedIDs.first}
    }
    func cancelPlacement(){placementProposal=nil;placementBaseline=nil;rebuild()}
    func changed() {
        audioMeasurementTask?.cancel(); measuringAudio=false; audioMeasurement=nil; audioMeters=[];normalization=nil;normalizationClip=nil
        document = editor.document; dirty = true; MediaBookmarks().remember(document); scheduleRecovery(); rebuild()
    }
    func undo() { if placementProposal != nil{cancelPlacement();return};editor.undo(); changed() }
    func redo() { if placementProposal != nil{cancelPlacement();return};editor.redo(); changed() }
    func rebuild(preview:ProjectDocument? = nil,synchronization:Bool=true) {
        invalidatePlaybackMeter()
        refreshCameraAudio()
        syncPreviewing=preview != nil && synchronization;previewDocument=preview
        if (preview ?? document).sequence.duration == .zero { refreshTask?.cancel();videoOutput=nil;cancelColorSampling(); player.replaceCurrentItem(with:nil); return }
        generation += 1; let token = generation
        refreshTask?.cancel()
        let snapshot = ProjectSnapshot(document:preview ?? document)
        preparing=true
        refreshTask = Task {
            defer {if token==generation{preparing=false}}
            do {
                let prepared = try await media.prepare(snapshot,useProxies:true)
                guard !Task.isCancelled, token == generation else { return }
                previewUsesProxies=prepared.usesProxies
                let position = playhead
                let output=AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]);prepared.playerItem.add(output);videoOutput=output
                player.replaceCurrentItem(with: prepared.playerItem)
                seek(position)
                if playing { player.play() }
            } catch { if !Task.isCancelled { self.error = Self.message(error) } }
        }
    }
    func beginColorSampling(_ apply:@escaping(RGBAColor)->Void){
        guard videoOutput != nil else{error="Load a visual frame before sampling a color.";return}
        stopPlayback();colorSampleAction=apply;samplingColor=true
    }
    func cancelColorSampling(){samplingColor=false;colorSampleAction=nil}
    func sampleViewerColor(x:Double,y:Double){
        guard samplingColor else{return}
        guard let buffer=videoOutput?.copyPixelBuffer(forItemTime:player.currentTime(),itemTimeForDisplay:nil),let color=ViewerColorSampler.sample(buffer,x:x,y:y) else{error="Seek to a visible frame and sample again.";cancelColorSampling();return}
        let action=colorSampleAction;cancelColorSampling();action?(color)
    }
    func seek(_ seconds:Double){seek(time(seconds,audio:true))}
    func seek(_ exact:RationalTime){
        let position=min(max(.zero,exact),max(.zero,playbackDocument.sequence.duration))
        playheadTime=position
        invalidatePlaybackMeter();requestPlaybackMeter()
        synchronizeCameraPlayers(position.seconds,playing:playing)
        player.seek(to:CMTime(value:position.value,timescale:CMTimeScale(position.timescale)),toleranceBefore:.zero,toleranceAfter:.zero)
    }
    func togglePlayback() {
        if playing { stopPlayback();return }
        if playhead >= playbackDocument.sequence.duration.seconds { seek(0) }
        if switchArmed && document.sequence.multicamGroups.last != nil {
            if replaceSwitchRange {
                let start=time(switchRangeStart),end=time(min(switchRangeEnd,document.sequence.duration.seconds))
                guard end>start else{error="Choose a nonempty switching range.";return}
                activeSwitchRange=(start,end);recordedRangeCuts=[];recordedRangeAudioCuts=[];rangeOriginalGroup=multicamGroup;seek(start)
            }
            beginGesture();recordingPass=true
            if let range=activeSwitchRange,let original=rangeOriginalGroup {
                do{
                    let cleared=try replacingPass(in:original,from:range.start,to:range.end)
                    var next=document;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1]=cleared
                    try editor.perform(.replace(next));document=editor.document;dirty=true;scheduleRecovery()
                    let initial=cleared.cuts.last(where:{$0.time<=range.start})?.angleID
                    if let item=player.currentItem{if switchMode != .audio{auditionAngle=initial;media.audition(angleID:initial,on:item)};if switchMode != .video{media.auditionAudio(assetID:MulticamSwitching.selectedAudio(in:cleared,at:range.start) ?? MulticamSwitching.silenceAudioID,on:item)}}
                }catch{recordingPass=false;activeSwitchRange=nil;rangeOriginalGroup=nil;endGesture();self.error=Self.message(error);return}
            }
        }
        player.play();playing=true
        synchronizeCameraPlayers(playhead,playing:true)
    }
    func stopPlayback() {
        player.pause();playing=false
        cameraPlayers.values.forEach{$0.pause()}
        if recordingPass {recordingPass=false;activeSwitchRange=nil;rangeOriginalGroup=nil;recordedRangeCuts=[];recordedRangeAudioCuts=[];endGesture();rebuild()}
        clearAngleAudition()
    }
    func step(_ direction:Int){stopPlayback();do{let rate=document.sequence.settings.frameRate,current=try rate.checkedQuantized(playheadTime);seek(try current.checkedAdding(rate.frameDuration.checkedScaled(by:direction<0 ? -1:1)))}catch{self.error=Self.message(error)}}
    func importMedia() {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true
        picker.allowedContentTypes = [.movie, .audio, .image];picker.allowsOtherFileTypes=true
        guard picker.runModal() == .OK else { return }
        let urls = picker.urls;busy=true;importProgress=0
        let importGeneration = projectGeneration
        importTask=Task {
            defer { busy = false }
            do {
                var probes: [(URL, MediaProbe)] = []
                for url in urls { probes.append((url,try await media.probe(url,progress:{[weak self] p in self?.importProgress=p})));try Task.checkCancellation() }
                guard importGeneration == projectGeneration else { return }
                var next = document
                for (url, probe) in probes {
                    let firstVideo = !next.assets.contains { $0.kind == .video }
                    next.assets.append(probe.asset)
                    if probe.hasVideo && firstVideo {
                        next.sequence.settings.width = probe.width; next.sequence.settings.height = probe.height
                        if probe.frameRate > 0 {
                            let known: [(Double, FrameRate)] = [(29.97,.init(numerator:30000,denominator:1001)),(59.94,.init(numerator:60000,denominator:1001)),(23.976,.init(numerator:24000,denominator:1001))]
                            next.sequence.settings.frameRate = known.first(where: { abs($0.0-probe.frameRate)<0.02 })?.1 ?? .init(numerator: Int64(probe.frameRate.rounded()))
                        }
                    }
                    let clip = Clip(name: url.deletingPathExtension().lastPathComponent, assetID: probe.asset.id, start: time(playhead, audio: !probe.hasVideo), duration: probe.asset.duration)
                    next.sequence.tracks.append(Track(name: clip.name, kind: probe.asset.kind == .image ? .image : probe.hasVideo ? .video : .audio, clips: [clip]))
                    selection = clip.id
                }
                replace(next)
            } catch { self.error = Self.message(error) }
        }
    }
    var currentTransition:VideoTransition?{document.sequence.transitions?.first{$0.id==selectedTransition}}
    func transitionPair()->(Clip,Clip)?{
        if let transition=currentTransition,
            let left=document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==transition.leftClipID}),let right=document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==transition.rightClipID}) {return(left,right)}
        guard let selected=selection,let track=document.sequence.tracks.first(where:{$0.kind != .audio && $0.clips.contains(where:{$0.id==selected})}) else{return nil}
        let clips=track.clips.sorted{$0.start<$1.start}
        let pairs=Array(zip(clips,clips.dropFirst())).filter{$0.end==$1.start && ($0.id==selected || $1.id==selected)}
        return pairs.min{abs($0.0.end.seconds-playhead)<abs($1.0.end.seconds-playhead)}
    }
    func applyTransition(_ kind:TransitionKind,left:UUID,right:UUID){
        do{
            let existing=document.sequence.transitions?.first{$0.leftClipID==left && $0.rightClipID==right}
            let available=try TransitionResolver.availableDuration(leftClipID:left,rightClipID:right,in:document,excluding:existing?.id)
            guard available > .zero else{error="Not enough source handles. Trim the clips to reveal more recording.";return}
            let duration=min(RationalTime(value:1,timescale:1),available)
            if let existing{selectedTransition=existing.id;editTransition{$0.kind=kind;$0.duration=min($0.duration,available)}}
            else{apply(.addTransition(leftClipID:left,rightClipID:right,kind:kind,duration:duration));selectedTransition=document.sequence.transitions?.last?.id}
        }catch{self.error=Self.message(error)}
    }
    func setTransitionDuration(_ seconds:Double){
        guard seconds.isFinite,seconds>0,let transition=currentTransition else{return}
        apply(.setTransitionDuration(id:transition.id,duration:time(seconds)))
    }
    func editTransition(_ update:(inout VideoTransition)->Void){
        guard let id=selectedTransition else{return};var next=document
        guard let index=next.sequence.transitions?.firstIndex(where:{$0.id==id}) else{return}
        update(&next.sequence.transitions![index]);replace(next)
    }
    func addShape(_ kind:ShapeKind){
        var next=document
        let shape=ShapeContent(kind:kind,fill:(kind == .line || kind == .arrow) ? .clear:.white,stroke:.white)
        let clip=Clip(name:kind.rawValue,start:time(playhead),duration:RationalTime(value:3,timescale:1),graphic:.shape(shape))
        next.sequence.tracks.append(Track(name:"Shape",kind:.shape,clips:[clip]));replace(next);selection=clip.id;panel = .clip;drawingMode=0
    }
    func commitDrawing(_ points:[GraphicPoint]){
        guard !points.isEmpty else{return}
        if drawingMode==3 {
            editSelected{clip in
                guard case .drawing(var drawing)=clip.graphic else{return}
                let resolution=max(32,min(512,Int(1/max(0.002,drawingWidth))))
                let cells=Set(points.map{Int(($0.x*Double(resolution)).rounded())+(resolution+1)*Int(($0.y*Double(resolution)).rounded())})
                drawing.strokes.removeAll{stroke in stroke.points.contains{p in
                    let x=Int((p.x*Double(resolution)).rounded()),y=Int((p.y*Double(resolution)).rounded())
                    for dy in -1...1 {for dx in -1...1 where cells.contains(x+dx+(resolution+1)*(y+dy)){return true}}
                    return false
                }}
                clip.graphic = .drawing(drawing)
            }
        }else{
            let stroke=DrawingStroke(points:Array(points.prefix(10000)),color:drawingColor,width:drawingWidth,tool:drawingMode==2 ? .highlighter:.pen)
            if let clip=selectedClip,case .drawing=clip.graphic,clip.start.seconds<=playhead,playhead<clip.end.seconds {
                editSelected{clip in guard case .drawing(var drawing)=clip.graphic else{return};drawing.strokes.append(stroke);clip.graphic = .drawing(drawing)}
            }else{
                var next=document
                let clip=Clip(name:"Drawing",start:time(playhead),duration:RationalTime(value:3,timescale:1),graphic:.drawing(DrawingContent(strokes:[stroke])))
                next.sequence.tracks.append(Track(name:"Drawing",kind:.drawing,clips:[clip]));replace(next);selection=clip.id
            }
        }
    }
    var selectedUsesOpacity:Bool {
        if selectedIsAdjustment{return true}
        guard let clip=selectedClip else{return false}
        return clip.title != nil || clip.graphic != nil || document.assets.first(where:{$0.id==clip.assetID})?.kind == .image
    }
    func addTitle() {
        var next = document
        let clip = Clip(name: "Title", start: time(playhead), duration: RationalTime(value: 3,timescale: 1), opacity:.init(points:[.init(time:.zero,value:0),.init(time:.init(value:1,timescale:4),value:1),.init(time:.init(value:11,timescale:4),value:1),.init(time:.init(value:3,timescale:1),value:0)]), title: .init(text: "Title"))
        next.sequence.tracks.append(Track(name: "Title", kind: .title, clips: [clip]))
        selection = clip.id; replace(next); panel = .title
    }
    func editSelected(_ change: (inout Clip) -> Void) {
        guard let selection else { return }
        guard !document.sequence.tracks.contains(where: { $0.isLocked && $0.clips.contains(where: {$0.id == selection}) }) else { error = "Unlock the track to edit."; return }
        var next = document
        for t in next.sequence.tracks.indices {
            if let c = next.sequence.tracks[t].clips.firstIndex(where: { $0.id == selection }) { change(&next.sequence.tracks[t].clips[c]) }
        }
        replace(next)
    }
    func setSpeed(_ speed: Double) {
        guard let clip=selectedClip else{return}
        apply(.retime(clipID:clip.id,speed:speed,preservesPitch:clip.preservesPitch))
    }
    func setFade(_ seconds: Double, incoming: Bool) {
        guard seconds.isFinite,seconds>=0 else {error="Enter a finite fade duration.";return}
        editSelected { clip in
            var envelope=selectedUsesOpacity ? clip.opacity:clip.volume
            let offset=envelope.evaluationOffset
            let position = incoming ? seconds : clip.duration.seconds-seconds
            let t=time(position,audio:true)+offset
            if incoming {
                envelope.points.removeAll{$0.time<=t}
                if seconds>0 {envelope.points += [.init(time:offset,value:0),.init(time:t,value:1)]}
            } else {
                envelope.points.removeAll{$0.time>=t}
                if seconds>0 {envelope.points += [.init(time:t,value:1),.init(time:clip.duration+offset,value:0)]}
            }
            if selectedUsesOpacity{clip.opacity=envelope}else{clip.volume=envelope}
        }
    }
    func suggestNormalization(){
        guard let clip=selectedClip else{return}
        audioMeasurementTask?.cancel();normalization=nil
        let snapshot=ProjectSnapshot(document:document);measuringAudio=true
        audioMeasurementTask=Task{
            defer{if !Task.isCancelled{measuringAudio=false}}
            do{let suggestion=try await media.suggestPeakNormalization(snapshot,clipID:clip.id)
                try Task.checkCancellation();guard selectedClip==clip else{return}
                normalization=suggestion;normalizationClip=clip
            }catch{if !Task.isCancelled{self.error=Self.message(error)}}
        }
    }
    func applyNormalization(){
        guard let suggestion=normalization,selectedClip==normalizationClip else{normalization=nil;return}
        editAudio{$0.gainDB=suggestion.resultingGainDB}
    }
    func measureAudio() {
        audioMeasurementTask?.cancel()
        let snapshot=ProjectSnapshot(document:document)
        measuringAudio=true
        audioMeasurementTask=Task {
            defer{if !Task.isCancelled{measuringAudio=false}}
            do {
                let measurement=try await media.measure(snapshot)
                let meters=try await media.audioMeterFrames(snapshot)
                try Task.checkCancellation()
                audioMeasurement=measurement;audioMeters=meters
            }catch{if !Task.isCancelled{self.error=Self.message(error)}}
        }
    }
    func cancelAudioMeasurement(){audioMeasurementTask?.cancel();measuringAudio=false}
    var currentAudioMeter:AudioMeterFrame? {
        guard !audioMeters.isEmpty else{return nil}
        let index=min(audioMeters.count-1,max(0,Int(playhead/0.05)))
        return audioMeters[index]
    }
    func editAudio(_ update:(inout AudioSettings)->Void){
        editSelected{clip in var settings=clip.audio ?? AudioSettings();update(&settings);clip.audio=settings}
    }
    func setClipStart(_ seconds:Double) {
        guard seconds.isFinite,(0...86400).contains(seconds) else {error="Start must be between 0 and 86,400 seconds.";return}
        guard let selection else{return}
        let audio=document.sequence.tracks.first(where:{$0.clips.contains(where:{$0.id == selection})})?.kind == .audio
        guard let clip=selectedClip else{return}
        apply(.moveMany(clipIDs:selectedIDs.isEmpty ? [selection]:selectedIDs,delta:time(seconds,audio:audio)-clip.start))
    }
    func beginGesture() { editor.beginUndoGroup() }
    func endGesture() { editor.endUndoGroup(); document = editor.document }
    func split() { if let selection { let audio=document.sequence.tracks.first(where:{$0.clips.contains(where:{$0.id == selection})})?.kind == .audio; apply(.split(clipID:selection, at:time(playhead,audio:audio))) } }
    func deleteSelection() { guard placementProposal==nil else{error="Apply or cancel the placement preview first.";return};if let selection { apply(.removeMany(clipIDs:selectedIDs.isEmpty ? [selection]:selectedIDs)); self.selection = nil } }
    func toggleSelection(_ id:UUID){
        if selectedIDs.contains(id){selectedIDs.remove(id)}else{selectedIDs.insert(id)}
        selection=selectedIDs.contains(id) ? id:selectedIDs.first
    }
    func selectAll(){if textAction("selectAll:"){return};selectedIDs=Set(document.sequence.tracks.flatMap(\.clips).map(\.id));selection=selectedIDs.first}
    private func textAction(_ name:String)->Bool {
        guard NSApp.keyWindow?.firstResponder is NSTextView else{return false}
        return NSApp.sendAction(NSSelectorFromString(name),to:nil,from:nil)
    }
    func copySelection(){
        if textAction("copy:"){return}
        let clips=document.sequence.tracks.flatMap{track in track.clips.filter{selectedIDs.contains($0.id)}.map{ClipboardClip(clip:$0,kind:track.kind,trackName:track.name)}}
        guard !clips.isEmpty,let data=try? JSONEncoder().encode(ClipClipboard(clips:clips,assets:document.assets)) else{return}
        NSPasteboard.general.clearContents();NSPasteboard.general.setData(data,forType:.init("org.lifeeditor.clips"))
    }
    func cutSelection(){if textAction("cut:"){return};copySelection();if !selectedIDs.isEmpty{apply(.removeMany(clipIDs:selectedIDs));selection=nil}}
    func pasteSelection(){
        if textAction("paste:"){return}
        guard let data=NSPasteboard.general.data(forType:.init("org.lifeeditor.clips")),let payload=try? JSONDecoder().decode(ClipClipboard.self,from:data),let first=payload.clips.map({$0.clip.start}).min() else{return}
        var next=document
        var assets:[UUID:UUID]=[:],links:[UUID:UUID]=[:],groups:[UUID:UUID]=[:]
        let used=Set(payload.clips.compactMap{$0.clip.assetID})
        for asset in payload.assets where used.contains(asset.id){
            if let existing=next.assets.first(where:{$0.id==asset.id && $0.url==asset.url}){assets[asset.id]=existing.id}
            else {var added=asset;added.id=UUID();next.assets.append(added);assets[asset.id]=added.id}
        }
        var inserted:Set<UUID>=[]
        let anchorDelta=time(playhead,audio:true)-first
        let delta=payload.clips.contains(where:{$0.kind != .audio}) ? document.sequence.settings.frameRate.quantized(anchorDelta):anchorDelta
        for item in payload.clips {
            var clip=item.clip;clip.id=UUID();clip.start=clip.start+delta
            if let id=clip.assetID{clip.assetID=assets[id]}
            if let id=clip.linkID{if links[id]==nil{links[id]=UUID()};clip.linkID=links[id]}
            if let id=clip.groupID{if groups[id]==nil{groups[id]=UUID()};clip.groupID=groups[id]}
            next.sequence.tracks.append(Track(name:item.trackName,kind:item.kind,clips:[clip]));inserted.insert(clip.id)
        }
        replace(next);selectedIDs=inserted;selection=inserted.first
    }
    func detachAudio(){
        guard let clip=selectedClip,let id=clip.assetID,document.assets.first(where:{$0.id==id})?.kind == .video,(clip.audioEnabled ?? true) else{return}
        guard !document.sequence.tracks.contains(where:{$0.isLocked && $0.clips.contains(where:{$0.id==clip.id})}) else{error="Unlock the track to edit.";return}
        var next=document;var audio=clip;audio.id=UUID();audio.name+=" Audio";audio.effects=nil;audio.visual=nil;audio.groupID=nil;audio.linkID=nil;audio.audioEnabled=true
        for t in next.sequence.tracks.indices {if let c=next.sequence.tracks[t].clips.firstIndex(where:{$0.id==clip.id}){next.sequence.tracks[t].clips[c].audioEnabled=false;next.sequence.tracks[t].clips[c].linkID=nil}}
        next.sequence.tracks.append(Track(name:audio.name,kind:.audio,clips:[audio]));replace(next)
    }
    func addMarker() {
        var next = document; next.sequence.markers.append(.init(time: time(playhead), name: "Marker \(next.sequence.markers.count+1)")); replace(next)
    }
    func toggleTrack(_ id: UUID, property: String) {
        var next = document; guard let index = next.sequence.tracks.firstIndex(where: { $0.id == id }) else { return }
        if property == "lock" { next.sequence.tracks[index].isLocked.toggle() }
        if property == "hide" { next.sequence.tracks[index].isHidden.toggle() }
        if property == "mute" { next.sequence.tracks[index].isMuted.toggle() }
        replace(next)
    }
    private func resetSession(){
        placementProposal=nil;placementBaseline=nil;autosaveError=nil;cancelColorSampling();videoOutput=nil;cameraAudioTask?.cancel();cameraAudioSignature="";cameraAudioIDs=[];checkingCameraAudio=false
        cancelAudioMeasurement();audioMeasurement=nil;audioMeters=[];playbackMeterClipped=false;invalidatePlaybackMeter();stopPlayback();switchArmed=false;auditionAngle=nil;cameraPlayers.values.forEach{$0.pause()};cameraPlayers.removeAll();angleProxyTasks.values.forEach{$0.cancel()};angleProxyTasks.removeAll();cameraPage=0;analysisTask?.cancel();syncTask?.cancel();syncGeneration+=1;syncBaseline=nil;syncReferenceID=nil;syncCandidates=[];syncPreviewing=false;previewDocument=nil;importTask?.cancel();cancelTranscription();analysisConfidence=nil;recoveryTask?.cancel()
    }
    func newProject() {
        guard confirmDiscard() else { return }
        resetSession()
        projectGeneration += 1
        player.pause(); playing = false; editor = ProjectEditor(); document = editor.document; projectURL = nil; dirty = false; selection = nil; seek(0); rebuild()
    }
    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes?"; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Discard")
        switch alert.runModal() { case .alertFirstButtonReturn: return save(); case .alertThirdButtonReturn: return true; default: return false }
    }
    func openProject(_ url: URL? = nil) {
        guard confirmDiscard() else { return }
        var destination = url
        if destination == nil {
            let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.treatsFilePackagesAsDirectories = false
            guard picker.runModal() == .OK else { return }; destination = picker.url
        }
        guard let destination else { return }
        do {
            let next = MediaBookmarks().resolve(try ProjectPackage.read(from: destination))
            resetSession()
            projectGeneration += 1
            editor = ProjectEditor(document: next); document = next; projectURL = destination; dirty = false; selection = nil; seek(0); rebuild()
            NSDocumentController.shared.noteNewRecentDocumentURL(destination)
        } catch { self.error = Self.message(error) }
    }
    var recentProjects:[URL]{NSDocumentController.shared.recentDocumentURLs}
    var canRevert:Bool{projectURL != nil && dirty}
    func revertProject(){
        guard let url=projectURL else{return}
        let alert=NSAlert();alert.messageText="Revert to the saved project?";alert.informativeText="Unsaved changes will be discarded.";alert.addButton(withTitle:"Revert");alert.addButton(withTitle:"Cancel")
        guard alert.runModal()==NSApplication.ModalResponse.alertFirstButtonReturn else{return}
        do{
            let restored=MediaBookmarks().resolve(try ProjectPackage.read(from:url))
            resetSession();projectGeneration+=1;editor=ProjectEditor(document:restored);document=restored;dirty=false;selection=nil;seek(0);rebuild()
        }catch{self.error=Self.message(error)}
    }
    func duplicateProject(){
        var copy=document;copy.id=UUID();copy.name+=" Copy"
        resetSession();projectGeneration+=1;editor=ProjectEditor(document:copy);document=copy;projectURL=nil;dirty=true;selection=nil;seek(0);rebuild();scheduleRecovery()
    }
    @discardableResult func save(as saveAs: Bool = false) -> Bool {
        var destination = saveAs ? nil : projectURL
        if destination == nil {
            let picker = NSSavePanel(); picker.nameFieldStringValue = document.name + ".lifeedit"; picker.canCreateDirectories = true
            guard picker.runModal() == .OK else { return false }; destination = picker.url
        }
        guard var destination else { return false }
        if destination.pathExtension != "lifeedit" { destination.appendPathExtension("lifeedit") }
        do { try ProjectPackage.write(document,to:destination); projectURL = destination; dirty = false;autosaveError=nil; NSDocumentController.shared.noteNewRecentDocumentURL(destination); return true }
        catch { self.error = Self.message(error); return false }
    }
    func refreshCacheUsage(){
        Task{cacheBytes=(try? await Task.detached(priority:.utility){try CacheStorage().usageBytes()}.value) ?? 0}
    }
    func clearCaches(){
        guard !playing,!exporting,!busy,!preparing else{error="Stop playback and background jobs before cleaning caches.";return}
        refreshTask?.cancel();player.replaceCurrentItem(with:nil)
        cameraPlayers.values.forEach{$0.replaceCurrentItem(with:nil)};cameraPlayers.removeAll();angleProxyTasks.values.forEach{$0.cancel()};angleProxyTasks.removeAll()
        let protected=Set(document.assets.flatMap{[$0.url]+($0.preparedURL.map{[$0]} ?? [])})
        Task{
            do{cacheBytes=try await Task.detached(priority:.utility){try CacheStorage().cleanup(budget:0,protectedURLs:protected)}.value;rebuild()}
            catch{self.error=Self.message(error)}
        }
    }
    func addManualCaption(){
        var next=document;let cue=CaptionCue(start:time(playhead),duration:.init(value:2,timescale:1),text:"Caption")
        let clip=cue.clip;next.sequence.tracks.append(Track(name:"Captions",kind:.caption,clips:[clip]));replace(next);selection=clip.id;panel = .title
    }
    func transcribeSelected(){
        guard !transcribing,let clip=selectedClip,let asset=document.assets.first(where:{$0.id==clip.assetID}) else{return}
        let projectID=document.id;transcribing=true
        transcriptionTask=Task{
            defer{transcribing=false}
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("life-transcription-"+UUID().uuidString,isDirectory:true)
            defer{try? FileManager.default.removeItem(at:folder)}
            do{
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let sourceDuration=try clip.duration.checkedScaled(by:Int64((clip.speed*1_000_000).rounded()),over:1_000_000)
                var offset=RationalTime.zero
                var mapped:[Clip]=[]
                while offset<sourceDuration {
                    try Task.checkCancellation();guard projectID==document.id else{return}
                    let chunk=min(RationalTime(value:59,timescale:1),sourceDuration-offset)
                    let requestURL=folder.appendingPathComponent(UUID().uuidString+".wav")
                    let source=Clip(assetID:asset.id,duration:chunk,sourceStart:clip.sourceStart+offset)
                    let request=ProjectDocument(sequence:Sequence(settings:document.sequence.settings,tracks:[Track(name:"Speech",kind:.audio,clips:[source])]),assets:[asset])
                    try await media.export(ProjectSnapshot(document:request),to:requestURL,options:ExportOptions(format:.wav))
                    try Task.checkCancellation()
                    let cues=try await transcription.transcribe(url:requestURL)
                    try Task.checkCancellation()
                    for cue in cues where cue.start<chunk {
                        let duration=min(cue.duration,chunk-cue.start)
                        let start=clip.start+((offset+cue.start).scaled(by:1_000_000,over:Int64((clip.speed*1_000_000).rounded())))
                        let timelineDuration=duration.scaled(by:1_000_000,over:Int64((clip.speed*1_000_000).rounded()))
                        mapped.append(CaptionCue(start:start,duration:timelineDuration,text:cue.text).clip)
                    }
                    try? FileManager.default.removeItem(at:requestURL)
                    offset+=chunk
                }
                guard projectID==document.id,document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==clip.id})==clip else{error="The source clip changed. Transcribe it again with the new timing.";return}
                var lanes:[[Clip]]=[]
                for caption in mapped.sorted(by:{$0.start<$1.start}){
                    if let lane=lanes.firstIndex(where:{($0.last?.end ?? .zero)<=caption.start}){lanes[lane].append(caption)}else{lanes.append([caption])}
                }
                var next=document;next.sequence.tracks += lanes.map{Track(name:"Captions",kind:.caption,clips:$0)};replace(next)
            }catch{if !Task.isCancelled{self.error=Self.message(error)}}
        }
    }
    func cancelTranscription(){transcriptionTask?.cancel();transcription.cancel()}
    func collectMedia(){
        let picker=NSSavePanel();picker.nameFieldStringValue=document.name+" Collected.lifeedit"
        guard picker.runModal() == .OK,let url=picker.url else{return}
        do {try ProjectPackage.collect(document,to:url)}catch{self.error=Self.message(error)}
    }
    func relinkMedia(){
        let missing=ProjectPackage.missingAssets(in:document)
        guard !missing.isEmpty else{return}
        let picker=NSOpenPanel();picker.message=missing[0].url.lastPathComponent
        guard picker.runModal() == .OK,let url=picker.url else{return}
        let id=missing[0].id;let projectID=document.id
        Task{
            do{
                let probe=try await media.probe(url)
                guard projectID==document.id,let existing=document.assets.first(where:{$0.id==id}) else{return}
                guard probe.asset.duration>=existing.duration,probe.asset.kind==existing.kind else{error="The replacement has a different type or is too short.";return}
                var next=try ProjectPackage.relinking(document,assetID:id,to:url)
                if let i=next.assets.firstIndex(where:{$0.id==id}){next.assets[i].preparedURL=probe.asset.preparedURL}
                replace(next)
            }catch{self.error=Self.message(error)}
        }
    }
    func exportMovie(){showExport=true}
    func beginExport(options:ExportOptions) {
        let picker = NSSavePanel(); picker.allowedContentTypes = [.init(filenameExtension:options.format.fileExtension) ?? .data]; picker.nameFieldStringValue = "\(document.name).\(options.format.fileExtension)"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        let snapshot = ProjectSnapshot(document: document); exportProgress=0;exporting = true
        exportTask = Task {
            defer { exporting = false }
            do { try await media.export(snapshot,to:url,options:options,progress:{[weak self] value in self?.exportProgress=value}) } catch { if !Task.isCancelled { self.error = Self.message(error) } }
        }
    }
    func cancelExport() { exportTask?.cancel() }
    func setGrid(_ update:(inout MusicalGrid)->Void) {
        gridMode = .beats
        var next=document
        var grid=next.sequence.musicalGrid ?? MusicalGrid()
        update(&grid);next.sequence.musicalGrid=grid;replace(next)
    }
    func analyzeBeats() {
        guard let analysisClip=selectedClip,let assetID=analysisClip.assetID,let asset=document.assets.first(where:{$0.id==assetID}) else{error="Select a recording.";return}
        analysisTask?.cancel();analyzing=true
        let projectID=document.id
        analysisTask=Task {
            defer {analyzing=false}
            do {
                let fingerprint=try await audioAnalyzer.fingerprint(url:asset.preparedURL ?? asset.url)
                try Task.checkCancellation()
                guard projectID==document.id else{return}
                let estimateTask=Task.detached(priority:.utility){AudioAnalyzer.beats(fingerprint)}
                let result=await withTaskCancellationHandler{await estimateTask.value}onCancel:{estimateTask.cancel()}
                try Task.checkCancellation()
                guard let result else{error="No reliable beat estimate. Set BPM manually.";return}
                analysisConfidence=result.confidence
                guard let current=document.sequence.tracks.flatMap(\.clips).first(where:{$0.id==analysisClip.id && $0.assetID==assetID}) else{return}
                let beatPeriod=60/result.bpm
                let sourceBeat=result.offset+max(0,ceil((current.sourceStart.seconds-result.offset)/beatPeriod))*beatPeriod
                let offset=current.start.seconds+(sourceBeat-current.sourceStart.seconds)/current.speed
                setGrid{$0.bpm=result.bpm*current.speed;$0.offset=time(offset,audio:true)}
            } catch {if !Task.isCancelled {self.error=Self.message(error)}}
        }
    }
    func cancelAnalysis(){analysisTask?.cancel()}
    func cancelImport(){importTask?.cancel()}
    func tapTempo(){
        let now=Date()
        if let last=tapTimes.last,now.timeIntervalSince(last)>3 {tapTimes=[]}
        tapTimes.append(now);tapTimes=Array(tapTimes.suffix(8))
        if tapTimes.count>1,let first=tapTimes.first {let bpm=60*Double(tapTimes.count-1)/now.timeIntervalSince(first);if (20...400).contains(bpm){setGrid{$0.bpm=bpm}}}
    }
    func importCaptions() {
        let picker=NSOpenPanel();picker.allowedContentTypes=[.init(filenameExtension:"srt") ?? .plainText]
        guard picker.runModal() == .OK,let url=picker.url else{return}
        do {
            let cues=try SRT.parse(String(contentsOf:url,encoding:.utf8))
            var next=document
            var lanes:[Track]=[]
            for cue in cues {
                let clip=cue.clip
                if let index=lanes.firstIndex(where:{$0.clips.allSatisfy{$0.end<=clip.start || clip.end<=$0.start}}){lanes[index].clips.append(clip)}
                else{lanes.append(Track(name:"Captions",kind:.caption,clips:[clip]))}
            }
            next.sequence.tracks+=lanes;replace(next)
        }catch{self.error=Self.message(error)}
    }
    func exportCaptions(){
        let picker=NSSavePanel();picker.nameFieldStringValue="Captions.srt"
        guard picker.runModal() == .OK,let url=picker.url else{return}
        do {
            let cues=document.sequence.tracks.filter{$0.kind == .caption}.flatMap(\.clips).compactMap{clip -> CaptionCue? in
                guard let title=clip.title else{return nil};return CaptionCue(start:clip.start,duration:clip.duration,text:title.text)
            }
            try SRT.encode(cues).write(to:url,atomically:true,encoding:.utf8)
        }catch{self.error=Self.message(error)}
    }
    func synchronizeCameras(){
        guard !recordingPass,placementProposal == nil else{error="Finish the current edit before synchronization.";return}
        guard let group=multicamGroup else{return}
        let baseline=document
        let memberIDs=Set(group.angleAssetIDs+[group.masterAudioAssetID].compactMap{$0})
        guard baseline.sequence.tracks.flatMap(\.clips).filter({$0.assetID.map(memberIDs.contains)==true}).allSatisfy({$0.speed==1}) else{error="Set camera speeds to 1× before synchronization.";return}
        syncTask?.cancel();syncGeneration+=1;let token=syncGeneration
        if syncPreviewing{rebuild()}
        syncCandidates=[];syncBaseline=nil;syncReferenceID=nil;synchronizing=true
        let method=syncMethod
        syncTask=Task {
            defer{if token==syncGeneration{synchronizing=false}}
            do{
                if method == .timecode {
                    var references:[UUID:TimecodeReference]=[:],notes:[UUID:String]=[:]
                    for id in group.angleAssetIDs+([group.masterAudioAssetID].compactMap{$0}).filter({!group.angleAssetIDs.contains($0)}) {
                        try Task.checkCancellation()
                        guard let asset=baseline.assets.first(where:{$0.id==id}) else{notes[id]="Missing media";continue}
                        do{if let reference=try await TimecodeReader.shared.read(asset.url){references[id]=reference}else{notes[id]="No timecode"}}
                        catch is CancellationError{throw CancellationError()}
                        catch{notes[id]="Invalid timecode"}
                    }
                    try Task.checkCancellation()
                    let result=try Self.timecodeSynchronization(in:baseline,references:references,notes:notes)
                    guard token==syncGeneration else{return}
                    _=installSynchronizationResults(result.candidates,referenceID:result.referenceID,baseline:baseline)
                    return
                }
                guard let masterID=group.masterAudioAssetID,let master=baseline.assets.first(where:{$0.id==masterID}) else{error="Choose master audio for waveform sync.";return}
                let reference=try await audioAnalyzer.fingerprint(url:master.preparedURL ?? master.url)
                var results:[CameraSyncCandidate]=[]
                for id in group.angleAssetIDs where id != masterID {
                    try Task.checkCancellation()
                    let fallback=try Self.currentSyncOffset(assetID:id,relativeTo:masterID,in:baseline)
                    guard let asset=baseline.assets.first(where:{$0.id==id}) else{results.append(.init(assetID:id,offset:fallback.seconds,confidence:0,note:"Missing media"));continue}
                    do {
                        let other=try await audioAnalyzer.fingerprint(url:asset.preparedURL ?? asset.url)
                        let matching=Task.detached(priority:.utility){AudioAnalyzer.synchronize(reference:reference,other:other,maxOffset:120)}
                        let match=await withTaskCancellationHandler{await matching.value}onCancel:{matching.cancel()}
                        try Task.checkCancellation()
                        var drift:Double?
                        let count=min(reference.values.count,other.values.count,Int(reference.samplesPerSecond*90))
                        if count>Int(reference.samplesPerSecond*10),reference.values.count>Int(reference.samplesPerSecond*180),let match {
                            let aStart=reference.values.count-count,bStart=other.values.count-count
                            let a=AudioFingerprint(values:Array(reference.values.suffix(count)),samplesPerSecond:reference.samplesPerSecond)
                            let b=AudioFingerprint(values:Array(other.values.suffix(count)),samplesPerSecond:other.samplesPerSecond)
                            let lateTask=Task.detached(priority:.utility){AudioAnalyzer.synchronize(reference:a,other:b,maxOffset:60)}
                            let late=await withTaskCancellationHandler{await lateTask.value}onCancel:{lateTask.cancel()}
                            if let late,late.confidence>0.6,match.confidence>0.6 {
                                let change=Double(aStart-bStart)/reference.samplesPerSecond+late.offset-match.offset
                                if abs(change)>0.04{drift=change}
                            }
                        }
                        results.append(.init(assetID:id,offset:match?.offset ?? fallback.seconds,confidence:match?.confidence ?? 0,drift:drift,note:match == nil ? "Manual":nil))
                    }catch is CancellationError{throw CancellationError()}
                    catch{results.append(.init(assetID:id,offset:fallback.seconds,confidence:0,note:"No audio"))}
                }
                try Task.checkCancellation();guard token==syncGeneration else{return}
                _=installSynchronizationResults(results,referenceID:masterID,baseline:baseline)
            }catch{if !Task.isCancelled,token==syncGeneration{self.error=Self.message(error)}}
        }
    }
    @discardableResult func installSynchronizationResults(_ candidates:[CameraSyncCandidate],referenceID:UUID,baseline:ProjectDocument)->Bool {
        guard document==baseline else{error="Project changed. Synchronize again.";return false}
        syncBaseline=baseline;syncReferenceID=referenceID;syncCandidates=candidates;return true
    }
    static func currentSyncOffset(assetID:UUID,relativeTo referenceID:UUID,in document:ProjectDocument)throws->RationalTime {
        let clips=document.sequence.tracks.flatMap(\.clips)
        guard let reference=clips.filter({$0.assetID==referenceID}).min(by:{$0.start<$1.start}),let clip=clips.filter({$0.assetID==assetID}).min(by:{$0.start<$1.start}) else{return .zero}
        return try clip.start.checkedSubtracting(clip.sourceStart).checkedSubtracting(reference.start.checkedSubtracting(reference.sourceStart))
    }
    static func timecodeSynchronization(in document:ProjectDocument,references:[UUID:TimecodeReference],notes:[UUID:String]=[:])throws->(referenceID:UUID,candidates:[CameraSyncCandidate]) {
        guard let group=document.sequence.multicamGroups.last else{throw DocumentError.clipNotFound}
        let master=group.masterAudioAssetID.flatMap{references[$0] == nil ? nil:$0}
        guard let referenceID=master ?? group.angleAssetIDs.first(where:{references[$0] != nil}) ?? group.angleAssetIDs.first else{throw DocumentError.clipNotFound}
        let ids=group.angleAssetIDs+([group.masterAudioAssetID].compactMap{$0}).filter{!group.angleAssetIDs.contains($0)}
        let candidates=try ids.filter{$0 != referenceID}.map {id -> CameraSyncCandidate in
            let fallback=try currentSyncOffset(assetID:id,relativeTo:referenceID,in:document)
            guard let reference=references[referenceID],let other=references[id] else{return .init(assetID:id,offset:fallback.seconds,confidence:0,note:notes[id] ?? "No timecode",exactOffset:fallback)}
            do{let match=try other.alignment(relativeTo:reference);return .init(assetID:id,offset:match.offset.seconds,confidence:1,note:match.requiresDayReview ? "Day wrap":nil,exactOffset:match.offset)}
            catch{return .init(assetID:id,offset:fallback.seconds,confidence:0,note:"Format mismatch",exactOffset:fallback)}
        }
        return (referenceID,candidates)
    }
    func cancelSynchronization(){syncTask?.cancel();syncGeneration+=1;synchronizing=false;syncCandidates=[];syncBaseline=nil;syncReferenceID=nil;if syncPreviewing{rebuild()}}
    func synchronizedCandidate()throws->ProjectDocument {
        guard let baseline=syncBaseline,document==baseline else{throw SynchronizationPreviewError.stale}
        guard let referenceID=syncReferenceID,let master=baseline.sequence.tracks.flatMap(\.clips).filter({$0.assetID==referenceID}).min(by:{$0.start<$1.start}) else{throw DocumentError.clipNotFound}
        var next=document
        for result in syncCandidates {
            guard result.offset.isFinite,abs(result.offset)<=86400 else{throw DocumentError.invalidTiming}
            let offset=result.exactOffset ?? RationalTime(value:Int64((result.offset*48000).rounded()),timescale:48000)
            let anchor=try master.start.checkedSubtracting(master.sourceStart).checkedAdding(offset)
            for t in next.sequence.tracks.indices {
                for c in next.sequence.tracks[t].clips.indices where next.sequence.tracks[t].clips[c].assetID==result.assetID {
                    guard !next.sequence.tracks[t].isLocked else{throw DocumentError.lockedTrack}
                    var clip=next.sequence.tracks[t].clips[c]
                    let start=try anchor.checkedAdding(clip.sourceStart)
                    if start < .zero {let trim=try RationalTime.zero.checkedSubtracting(start);guard clip.duration>trim else{throw DocumentError.sourceBoundary};clip.sourceStart=try clip.sourceStart.checkedAdding(trim);clip.duration=try clip.duration.checkedSubtracting(trim);clip.volume.evaluationOffset=try clip.volume.evaluationOffset.checkedAdding(trim);clip.opacity.evaluationOffset=try clip.opacity.evaluationOffset.checkedAdding(trim);if let animation=clip.title?.animation{clip.title?.animation=try animation.windowed(by:trim)}}
                    clip.start=try next.sequence.tracks[t].kind == .audio ? max(.zero,start):next.sequence.settings.frameRate.checkedQuantized(max(.zero,start));next.sequence.tracks[t].clips[c]=clip
                }
            }
        }
        try next.validate();return next
    }
    func previewSynchronization(){do{stopPlayback();let candidate=try synchronizedCandidate();rebuild(preview:candidate)}catch{self.error=Self.message(error)}}
    func applySynchronization(){do{stopPlayback();let candidate=try synchronizedCandidate();replace(candidate);if document==candidate{syncCandidates=[];syncBaseline=nil;syncReferenceID=nil}}catch{self.error=Self.message(error)}}
    var multicamGroup:MulticamGroup? {document.sequence.multicamGroups.last}
    var visibleAngles:[MediaAsset] {
        guard let group=multicamGroup else{return []}
        return group.angleAssetIDs.compactMap{id in document.assets.first{$0.id==id}}.dropFirst(cameraPage*4).prefix(4).map{$0}
    }
    func createMulticam(){
        let assets=document.assets.filter{$0.kind == .video}
        guard assets.count>=2 else{error="Import at least two camera recordings.";return}
        var next=document
        next.sequence.multicamGroups.append(.init(angleAssetIDs:assets.map(\.id),masterAudioAssetID:document.assets.first(where:{$0.kind == .audio})?.id ?? assets.first?.id,cuts:[.init(time:.zero,angleID:assets[0].id)],audioAssetIDs:document.assets.filter{$0.kind == .audio}.map(\.id)))
        replace(next);panel = .multicam
    }
    func angleAvailable(_ asset:MediaAsset)->Bool {
        if switchMode != .video && (checkingCameraAudio || !cameraAudioIDs.contains(asset.id)){return false}
        return playbackDocument.sequence.tracks.flatMap(\.clips).contains{$0.assetID==asset.id && $0.start.seconds<=playhead && playhead<$0.end.seconds}
    }
    func anglePlayer(_ asset:MediaAsset)->AVPlayer {
        if let player=cameraPlayers[asset.id]{return player}
        let player=AVPlayer(url:asset.preparedURL ?? asset.url);player.automaticallyWaitsToMinimizeStalling=false;player.isMuted=true;cameraPlayers[asset.id]=player
        if angleProxyTasks[asset.id]==nil {
            let projectID=document.id
            angleProxyTasks[asset.id]=Task{[weak self,weak player] in
                guard let self else{return}
                do{
                    let url=try await media.proxy(asset:asset,maxDimension:1280)
                    try Task.checkCancellation()
                    guard projectID==document.id,let player else{return}
                    let item=AVPlayerItem(url:url);media.keepCacheFiles([url],on:item);player.replaceCurrentItem(with:item)
                    synchronizeCameraPlayers(playhead,playing:playing)
                }catch{if !Task.isCancelled{self.error=Self.message(error)}}
            }
        }
        return player
    }
    private func synchronizeCameraPlayers(_ position:Double,playing:Bool){
        guard let group=multicamGroup else{return}
        let clock=CMClockGetHostTimeClock()
        let host=CMTimeAdd(CMClockGetTime(clock),CMTime(seconds:0.1,preferredTimescale:600))
        if playing && player.status == .readyToPlay {player.pause();player.setRate(1,time:CMTime(seconds:position,preferredTimescale:48000),atHostTime:host)}
        let visibleIDs=Set(visibleAngles.prefix(4).map(\.id))
        for (id,preview) in cameraPlayers where !visibleIDs.contains(id) {preview.pause()}
        for assetID in group.angleAssetIDs where visibleIDs.contains(assetID) {
            guard let asset=document.assets.first(where:{$0.id==assetID}),let clip=playbackDocument.sequence.tracks.flatMap(\.clips).first(where:{$0.assetID==assetID && $0.start.seconds<=position && position<$0.end.seconds}) else{cameraPlayers[assetID]?.pause();continue}
            let source=clip.sourceStart.seconds+(position-clip.start.seconds)*clip.speed
            let preview=anglePlayer(asset)
            let t=CMTime(seconds:max(0,source),preferredTimescale:48000)
            preview.pause();preview.seek(to:t,toleranceBefore:.zero,toleranceAfter:.zero)
            if playing && source>=0 && source<asset.duration.seconds {if preview.status == .readyToPlay{preview.setRate(Float(clip.speed),time:t,atHostTime:host)}else{preview.playImmediately(atRate:Float(clip.speed))}}
        }
    }
    private func clearAngleAudition(){
        auditionAngle=nil
        if let item=player.currentItem{media.audition(angleID:nil,on:item);media.auditionAudio(assetID:nil,on:item)}
    }
    private func replacingPass(in original:MulticamGroup,from start:RationalTime,to end:RationalTime)throws->MulticamGroup{
        var result=original
        if switchMode != .audio{result=try MulticamEditing.replacingCuts(in:result,from:start,to:end,with:recordedRangeCuts)}
        if switchMode != .video{result=try MulticamSwitching.replacingAudioCuts(in:result,from:start,to:end,with:recordedRangeAudioCuts)}
        return result
    }
    func refreshCameraAudio(){
        guard let group=multicamGroup else{return}
        let assets=document.assets.filter{$0.kind != .image}
        let signature=group.id.uuidString+assets.map{$0.id.uuidString+($0.preparedURL ?? $0.url).absoluteString}.joined(separator:"|")
        guard signature != cameraAudioSignature else{return}
        cameraAudioTask?.cancel();cameraAudioSignature=signature;checkingCameraAudio=true
        let project=document.id
        cameraAudioTask=Task{
            defer{if signature==cameraAudioSignature{checkingCameraAudio=false}}
            var found:Set<UUID>=[]
            for asset in assets{
                do{try Task.checkCancellation();if try await media.audioAvailable(asset:asset){found.insert(asset.id)}}catch{if Task.isCancelled{return}}
            }
            guard !Task.isCancelled,document.id==project,signature==cameraAudioSignature else{return}
            cameraAudioIDs=found
        }
    }
    func chooseAngle(_ assetID:UUID){
        guard let asset=document.assets.first(where:{$0.id==assetID}),angleAvailable(asset) else{return}
        auditionAngle=assetID
        if let item=player.currentItem{
            if switchMode != .audio{media.audition(angleID:assetID,on:item)}
            if switchMode != .video{media.auditionAudio(assetID:assetID,on:item)}
        }
        guard switchArmed,let group=multicamGroup else{return}
        do{
            let position=try document.sequence.settings.frameRate.checkedQuantized(playheadTime)
            var updated=try MulticamSwitching.applying(angleID:assetID,at:position,mode:switchMode,to:group,frameRate:document.sequence.settings.frameRate,availableAudioAssetIDs:cameraAudioIDs)
            guard updated != group else{return}
            if let range=activeSwitchRange{
                guard position>=range.start,position<range.end,let original=rangeOriginalGroup else{return}
                if switchMode != .audio{recordedRangeCuts.removeAll{$0.time==position};recordedRangeCuts.append(.init(time:position,angleID:assetID))}
                if switchMode != .video{recordedRangeAudioCuts.removeAll{$0.time==position};recordedRangeAudioCuts.append(.init(time:position,angleID:assetID))}
                updated=try replacingPass(in:original,from:range.start,to:range.end)
            }
            var next=document;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1]=updated
            try editor.perform(.replace(next));document=editor.document;dirty=true;scheduleRecovery()
            if !playing{rebuild()}
        }catch{self.error=Self.message(error)}
    }
    func findRecovery(){recoverable=RecoveryStore().recoverableProjects()}
    func restoreRecovery(_ snapshot:ProjectDocument){
        guard confirmDiscard() else{return}
        resetSession();projectGeneration+=1
        editor=ProjectEditor(document:MediaBookmarks().resolve(snapshot));document=editor.document;dirty=true;projectURL=nil;selection=nil;seek(0);rebuild()
    }
    private var recoveryTask:Task<Void,Never>?
    private func scheduleRecovery(){
        recoveryTask?.cancel()
        let snapshot=document,destination=projectURL
        recoveryTask=Task{
            do{
                try await Task.sleep(for:.seconds(2));try Task.checkCancellation()
                // Main-actor serialization keeps autosave ordered with explicit Save.
                if let destination,destination==projectURL,snapshot==document{
                    try ProjectPackage.write(snapshot,to:destination);dirty=false;autosaveError=nil
                }
                try await RecoveryWriter.shared.checkpoint(snapshot)
            }catch{if !Task.isCancelled{autosaveError=Self.message(error);self.error="Autosave or recovery failed: "+Self.message(error)}}
        }
    }
    static func message(_ error: Error) -> String {
        if let error = error as? DocumentError {
            switch error { case .overlap: return "Clips overlap. Move to a clear space or another track."
            case .sourceBoundary: return "The edit exceeds the original recording."
            case .lockedTrack: return "Unlock the track to edit."
            case .invalidSplit: return "Place the playhead inside the selected clip."
            case .unsupportedVersion(let version): return "Project format \(version) is unsupported. The file was not changed."
            default: return "The edit could not be applied (\(error))." }
        }
        return error.localizedDescription
    }
}

private struct ClipboardClip:Codable{var clip:Clip;var kind:TrackKind;var trackName:String}
private struct ClipClipboard:Codable{var clips:[ClipboardClip];var assets:[MediaAsset]}

struct CameraSyncCandidate:Identifiable {
    var id:UUID{assetID}
    var assetID:UUID
    var offset:Double{didSet{exactOffset=nil}}
    var confidence:Double
    var drift:Double? = nil
    var note:String? = nil
    var exactOffset:RationalTime? = nil
}
enum CameraSyncMethod:String,CaseIterable{case waveform,timecode}
enum SynchronizationPreviewError:LocalizedError{case stale;var errorDescription:String?{"Project changed. Synchronize again."}}
