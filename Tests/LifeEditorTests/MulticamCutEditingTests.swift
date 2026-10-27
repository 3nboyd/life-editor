import AppKit
import Testing
import LifeCore
@testable import LifeEditor

@MainActor private func cutStore()->EditorStore {
    let d=RationalTime(value:6,timescale:1)
    let assets=(0..<3).map{MediaAsset(url:URL(fileURLWithPath:"/tmp/cut-test-\($0).mov"),kind:$0==2 ? .audio:.video,duration:d)}
    let group=MulticamGroup(angleAssetIDs:[assets[0].id,assets[1].id],masterAudioAssetID:assets[2].id,cuts:[.init(time:.zero,angleID:assets[0].id),.init(time:.init(value:2,timescale:1),angleID:assets[1].id),.init(time:.init(value:4,timescale:1),angleID:assets[0].id)],audioCuts:[.init(time:.init(value:3,timescale:1),angleID:assets[1].id)])
    let tracks=assets.enumerated().map{Track(name:"\($0.offset)",kind:$0.offset==2 ? .audio:.video,clips:[Clip(assetID:$0.element.id,duration:d)])}
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:tracks,multicamGroups:[group]),assets:assets));store.cameraAudioIDs=Set(assets.map(\.id));store.checkingCameraAudio=false;store.panel = .multicam;store.pixelsPerSecond=100;store.snapping=false
    return store
}
@MainActor @Test func multicamCutProposalIsAtomicFrameQuantizedAndLaneIndependent()throws {
    let store=cutStore(),before=store.document,group=try #require(store.multicamGroup),id=group.cuts[1].id
    let proposal=try store.proposeMulticamCut(id,audio:false,seconds:2.19,baseline:before)
    #expect(store.document==before)
    #expect(proposal.time==store.document.sequence.settings.frameRate.quantized(store.time(2.19,audio:true)))
    #expect(store.commitMulticamCut(proposal));let after=store.document
    #expect(after.sequence.multicamGroups[0].audioCuts==group.audioCuts)
    #expect(after.sequence.multicamGroups[0].masterAudioAssetID==group.masterAudioAssetID)
    store.undo();#expect(store.document==before);store.redo();#expect(store.document==after)
    #expect(throws:(any Error).self){try store.proposeMulticamCut(id,audio:false,seconds:4,baseline:after)}
    #expect(throws:(any Error).self){try store.proposeMulticamCut(group.cuts[0].id,audio:false,seconds:0.1,baseline:after)}
    #expect(!store.commitMulticamCut(proposal));#expect(store.document==after)
}
@MainActor @Test func multicamCutEditingRejectsLocksStateAndMissingIntervals()throws {
    let store=cutStore(),id=try #require(store.multicamGroup?.cuts[1].id)
    for mode in 0..<3 {
        store.playing=mode==0;store.switchArmed=mode==1;store.checkingCameraAudio=mode==2
        #expect(throws:(any Error).self){try store.proposeMulticamCut(id,audio:false,seconds:2.5,baseline:store.document)}
    }
    store.playing=false;store.switchArmed=false;store.checkingCameraAudio=false
    var doc=store.document;doc.sequence.tracks[1].isLocked=true;store.replace(doc)
    #expect(throws:(any Error).self){try store.proposeMulticamCut(id,audio:false,seconds:2.5,baseline:store.document)}
    doc.sequence.tracks[1].isLocked=false;doc.sequence.tracks[0].clips[0].duration = .init(value:2,timescale:1);store.replace(doc)
    #expect(throws:(any Error).self){try store.proposeMulticamCut(id,audio:false,seconds:2.5,baseline:store.document)}
}
@MainActor @Test func multicamCutPointerGhostCommitsOnceAndOptionBypassesSnap()throws {
    let store=cutStore(),before=store.document,cut=try #require(store.multicamGroup?.cuts[1])
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:900,height:400)
    func event(_ type:NSEvent.EventType,_ point:NSPoint,_ flags:NSEvent.ModifierFlags=[])->NSEvent {NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    let start=NSPoint(x:canvas.x(2),y:46),end=NSPoint(x:canvas.x(2.5),y:46)
    canvas.mouseDown(with:event(.leftMouseDown,start));canvas.mouseDragged(with:event(.leftMouseDragged,end))
    #expect(canvas.cutDrag?.proposal != nil);#expect(store.document==before)
    canvas.mouseUp(with:event(.leftMouseUp,end));let after=store.document
    #expect(after.sequence.multicamGroups[0].cuts.first(where:{$0.id==cut.id})?.time.seconds==2.5)
    store.undo();#expect(store.document==before);store.redo();#expect(store.document==after)
    store.snapping=true;store.playhead=3
    let moved=NSPoint(x:canvas.x(2.5),y:46),near=NSPoint(x:canvas.x(2.96),y:46)
    canvas.mouseDown(with:event(.leftMouseDown,moved));canvas.mouseDragged(with:event(.leftMouseDragged,near))
    #expect(canvas.cutDrag?.target==3);#expect(canvas.snapLabel=="Cut")
    canvas.mouseDragged(with:event(.leftMouseDragged,near,.option));#expect(canvas.cutDrag?.target != 3);#expect(canvas.snapX==nil)
    // A concurrent project edit invalidates the pending pointer proposal.
    var newer=store.document;newer.sequence.tracks[2].name="Master renamed";store.replace(newer)
    canvas.mouseUp(with:event(.leftMouseUp,near));#expect(store.document==newer)
    canvas.refreshAccessibility();#expect(canvas.accessibilityChildren()?.isEmpty==false)
    store.panel = .clip;#expect(!canvas.showsDecisionLanes);#expect(canvas.decisionHeight==0)
    window.orderOut(nil)
}

