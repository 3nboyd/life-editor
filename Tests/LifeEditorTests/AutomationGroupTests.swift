import Testing
import Foundation
import AppKit
import LifeCore
@testable import LifeEditor
private func gt(_ n:Int64,_ d:Int64=1)->RationalTime{.init(value:n,timescale:d)}
@MainActor private func groupFixture(quiet:Bool=false)->(EditorStore,[AutomationPoint]){
    let points=[AutomationPoint(time:.zero,value:0.9),AutomationPoint(time:gt(2),value:quiet ? 0.0001:0.25),AutomationPoint(time:gt(3),value:quiet ? 0.0002:0.5),AutomationPoint(time:gt(7),value:0.8)]
    let envelope=AutomationEnvelope(points:points,evaluationOffset:gt(1))
    let clip=Clip(duration:gt(4),volume:envelope,title:TitleContent(text:"Group"))
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Title",kind:.title,clips:[clip])])));store.selection=clip.id;store.automationLane = .volume
    store.selectAllVisibleAutomationPoints();return(store,points)
}
@MainActor @Test func automationGroupSelectionCurveCopyDeleteAndUndo() throws{
    let(store,points)=groupFixture(),before=store.document
    #expect(store.selectedAutomationPointIDs==Set([points[1].id,points[2].id]))
    store.updateAutomationPoint(id:points[1].id,interpolation:.hold)
    #expect(store.selectedVisibleAutomationPoints.allSatisfy{$0.interpolation == .hold})
    #expect(store.currentAutomationEnvelope.points.contains(points[0]));#expect(store.currentAutomationEnvelope.points.contains(points[3]))
    store.undo();#expect(store.document==before)
    let pasteboard=NSPasteboard.withUniqueName();defer{pasteboard.releaseGlobally()}
    store.copyAutomationPoint(to:pasteboard)
    #expect(try AutomationPointClipboard.read(from:pasteboard).checked(for:.volume).count==2)
    store.deleteAutomationPoint();#expect(store.currentAutomationEnvelope.points==[points[0],points[3]])
    store.undo();#expect(store.document==before)
    store.selectAllVisibleAutomationPoints();store.automationLane = .opacity;#expect(store.selectedAutomationPointIDs.isEmpty)
}
@MainActor @Test func automationGroupTranslationIsAtomicExactAndPreservesHiddenPoints() throws{
    let(store,points)=groupFixture(),before=store.document
    #expect(store.updateSelectedAutomationPoints(anchorID:points[1].id,sequenceTime:1+1.0/48000))
    for point in store.selectedVisibleAutomationPoints{
        let old=try #require(points.first{$0.id==point.id});#expect(point.time==old.time+gt(1,48000));#expect(point.value==old.value)
    }
    #expect(store.currentAutomationEnvelope.points.contains(points[0]));#expect(store.currentAutomationEnvelope.points.contains(points[3]))
    store.undo();#expect(store.document==before)
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[1].id,sequenceTime:4));#expect(store.document==before)
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[1].id,effectiveValue:AudioSettings.maximumLinearGain));#expect(store.document==before)
    store.selectAutomationPoint(points[2].id,toggle:true)
    // An unselected existing point is an atomic collision, never replaced.
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[1].id,sequenceTime:2));#expect(store.document==before)
    let clip=try #require(store.selectedClip)
    store.placementProposal=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[clip.id],at:gt(5)),in:store.document)
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[1].id,sequenceTime:1.5));#expect(store.document==before)
    store.placementProposal=nil
    store.document.sequence.tracks[0].isLocked=true;let locked=store.document
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[1].id,sequenceTime:1.5));#expect(store.document==locked)
}
@MainActor @Test func automationGroupQuietFloorNoopAndIndividualNumericPrecision() throws{
    let(store,points)=groupFixture(quiet:true),before=store.document
    #expect(store.updateSelectedAutomationPoints(anchorID:points[1].id,effectiveValue:points[1].value));#expect(store.document==before)
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[1].id,effectiveValue:pow(10,-90.0/20)));#expect(store.document==before)
    #expect(store.error=="Edit points below −60 dB individually.")
    #expect(store.updateSelectedAutomationPoints(anchorID:points[1].id,sequenceTime:1.5))
    #expect(store.selectedVisibleAutomationPoints.map(\.value)==[points[1].value,points[2].value])
    store.selectAutomationPoint(points[1].id)
    store.updateAutomationPoint(id:points[1].id,effectiveValue:pow(10,-96.0/20))
    #expect(store.currentAutomationPoint?.value==pow(10,-96.0/20))
}
@MainActor @Test func automationGroupTimelineShiftSelectionKeyboardAndDrag() throws{
    _ = NSApplication.shared
    let(store,points)=groupFixture();store.snapping=false;store.pixelsPerSecond=100
    let clip=try #require(store.selectedClip),canvas=TimelineCanvas(store:store)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:250),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:800,height:250)
    let box=canvas.rect(clip,row:0)
    func center(_ p:AutomationPoint)->NSPoint{.init(x:canvas.x((p.time-clip.volume.evaluationOffset).seconds),y:box.maxY-8-AutomationScale.position(p.value,lane:.volume)*28)}
    func event(_ type:NSEvent.EventType,_ p:NSPoint,_ flags:NSEvent.ModifierFlags=[])->NSEvent{NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    store.selectAutomationPoint(points[1].id)
    canvas.mouseDown(with:event(.leftMouseDown,center(points[2]),.shift));canvas.mouseUp(with:event(.leftMouseUp,center(points[2]),.shift))
    #expect(store.selection==clip.id);#expect(store.selectedAutomationPointIDs.count==2)
    let before=store.document,start=center(points[1]),end=NSPoint(x:start.x+25,y:start.y)
    canvas.mouseDown(with:event(.leftMouseDown,start));canvas.mouseDragged(with:event(.leftMouseDragged,end));canvas.mouseUp(with:event(.leftMouseUp,end))
    #expect(store.selectedVisibleAutomationPoints.map(\.time)==[gt(9,4),gt(13,4)])
    store.undo();#expect(store.document==before)
    canvas.refreshAccessibility()
    let elements=(canvas.accessibilityChildren() ?? []).compactMap{$0 as? NSAccessibilityElement}
    #expect(elements.filter{$0.accessibilityLabel()=="Toggle volume point"}.count==2)
    let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:27)!
    canvas.keyDown(with:key);#expect(store.selectedAutomationPointIDs.isEmpty)
}
@MainActor @Test func automationGroupUnrepresentableRationalDeltaRejectsWithoutMutation() throws{
    let p:Int64=999_999_937,q:Int64=999_999_929
    let points=[AutomationPoint(time:gt(p+1,p),value:0.25),AutomationPoint(time:gt(2*p+1,p),value:0.5)]
    let clip=Clip(duration:gt(4),volume:.init(points:points,evaluationOffset:gt(1,q)),title:TitleContent(text:"Prime"))
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Prime",kind:.title,clips:[clip])]))
    try document.validate()
    let store=EditorStore();store.replace(document);store.selection=clip.id;store.automationLane = .volume;store.selectAllVisibleAutomationPoints()
    let exactLocal=try points[0].time.checkedSubtracting(clip.volume.evaluationOffset)
    #expect(store.updateSelectedAutomationPoints(anchorID:points[0].id,sequenceTime:exactLocal.seconds));#expect(store.document==document)
    #expect(!store.updateSelectedAutomationPoints(anchorID:points[0].id,sequenceTime:1+1.0/48000))
    #expect(store.document==document);#expect(store.error=="Choose a representable point time.")
}

