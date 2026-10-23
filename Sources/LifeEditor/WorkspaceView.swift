import SwiftUI
import AVKit
import LifeCore

private let surface = Color(red:0.10,green:0.11,blue:0.12)
private let accent = Color(red:0.54,green:0.72,blue:0.69)

struct WorkspaceView: View {
    @ObservedObject var store: EditorStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gearAngle: Double = 0
    @AppStorage("timelineFraction") private var timelineFraction=0.32
    @AppStorage("inspectorWidth") private var inspectorWidth=260.0
    @State private var resizingTimeline:Double?
    @State private var resizingPanel:Double?
    @State private var timelineCollapsed=false
    @State private var shapePicker=false
    @State private var audioPage=0
    var body: some View {
        VStack(spacing:0) {
            toolbar
            Divider()
            if store.focused { viewer } else {
                GeometryReader { geometry in
                    VStack(spacing:0){
                        HStack(spacing:0){
                            viewer.frame(minWidth:560)
                            if store.panel != nil {
                                Rectangle().fill(.white.opacity(0.08)).frame(width:5).contentShape(Rectangle()).gesture(DragGesture().onChanged{value in
                                    if resizingPanel==nil{resizingPanel=inspectorWidth}
                                    inspectorWidth=max(220,min(380,(resizingPanel ?? 260)-value.translation.width))
                                }.onEnded{_ in resizingPanel=nil}).help("Resize panel").accessibilityLabel("Resize panel")
                                inspector.frame(width:inspectorWidth)
                            }
                        }.frame(height:timelineCollapsed ? geometry.size.height : geometry.size.height*(1-timelineFraction)-2)
                        if !timelineCollapsed {
                            Rectangle().fill(.white.opacity(0.1)).frame(height:5).contentShape(Rectangle()).gesture(DragGesture().onChanged{value in
                                if resizingTimeline==nil{resizingTimeline=timelineFraction}
                                timelineFraction=max(0.2,min(0.55,(resizingTimeline ?? 0.32)-value.translation.height/geometry.size.height))
                            }.onEnded{_ in resizingTimeline=nil}).help("Resize timeline").accessibilityLabel("Resize timeline").accessibilityAdjustableAction{direction in timelineFraction=max(0.2,min(0.55,timelineFraction+(direction == .increment ? 0.05:-0.05)))}
                            timeline.frame(maxHeight:.infinity)
                        }
                    }
                }
            }
        }
        .background(surface)
        .tint(accent)
        .sheet(isPresented:$store.showExport){ExportSheet(store:store)}
        .alert("Life Editor",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onAppear { store.safeAreas = UserDefaults.standard.bool(forKey:"showSafeAreaDefault") }
        .onExitCommand{if store.placementProposal != nil{store.cancelPlacement()}else{store.cancelColorSampling()}}
    }
    private var toolbar: some View {
        HStack(spacing:10) {
            icon("square.and.arrow.down", "Import · ⌘I", action:store.importMedia).disabled(store.placementProposal != nil)
            Divider().frame(height:18)
            icon("rectangle.stack", "Media", selected:store.panel == .media) { toggle(.media) }
            icon("textformat", "Title", action:store.addTitle)
            icon("shapes", "Shapes"){shapePicker.toggle()}.popover(isPresented:$shapePicker){HStack(spacing:12){
                ForEach(ShapeKind.allCases,id:\.self){kind in Button{store.addShape(kind);shapePicker=false}label:{Image(systemName:shapeIcon(kind)).frame(width:32,height:32)}.buttonStyle(.plain).help(kind.rawValue).accessibilityLabel(kind.rawValue)}
            }.padding(14)}
            icon("pencil.tip", "Drawing", selected:store.panel == .drawing){toggle(.drawing);store.drawingMode=store.panel == .drawing ? 1:0}
            icon("slider.horizontal.3", "Clip", selected:store.panel == .clip) { toggle(.clip) }
            icon("camera.filters", "Effects", selected:store.panel == .effects){toggle(.effects)}
            icon("bookmark", "Markers",selected:store.panel == .markers){toggle(.markers)}
            icon("waveform", "Audio", selected:store.panel == .audio) {toggle(.audio)}
            icon("square.grid.2x2", "Multicam", selected:store.panel == .multicam) {toggle(.multicam)}
            Spacer()
            Text(store.document.name + (store.dirty ? " •" : "")).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let failure=store.autosaveError{icon("externaldrive.badge.exclamationmark","Autosave failed"){store.error=failure}}
            if store.busy {ProgressView(value:store.importProgress).frame(width:50).accessibilityLabel("Preparing media");icon("xmark","Cancel import"){store.cancelImport()}}
            if store.exporting {
                ProgressView().controlSize(.small).accessibilityLabel("Exporting")
                icon("xmark", "Cancel Export", action:store.cancelExport)
            } else { icon("square.and.arrow.up", "Export", action:store.exportMovie).disabled(store.document.sequence.duration == .zero) }
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration:0.3)) { gearAngle += 90 }
                openSettings()
            } label: { Image(systemName:"gearshape").rotationEffect(.degrees(gearAngle)).frame(width:30,height:30) }
            .buttonStyle(.plain).help("Settings · ⌘,").accessibilityLabel("Settings")
        }.padding(.horizontal,12).frame(height:44)
    }
    private var viewer: some View {
        VStack(spacing:0) {
            ZStack {
                Color.black
                PlayerSurface(player:store.player)
                ViewerOverlay(store:store)
                if store.panel == .multicam && store.multicamGroup != nil {
                    HStack {Spacer();angleGrid.frame(width:200).padding(8)}
                }
                if store.document.sequence.tracks.isEmpty {
                    Button(action:store.importMedia) { Image(systemName:"plus.rectangle.on.rectangle").font(.system(size:30,weight:.ultraLight)).frame(width:80,height:80) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Import · ⌘I").accessibilityLabel("Import media")
                }
                if store.safeAreas {
                    Rectangle().stroke(.white.opacity(0.35),style:StrokeStyle(lineWidth:1,dash:[5,5])).padding(32).allowsHitTesting(false)
                }
            }.padding(12)
            HStack(spacing:14) {
                if store.syncPreviewing {Text("Sync preview").font(.caption2).foregroundStyle(.secondary)}
                if store.previewUsesProxies {Text("Proxy").font(.caption2).foregroundStyle(.secondary).help("Reduced-resolution preview; export uses full-quality media")}
                Text(timecode(store.playhead)).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary).frame(width:110,alignment:.leading)
                Spacer()
                icon("backward.end", "Start") { store.seek(0) }
                icon("backward.frame", "Previous frame · ←") { store.step(-1) }
                icon(store.playing ? "pause.fill" : "play.fill", "Play / Pause · Space", action:store.togglePlayback)
                icon("forward.frame", "Next frame · →") { store.step(1) }
                Spacer()
                icon("viewfinder", "Safe areas", selected:store.safeAreas) { store.safeAreas.toggle() }
                icon("arrow.up.left.and.arrow.down.right", "Viewer focus · ⇧⌘F", selected:store.focused) { store.focused.toggle() }
            }.padding(.horizontal,18).frame(height:42)
        }
    }
    private var timeline: some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                icon("scissors", "Split · ⌘B", action:store.split).disabled(store.selection == nil)
                icon("trash", "Delete · ⌫", action:store.deleteSelection).disabled(store.selection == nil)
                icon("rectangle.badge.plus","Insert copies · ⇧⌘I"){store.previewPlacement(.insertCopies(clipIDs:store.selectedIDs,at:store.playheadTime),title:"Insert")}.disabled(store.selectedIDs.isEmpty || store.placementProposal != nil)
                icon("rectangle.fill.on.rectangle.fill","Overwrite copies · ⇧⌘O"){store.previewPlacement(.overwriteCopies(clipIDs:store.selectedIDs,at:store.playheadTime),title:"Overwrite")}.disabled(store.selectedIDs.isEmpty || store.placementProposal != nil)
                icon("bookmark", "Marker · M", action:store.addMarker)
                Divider().frame(height:18)
                Button {store.snapping.toggle()} label: {MagnetIcon().stroke(lineWidth:1.8).frame(width:15,height:17).padding(8).background(store.snapping ? accent.opacity(0.2):.clear,in:RoundedRectangle(cornerRadius:5))}.buttonStyle(.plain).help("Snapping · N").accessibilityLabel("Snapping").accessibilityValue(store.snapping ? "On":"Off")
                Menu {
                    Toggle("Show Grid",isOn:$store.gridVisible)
                    Button("Time"){store.gridMode = .time}
                    Button("Frames"){store.gridMode = .frames}
                    Button("Beats"){store.setGrid{_ in}}
                } label: {Image(systemName:"grid").frame(width:30,height:30)}.menuStyle(.borderlessButton).fixedSize().help("Grid").accessibilityLabel("Grid")
                PlacementPreviewControls(store:store)
                Spacer()
                icon("minus.magnifyingglass", "Zoom out") { store.pixelsPerSecond = max(4,store.pixelsPerSecond/1.4) }
                Slider(value:Binding(get:{log2(store.pixelsPerSecond)},set:{store.pixelsPerSecond=pow(2,$0)}),in:2...17).frame(width:100).accessibilityLabel("Timeline zoom")
                icon("plus.magnifyingglass", "Zoom in") { store.pixelsPerSecond = min(131072,store.pixelsPerSecond*1.4) }
                icon("arrow.left.and.right.righttriangle.left.righttriangle.right", "Fit project") { store.pixelsPerSecond = max(4,min(100,900/max(1,store.document.sequence.duration.seconds))) }
            }.padding(.horizontal,10).frame(height:36)
            Divider()
            TimelineSurface(store:store)
        }.background(Color(red:0.075,green:0.08,blue:0.09))
    }
    @ViewBuilder private var inspector: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text(store.panel?.rawValue.capitalized ?? "Clip").font(.headline); Spacer(); icon("xmark", "Close panel") {store.panel=nil} }
            if store.panel == .media {
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        ForEach(store.document.assets) { asset in
                            HStack { Image(systemName:asset.kind == .audio ? "waveform" : "film"); Text(asset.url.lastPathComponent).lineLimit(2).font(.caption); Spacer() }
                        }
                    }
                }
                Button("Import…", action:store.importMedia)
                HStack{Button("SRT"){store.importCaptions()};Button("Caption"){store.addManualCaption()}}
                if store.transcribing {Button("Cancel Transcription"){store.cancelTranscription()}}
                else {Button("Transcribe"){store.transcribeSelected()}.disabled(store.selectedClip?.assetID==nil || !LocalTranscription.supports(locale:.current)).help(LocalTranscription.supports(locale:.current) ? "On-device transcription":"On-device transcription unavailable")}

            } else if store.panel == .effects {EffectBrowser(store:store)}
            else if store.panel == .audio {
                Picker("Audio tools",selection:$audioPage){Text("Mix").tag(0);Text("Beats").tag(1)}.pickerStyle(.segmented)
                ScrollView{if audioPage==0{AudioControls(store:store)}else{VStack(spacing:16){audioInspector;MusicalGridControls(store:store)}}}
            }
            else if store.panel == .multicam {ScrollView{multicamInspector;MulticamCutControls(store:store)}}
            else if store.panel == .drawing {DrawingControls(store:store)}
            else if store.panel == .markers {MarkerControls(store:store)}
            else if let clip = store.selectedClip {
                ScrollView {VStack(alignment:.leading,spacing:14){
                TextField("Name",text:Binding(get:{store.selectedClip?.name ?? ""},set:{text in store.editSelected{$0.name=text}})).textFieldStyle(.roundedBorder)
                if clip.title != nil {
                    TextField("Text",text:Binding(get:{store.selectedClip?.title?.text ?? ""},set:{text in store.editSelected{$0.title?.text=text}}),axis:.vertical).lineLimit(2...6)
                    TitleControls(store:store)
                    HStack { Text("Size"); Slider(value:Binding(get:{store.selectedClip?.title?.fontSize ?? 64},set:{v in store.editSelected{$0.title?.fontSize=v}}),in:16...160,onEditingChanged:gesture) }
                } else if clip.assetID != nil,clip.freezeFrame == nil {
                    HStack { Text("Speed"); Spacer(); Text(String(format:"%.2f×",clip.speed)).monospacedDigit() }
                    Slider(value:Binding(get:{store.selectedClip?.speed ?? 1},set:{ v in store.setSpeed(v) }),in:0.25...4,step:0.05,onEditingChanged:gesture)
                    Toggle("Preserve pitch",isOn:Binding(get:{store.selectedClip?.preservesPitch ?? true},set:{v in store.editSelected{$0.preservesPitch=v}}))
                }
                AutomationControls(store:store)
                HStack {
                    Text("Start").foregroundStyle(.secondary)
                    TextField("Seconds",value:Binding(get:{store.selectedClip?.start.seconds ?? 0},set:{v in store.setClipStart(v)}),format:.number.precision(.fractionLength(5))).textFieldStyle(.roundedBorder).accessibilityLabel("Clip start in seconds")
                }
                if !store.selectedIsAdjustment{VisualControls(store:store)}
                TrackControls(store:store)
                if store.selectedIsAdjustment{
                    HStack{Text("Duration");TextField("Seconds",value:Binding(get:{store.selectedClip?.duration.seconds ?? 0},set:{store.setAdjustmentDuration($0)}),format:.number.precision(.fractionLength(3))).textFieldStyle(.roundedBorder).accessibilityLabel("Adjustment layer duration seconds")}
                }else{EditControls(store:store)}
                Text(String(format:"%.3f s",clip.duration.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }}
            }
            Spacer()
        }.font(.system(size:12)).padding(16).background(surface)
    }
    private var audioInspector:some View {
        VStack(alignment:.leading,spacing:14){
            HStack{
                if store.analyzing {ProgressView().controlSize(.small);Button("Cancel"){store.cancelAnalysis()}}
                else {Button("Detect Beats"){store.analyzeBeats()}.disabled(store.selectedClip?.assetID == nil)}
                Spacer();Button("Tap"){store.tapTempo()}.help("Tap tempo")
            }
            if let confidence=store.analysisConfidence {Text(String(format:"%.0f%%",confidence*100)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)}
            HStack{Text("BPM");TextField("BPM",value:Binding(get:{store.document.sequence.musicalGrid?.bpm ?? 120},set:{v in store.setGrid{$0.bpm=v}}),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder)}
            HStack{
                Button("½"){store.setGrid{$0.bpm=max(20,$0.bpm/2)}}.help("Half tempo")
                Button("2×"){store.setGrid{$0.bpm=min(400,$0.bpm*2)}}.help("Double tempo")
                Button("Downbeat"){store.setGrid{grid in if let moved=try? grid.moved(by:store.time(store.playhead,audio:true)-grid.offset){grid=moved}}}.help("Set first downbeat at playhead")
            }
            HStack{Text("Beats / bar");Stepper(value:Binding(get:{store.document.sequence.musicalGrid?.beatsPerBar ?? 4},set:{v in store.setGrid{$0.beatsPerBar=v}}),in:1...16){Text("\(store.document.sequence.musicalGrid?.beatsPerBar ?? 4)")}}
            Picker("Division",selection:Binding(get:{store.document.sequence.musicalGrid?.subdivision ?? 1},set:{v in store.setGrid{$0.subdivision=v}})){Text("1").tag(1);Text("½").tag(2);Text("⅓").tag(3);Text("¼").tag(4)}.pickerStyle(.segmented)
        }
    }
    private var multicamInspector:some View {
        VStack(alignment:.leading,spacing:14){
            if let group=store.multicamGroup {
                Picker("Switch",selection:$store.switchMode){Text("Video").tag(MulticamSwitchMode.video);Text("Audio").tag(MulticamSwitchMode.audio);Text("Both").tag(MulticamSwitchMode.both)}.pickerStyle(.segmented).disabled(store.playing || store.checkingCameraAudio)
                Toggle("Replace range",isOn:$store.replaceSwitchRange).disabled(store.playing)
                if store.replaceSwitchRange{
                    HStack{
                        TextField("Start",value:$store.switchRangeStart,format:.number.precision(.fractionLength(3))).accessibilityLabel("Switch range start seconds")
                        Text("–")
                        TextField("End",value:$store.switchRangeEnd,format:.number.precision(.fractionLength(3))).accessibilityLabel("Switch range end seconds")
                    }.textFieldStyle(.roundedBorder).disabled(store.playing)
                }
                Toggle(isOn:$store.switchArmed){Label("Record switches",systemImage:store.switchArmed ? "record.circle.fill":"record.circle")}.toggleStyle(.button).help("Arm camera switching · 1–9")
                CameraSynchronizationControls(store:store)
                Picker("Master",selection:Binding(get:{group.masterAudioAssetID},set:{id in var next=store.document;next.sequence.multicamGroups[next.sequence.multicamGroups.count-1].masterAudioAssetID=id;if let id{var associated=next.sequence.multicamGroups[next.sequence.multicamGroups.count-1].audioAssetIDs ?? [];if !associated.contains(id){associated.append(id)};next.sequence.multicamGroups[next.sequence.multicamGroups.count-1].audioAssetIDs=associated};store.replace(next)})){
                    ForEach(store.document.assets.filter{store.cameraAudioIDs.contains($0.id)}){asset in Text(asset.url.lastPathComponent).tag(Optional(asset.id))}
                }
                HStack{Button {store.cameraPage=max(0,store.cameraPage-1)}label:{Image(systemName:"chevron.left")}.disabled(store.cameraPage==0).help("Previous angles").accessibilityLabel("Previous angles")
                    Spacer();Text("\(store.cameraPage+1)").monospacedDigit();Spacer()
                    Button{store.cameraPage+=1}label:{Image(systemName:"chevron.right")}.disabled((store.cameraPage+1)*4>=group.angleAssetIDs.count).help("Next angles").accessibilityLabel("Next angles")}
            }else{Button("Create Multicam"){store.createMulticam()}}
        }
    }
    private var angleGrid:some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:5){
                ForEach(Array(store.visibleAngles.prefix(4).enumerated()),id:\.element.id){index,asset in
                    Button{store.chooseAngle(asset.id)}label:{
                        ZStack(alignment:.bottomLeading){PlayerSurface(player:store.anglePlayer(asset)).frame(height:70).allowsHitTesting(false);Text("\(index+1)").font(.caption.bold()).padding(4).background(.black.opacity(0.8))}
                            .overlay{if store.auditionAngle==asset.id{Rectangle().stroke(accent,lineWidth:2)}}
                    }.buttonStyle(.plain).disabled(!store.angleAvailable(asset)).opacity(store.angleAvailable(asset) ? 1:0.3).help("Camera \(index+1)").accessibilityLabel("Camera \(index+1): \(asset.url.lastPathComponent)")
                }
            }
        }.frame(maxHeight:310).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:6))
    }
    private func shapeIcon(_ kind:ShapeKind)->String{
        switch kind{case .rectangle:"rectangle";case .roundedRectangle:"capsule";case .ellipse:"circle";case .line:"line.diagonal";case .arrow:"arrow.up.right"}
    }
    private func gesture(_ active:Bool) { if active {store.beginGesture()} else {store.endGesture()} }
    private func fadeDuration(_ clip:Clip,incoming:Bool)->Double {
        let envelope=store.selectedUsesOpacity ? clip.opacity:clip.volume
        let offset=envelope.evaluationOffset
        let points=envelope.points.sorted{$0.time<$1.time}
        if incoming {
            guard envelope.value(at:.zero)==0,let next=points.first(where:{$0.time>offset && $0.value>0}) else{return 0}
            return min(clip.duration.seconds,(next.time-offset).seconds)
        }
        guard envelope.value(at:clip.duration)==0,let previous=points.last(where:{$0.time<offset+clip.duration && $0.value>0}) else{return 0}
        return max(0,(clip.duration+offset-previous.time).seconds)
    }
    private func toggle(_ panel: EditorStore.InspectorPanel) { store.panel = store.panel == panel ? nil : panel;if store.panel != .drawing{store.drawingMode=0} }
    private func timecode(_ seconds:Double) -> String { let s = Int(max(0,seconds)); let fps=Double(store.document.sequence.settings.frameRate.numerator)/Double(store.document.sequence.settings.frameRate.denominator); return String(format:"%02d:%02d:%02d:%02d",s/3600,(s/60)%60,s%60,Int((seconds-Double(s))*fps)) }
    private func icon(_ symbol:String,_ label:String,selected:Bool=false,action:@escaping ()->Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.system(size:14,weight:.medium)).frame(width:30,height:30).background(selected ? accent.opacity(0.22) : .clear,in:RoundedRectangle(cornerRadius:5)).overlay { if selected { RoundedRectangle(cornerRadius:5).stroke(accent.opacity(0.7),lineWidth:1) } } }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context:Context) -> AVPlayerView { let view=AVPlayerView(); view.controlsStyle = .none; view.videoGravity = .resizeAspect; view.player=player; return view }
    func updateNSView(_ view:AVPlayerView,context:Context) { view.player=player }
}

private struct MagnetIcon:Shape {
    func path(in r:CGRect)->Path {
        Path {p in
            p.move(to:CGPoint(x:r.minX,y:r.minY));p.addLine(to:CGPoint(x:r.minX,y:r.midY));p.addCurve(to:CGPoint(x:r.maxX,y:r.midY),control1:CGPoint(x:r.minX,y:r.maxY+3),control2:CGPoint(x:r.maxX,y:r.maxY+3));p.addLine(to:CGPoint(x:r.maxX,y:r.minY))
            p.move(to:CGPoint(x:r.minX-2,y:r.minY+4));p.addLine(to:CGPoint(x:r.minX+2,y:r.minY+4));p.move(to:CGPoint(x:r.maxX-2,y:r.minY+4));p.addLine(to:CGPoint(x:r.maxX+2,y:r.minY+4))
        }
    }
}
