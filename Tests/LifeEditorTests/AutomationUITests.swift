import Testing
import Foundation
import AppKit
import SwiftUI
import LifeCore
@testable import LifeEditor
private func at(_ n:Int64,_ d:Int64=1)->RationalTime { .init(value:n,timescale:d) }
@MainActor private func automationFixture(envelope:AutomationEnvelope = .init(),locked:Bool = false)->(EditorStore,Clip) {
    let clip=Clip(duration:at(4),volume:envelope,title:TitleContent(text:"Test"))
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Title",kind:.title,clips:[clip],isLocked:locked)])));store.selection=clip.id;store.automationLane = .volume
    return (store,clip)
}
@MainActor @Test func automationPointsUseSameEnvelopePreserveHiddenPointsAndGroupedUndo() throws {
    let envelope=AutomationEnvelope(baseValue:0.5,points:[.init(time:.zero,value:0.5),.init(time:at(2),value:1),.init(time:at(4),value:0),.init(time:at(8),value:0.7)],evaluationOffset:at(2))
    let (store,_)=automationFixture(envelope:envelope), initial=store.document
    let hidden=envelope.points.filter { $0.time == .zero || $0.time == at(8) }
    store.beginGesture()
    let id=try #require(store.addAutomationPoint(at:1,effectiveValue:0.25))
    store.updateAutomationPoint(id:id,sequenceTime:1.5,effectiveValue:0.2,interpolation:.hold)
    store.endGesture()
    #expect(store.currentAutomationPoint?.time == at(7,2))
    #expect(store.currentAutomationPoint?.interpolation == .hold)
    #expect(abs((store.currentAutomationPoint?.value ?? 0)*store.currentAutomationEnvelope.baseValue-0.2)<0.000001)
    #expect(hidden.allSatisfy { store.currentAutomationEnvelope.points.contains($0) })
    store.undo();#expect(store.document == initial)
    store.redo();#expect(store.currentAutomationEnvelope.points.contains { $0.id == id })
    store.setLaneFade(1,incoming:true);store.setLaneFade(1,incoming:false)
    #expect(store.currentAutomationEnvelope.value(at:.zero) == 0)
    #expect(store.currentAutomationEnvelope.value(at:at(4)) == 0)
    #expect(hidden.allSatisfy { store.currentAutomationEnvelope.points.contains($0) })
}
@MainActor @Test func automationHandlesNegativeOffsetsSilenceAndLockedTracks() throws {
    let oldPoints=[AutomationPoint(time:.zero,value:0),AutomationPoint(time:at(4),value:1)]
    let (store,_)=automationFixture(envelope:AutomationEnvelope(points:oldPoints,evaluationOffset:at(-2)))
    let before=store.currentAutomationEnvelope.value(at:at(4))
    #expect(store.addAutomationPoint(at:1,effectiveValue:0.3) != nil)
    #expect(store.currentAutomationEnvelope.evaluationOffset == at(-1))
    #expect(store.currentAutomationEnvelope.points.allSatisfy { $0.time >= .zero })
    #expect(store.currentAutomationEnvelope.value(at:at(4)) == before)
    store.setAutomationBase(0)
    #expect(store.currentAutomationEnvelope.value(at:at(2)) == 0)
    #expect(store.addAutomationPoint(at:2,effectiveValue:1) != nil)
    #expect(store.currentAutomationEnvelope.baseValue == 1)
    let (locked,_)=automationFixture(locked:true),original=locked.document
    #expect(locked.addAutomationPoint(at:1,effectiveValue:0.5) == nil)
    locked.setAutomationBase(0.5);locked.setLaneFade(1,incoming:true)
    #expect(locked.document == original)
    #expect(locked.error == "Unlock the track to edit.")
}
@MainActor @Test func automationNumericNavigationDeletionAndPracticalInspector() throws {
    _ = NSApplication.shared
    let (store,_)=automationFixture()
    let a=try #require(store.addAutomationPoint(at:1,effectiveValue:0.25)), b=try #require(store.addAutomationPoint(at:3,effectiveValue:0.75))
    store.selectedAutomationPoint=a;store.selectAdjacentAutomationPoint(1)
    #expect(store.selectedAutomationPoint == b)
    store.selectAdjacentAutomationPoint(-1);#expect(store.selectedAutomationPoint == a)
    store.updateAutomationPoint(id:a,effectiveValue:0.5,interpolation:.eased)
    #expect(store.currentAutomationPoint?.interpolation == .eased)
    store.deleteAutomationPoint();#expect(!store.currentAutomationEnvelope.points.contains { $0.id == a })
    store.undo();#expect(store.currentAutomationEnvelope.points.contains { $0.id == a })
    let host=NSHostingView(rootView:AutomationControls(store:store));host.frame=NSRect(x:0,y:0,width:280,height:400);host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=280)
    #expect(AutomationScale.parse("−∞",lane:.volume) == 0)
    #expect(AutomationScale.parse("silence",lane:.volume) == 0)
    #expect(AutomationScale.parse("25",lane:.volume) == nil)
    #expect(AutomationScale.parse("100",lane:.opacity) == 1)
    #expect(AutomationScale.label(0,lane:.volume) == "−∞ dB")
}
@MainActor @Test func timelineCommandClickAddsAndDragsAnAutomationPointWithOneUndo() throws {
    _ = NSApplication.shared
    let (store,clip)=automationFixture();store.pixelsPerSecond=100;store.snapping=false
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:250),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:800,height:250)
    let box=canvas.rect(clip,row:0),y=box.maxY-8-AutomationScale.position(1,lane:.volume)*28
    func event(_ type:NSEvent.EventType,_ point:NSPoint,_ modifiers:NSEvent.ModifierFlags=[])->NSEvent {
        NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:modifiers,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    }
    let start=NSPoint(x:canvas.x(1),y:y)
    canvas.mouseDown(with:event(.leftMouseDown,start,.command));canvas.mouseUp(with:event(.leftMouseUp,start,.command))
    let id=try #require(store.selectedAutomationPoint),before=store.document
    canvas.mouseDown(with:event(.leftMouseDown,start))
    canvas.mouseDragged(with:event(.leftMouseDragged,NSPoint(x:canvas.x(1.6),y:box.maxY-8)))
    canvas.mouseUp(with:event(.leftMouseUp,NSPoint(x:canvas.x(1.6),y:box.maxY-8)))
    #expect(store.currentAutomationPoint?.id == id)
    #expect(abs(store.automationLocalTime(try #require(store.currentAutomationPoint))-1.6)<0.000001)
    #expect(store.currentAutomationPoint?.value == 0)
    store.undo();#expect(store.document == before)
}
@MainActor @Test func timelineFrameGridSnappingDoesNotDiscardMusicalAnchors() throws {
    let (store,_)=automationFixture();store.pixelsPerSecond=100;store.playhead=20
    let music=MusicalGrid(bpm:100,anchors:[BeatAnchor(time:at(1),beatIndex:0),BeatAnchor(time:at(7),beatIndex:8)])
    store.document.sequence.musicalGrid=music;store.gridMode = .frames
    let canvas=TimelineCanvas(store:store),snap=try #require(canvas.snappedTime(0.105))
    #expect(snap.label == "Frame");#expect(abs(snap.time-0.1)<0.000001)
    store.gridMode = .time
    #expect(store.document.sequence.musicalGrid == music)
    store.gridMode = .beats
    #expect(store.document.sequence.musicalGrid == music)
}
@MainActor @Test func timelineLineAndBothFadeHandlesEditOneEnvelopeAndUndoPerGesture() throws {
    _ = NSApplication.shared
    let (store,clip)=automationFixture();store.pixelsPerSecond=100;store.snapping=false
    let canvas=TimelineCanvas(store:store),window=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:250),styleMask:[.titled],backing:.buffered,defer:false)
    window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:800,height:250)
    let box=canvas.rect(clip,row:0),lineY=box.maxY-8-AutomationScale.position(1,lane:.volume)*28
    func gesture(_ start:NSPoint,_ end:NSPoint) {
        func event(_ type:NSEvent.EventType,_ point:NSPoint)->NSEvent { NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)! }
        canvas.mouseDown(with:event(.leftMouseDown,start));canvas.mouseDragged(with:event(.leftMouseDragged,end));canvas.mouseUp(with:event(.leftMouseUp,end))
    }
    let before=store.document
    gesture(NSPoint(x:canvas.x(2),y:lineY),NSPoint(x:canvas.x(2),y:lineY-10))
    #expect(store.currentAutomationEnvelope.baseValue>1)
    #expect(store.currentAutomationEnvelope.points.isEmpty)
    store.undo();#expect(store.document == before)
    gesture(NSPoint(x:box.minX+8,y:box.minY+24),NSPoint(x:canvas.x(1),y:box.minY+24))
    #expect(store.currentAutomationEnvelope.value(at:.zero) == 0)
    #expect(store.currentAutomationEnvelope.value(at:at(2)) == 1)
    let afterIncoming=store.document
    gesture(NSPoint(x:box.maxX-8,y:box.minY+24),NSPoint(x:canvas.x(3),y:box.minY+24))
    #expect(store.currentAutomationEnvelope.value(at:.zero) == 0)
    #expect(store.currentAutomationEnvelope.value(at:at(4)) == 0)
    #expect(store.currentAutomationEnvelope.points.count == 4)
    store.undo();#expect(store.document == afterIncoming)
}