@MainActor @Test func automationGroupNegativeEvaluationOffsetRebasesAllClocksLosslessly() throws{
    let points=[AutomationPoint(time:.zero,value:0.25),AutomationPoint(time:gt(1),value:0.5),AutomationPoint(time:gt(3),value:0.75)]
    let envelope=AutomationEnvelope(points:points,evaluationOffset:gt(-2))
    let clip=Clip(duration:gt(4),volume:envelope,title:TitleContent(text:"Offset"))
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Offset",kind:.title,clips:[clip])])));store.selection=clip.id;store.automationLane = .volume;store.selectAllVisibleAutomationPoints()
    #expect(store.updateSelectedAutomationPoints(anchorID:points[0].id,sequenceTime:0.5))
    #expect(store.selectedVisibleAutomationPoints.map{store.automationLocalTime($0)}==[0.5,1.5])
    let hidden=try #require(store.currentAutomationEnvelope.points.first{$0.id==points[2].id})
    #expect(hidden.value==points[2].value);#expect(store.automationLocalTime(hidden)==5)
    try store.document.validate()
}

@MainActor @Test func automationGroupTrimReconcilesHiddenPrimaryAndKeepsRemainingEditable() throws{
    let(store,points)=groupFixture()
    let clip=try #require(store.selectedClip)
    store.selectAutomationPoint(points[1].id);store.selectAutomationPoint(points[2].id,toggle:true)
    store.selectAutomationPoint(points[1].id,preserveGroup:true)
    let before=store.document
    store.apply(.trim(clipID:clip.id,start:gt(3,2),end:gt(4)))
    let trimmed=store.document
    #expect(store.selectedAutomationPointIDs==[points[2].id])
    #expect(store.currentAutomationPoint?.id==points[2].id)
    store.updateAutomationPoint(id:points[2].id,interpolation:.hold)
    #expect(store.currentAutomationPoint?.interpolation == .hold)
    store.undo();#expect(store.document==trimmed)
    store.undo();#expect(store.document==before)
    #expect(store.selectedAutomationPointIDs==[points[2].id])
}