@MainActor @Test func multicamCutIgnoresUnchangedMissingTail()throws {
    let store=cutStore()
    var doc=store.document;doc.sequence.tracks[0].clips[0].duration = .init(value:5,timescale:1)
    store.replace(doc)
    let cut=try #require(store.multicamGroup?.cuts[1])
    let proposal=try store.proposeMulticamCut(cut.id,audio:false,seconds:2.5,baseline:store.document)
    #expect(store.commitMulticamCut(proposal))
}

@MainActor @Test func multicamUnsortedPersistedCutsRefineChronologicallyAndUndoExactly()throws {
    let store=cutStore();var doc=store.document
    let ordered=doc.sequence.multicamGroups[0].cuts
    doc.sequence.multicamGroups[0].cuts=[ordered[1],ordered[0],ordered[2]];try doc.validate();store.replace(doc)
    let candidate=try store.proposeMulticamCut(ordered[1].id,audio:false,seconds:3,baseline:doc)
    #expect(candidate.document.sequence.multicamGroups[0].cuts.map(\.time)==[.zero,.init(value:3,timescale:1),.init(value:4,timescale:1)])
    #expect(store.commitMulticamCut(candidate));store.undo();#expect(store.document==doc)
}
@MainActor @Test func multicamAudioPointerPreservesVideoAndRejectsPendingPreview()throws {
    let store=cutStore(),before=store.document,cut=try #require(store.multicamGroup?.audioCuts?.first)
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:900,height:400)
    func event(_ type:NSEvent.EventType,_ p:NSPoint)->NSEvent{NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    let origin=NSPoint(x:canvas.x(3),y:74),end=NSPoint(x:canvas.x(3.5),y:74)
    canvas.mouseDown(with:event(.leftMouseDown,origin));canvas.mouseDragged(with:event(.leftMouseDragged,end));#expect(store.document==before)
    canvas.mouseUp(with:event(.leftMouseUp,end));#expect(store.multicamGroup?.cuts==before.sequence.multicamGroups[0].cuts);#expect(store.multicamGroup?.audioCuts?.first?.time.seconds==3.5)
    var locked=store.document;locked.sequence.tracks[2].isLocked=true;store.replace(locked)
    #expect(throws:(any Error).self){try store.proposeMulticamCut(cut.id,audio:true,seconds:3.75,baseline:locked)}
    locked.sequence.tracks[2].isLocked=false;store.replace(locked)
    let clip=try #require(locked.sequence.tracks.first?.clips.first)
    var placementSource=locked;placementSource.sequence.multicamGroups=[]
    store.placementProposal=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[clip.id],at:.init(value:6,timescale:1)),in:placementSource)
    #expect(throws:(any Error).self){try store.proposeMulticamCut(cut.id,audio:true,seconds:3.75,baseline:locked)}
    canvas.mouseDown(with:event(.leftMouseDown,.init(x:canvas.x(3.5),y:74)));#expect(canvas.cutDrag==nil);#expect(store.document==locked)
    store.placementProposal=nil;window.orderOut(nil)
}

@MainActor @Test func multicamCutEscapeCancelsGhostAndExposesNamedAccessibilityTargets()throws {
    _ = NSApplication.shared
    let store=cutStore(),before=store.document
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:900,height:400);defer{window.orderOut(nil)}
    func pointer(_ type:NSEvent.EventType,_ p:NSPoint)->NSEvent{NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    let origin=NSPoint(x:canvas.x(2),y:46),target=NSPoint(x:canvas.x(2.5),y:46)
    canvas.mouseDown(with:pointer(.leftMouseDown,origin));canvas.mouseDragged(with:pointer(.leftMouseDragged,target))
    try #require(canvas.cutDrag?.proposal != nil)
    let escape=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
    canvas.keyDown(with:escape);canvas.mouseUp(with:pointer(.leftMouseUp,target))
    #expect(canvas.cutDrag==nil && canvas.snapX==nil && store.document==before)
    canvas.refreshAccessibility()
    let labels=(canvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []).compactMap{$0.accessibilityLabel()}
    #expect(labels.contains("Video cut, source 2"))
    #expect(labels.contains("Audio cut, source 2"))
    let bitmap=try #require(canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds));canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
    let directory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["LIFE_UI_ARTIFACTS"] ?? "/tmp/life-editor-ui-checks",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try #require(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("multicam-decision-lanes.png"))
}

@MainActor @Test func multicamCutDeleteNeverDeletesPreviouslySelectedMedia()throws {
    _ = NSApplication.shared
    let store=cutStore(),before=store.document,clip=try #require(before.sequence.tracks.first?.clips.first)
    store.selection=clip.id;store.selectedIDs=[clip.id]
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:400),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:900,height:400);defer{window.orderOut(nil)}
    let point=canvas.convert(NSPoint(x:canvas.x(2),y:46),to:nil)
    let click=try #require(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
    canvas.mouseDown(with:click);#expect(store.selection==nil && store.selectedIDs.isEmpty)
    let delete=try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{7f}",charactersIgnoringModifiers:"\u{7f}",isARepeat:false,keyCode:51))
    canvas.keyDown(with:delete)
    #expect(store.document.sequence.tracks==before.sequence.tracks)
    #expect(store.multicamGroup?.cuts.count==2)
    #expect(store.multicamGroup?.audioCuts==before.sequence.multicamGroups[0].audioCuts)
    #expect(canvas.cutDrag==nil)
    store.undo();#expect(store.document==before)
    canvas.selectedCutID=before.sequence.multicamGroups[0].cuts[0].id
    canvas.keyDown(with:delete);#expect(store.document==before)
}
