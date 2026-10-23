import AppKit
import Testing
import LifeCore
@testable import LifeEditor
private func cpTime(_ n:Int64,_ d:Int64=1)->RationalTime{.init(value:n,timescale:d)}
@MainActor private func clipboardStore(source:AutomationEnvelope,target:AutomationEnvelope = .init(),lane:AutomationLane = .volume,locked:Bool=false)->(EditorStore,Clip,Clip){
    let first=Clip(duration:cpTime(2),volume:lane == .volume ? source:.init(),opacity:lane == .opacity ? source:.init(),title:TitleContent(text:"Source")),second=Clip(start:cpTime(3),duration:cpTime(2),volume:lane == .volume ? target:.init(),opacity:lane == .opacity ? target:.init(),title:TitleContent(text:"Target"))
    let store=EditorStore();store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Titles",kind:.title,clips:[first,second],isLocked:locked)])));store.selection=first.id;store.automationLane=lane
    return (store,first,second)
}
@MainActor @Test func automationClipboardCopiesVisibleRelativePointsMergesExactTimesAndUndoes()throws{
    let source=AutomationEnvelope(baseValue:0.5,points:[.init(time:.zero,value:0.2),.init(time:cpTime(2),value:0.2,interpolation:.hold),.init(time:cpTime(3),value:0.8,interpolation:.eased),.init(time:cpTime(7),value:0.6)],evaluationOffset:cpTime(2))
    let collision=AutomationPoint(time:.zero,value:0.1),hidden=AutomationPoint(time:cpTime(5),value:0.8)
    let target=AutomationEnvelope(baseValue:0.25,points:[collision,hidden],evaluationOffset:cpTime(-1)),(store,first,second)=clipboardStore(source:source,target:target)
    let board=NSPasteboard(name:.init(UUID().uuidString));defer{board.releaseGlobally()}
    store.copyVisibleAutomationPoints(to:board);let payload=try AutomationPointClipboard.read(from:board),points=try payload.checked(for:.volume)
    #expect(points.count==2 && points[0].offset == .zero && points[1].offset==cpTime(1))
    store.selection=second.id;store.automationLane = .volume;store.playheadTime=second.start
    let before=store.document;store.pasteAutomationPoints(from:board);let pasted=try #require(store.selectedClip?.volume)
    #expect(pasted.evaluationOffset == .zero)
    #expect(abs(pasted.value(at:cpTime(1,2))-0.1)<0.000001);#expect(abs(pasted.value(at:cpTime(1))-0.4)<0.000001)
    #expect(pasted.points.contains{$0.id==collision.id && $0.time==cpTime(1) && $0.interpolation == .eased})
    let kept=try #require(pasted.points.first{$0.id==hidden.id});#expect(kept.time-pasted.evaluationOffset==hidden.time-target.evaluationOffset);#expect(kept.value*pasted.baseValue==hidden.value*target.baseValue)
    let selected=try #require(store.selectedAutomationPoint);#expect(!source.points.contains{$0.id==selected})
    #expect(store.document.sequence.tracks[0].clips.first{$0.id==first.id}?.volume==source)
    #expect(try ProjectDocument.decode(store.document.encoded())==store.document)
    let after=store.document;store.undo();#expect(store.document==before);store.redo();#expect(store.document==after)
}
@MainActor @Test func automationClipboardSelectedPointSampleAnchorZeroAndTinyBasesRemainFinite()throws{
    for base in [0.0,1e-308]{
        let source=AutomationEnvelope(baseValue:AudioSettings.maximumLinearGain,points:[.init(time:cpTime(1,48000),value:1,interpolation:.hold)])
        let existing=AutomationPoint(time:cpTime(2),value:0.5),target=AutomationEnvelope(baseValue:base,points:[existing])
        let (store,first,second)=clipboardStore(source:source,target:target),board=NSPasteboard(name:.init(UUID().uuidString));defer{board.releaseGlobally()}
        store.selectedAutomationPoint=first.volume.points[0].id;store.copyAutomationPoint(to:board)
        store.selection=second.id;store.automationLane = .volume;store.playheadTime=try second.start.checkedAdding(cpTime(1,48000))
        store.pasteAutomationPoints(from:board);let envelope=try #require(store.selectedClip?.volume),point=try #require(store.currentAutomationPoint)
        #expect(point.time-envelope.evaluationOffset==cpTime(1,48000));#expect(point.interpolation == .hold)
        #expect(abs(point.value*envelope.baseValue-AudioSettings.maximumLinearGain)<0.000001)
        #expect(envelope.points.allSatisfy{$0.value.isFinite});#expect(envelope.points.first{$0.id==existing.id}?.value==base*existing.value)
        #expect(try ProjectDocument.decode(store.document.encoded())==store.document)
    }
}
@MainActor @Test func automationClipboardRejectsMalformedRangesLanesLockedAndPendingPlacementAtomically()throws{
    let source=AutomationEnvelope(points:[.init(time:.zero,value:0),.init(time:cpTime(2),value:1)]),(store,_,second)=clipboardStore(source:source),board=NSPasteboard(name:.init(UUID().uuidString));defer{board.releaseGlobally()}
    store.copyVisibleAutomationPoints(to:board);let valid=try #require(board.data(forType:AutomationPointClipboard.type));store.selection=second.id;store.automationLane = .volume;store.playheadTime=cpTime(4)
    let before=store.document;store.pasteAutomationPoints(from:board);#expect(store.document==before)
    store.playheadTime=second.start;store.automationLane = .opacity;store.pasteAutomationPoints(from:board);#expect(store.document==before);store.automationLane = .volume
    let malformed=[
        #"{"version":1,"lane":"volume","points":[{"offset":{"value":0,"timescale":0},"effectiveValue":1,"interpolation":"linear"}]}"#,
        #"{"version":1,"lane":"volume","points":[{"offset":{"value":0,"timescale":-1},"effectiveValue":1,"interpolation":"linear"}]}"#,
        #"{"version":1,"lane":"volume","points":[{"offset":{"value":1,"timescale":4000000000},"effectiveValue":1,"interpolation":"linear"}]}"#,
        #"{"version":1,"lane":"volume","points":[{"offset":{"value":-1,"timescale":1},"effectiveValue":1,"interpolation":"linear"}]}"#,
        #"{"version":1,"lane":"volume","points":[{"offset":{"value":9223372036854775807,"timescale":1},"effectiveValue":1,"interpolation":"linear"}]}"#,
        #"{"version":2,"lane":"volume","points":[]}"#,
        #"{"version":1,"lane":"volume","points":[{"offset":{"value":0,"timescale":1},"effectiveValue":1,"interpolation":"linear"},{"offset":{"value":0,"timescale":1},"effectiveValue":0,"interpolation":"hold"}]}"#
    ]
    for raw in malformed{board.clearContents();board.setData(Data(raw.utf8),forType:AutomationPointClipboard.type);store.pasteAutomationPoints(from:board);#expect(store.document==before)}
    board.setData(Data(repeating:32,count:AutomationPointClipboard.maximumBytes+1),forType:AutomationPointClipboard.type);store.pasteAutomationPoints(from:board);#expect(store.document==before)
    board.setData(valid,forType:AutomationPointClipboard.type)
    store.placementProposal=try SpliceEditing.proposal(for:.insertCopies(clipIDs:[second.id],at:cpTime(3)),in:before);store.pasteAutomationPoints(from:board);#expect(store.document==before);store.placementProposal=nil
    var locked=before;locked.sequence.tracks[0].isLocked=true;store.replace(locked);store.selection=second.id;store.pasteAutomationPoints(from:board);#expect(store.document==locked)
}

@MainActor @Test func automationClipboardMergesDecodedEquivalentFractionWithoutDuplicatingTargetID()throws{
    let id=UUID(),data=Data("{\"id\":\"\(id.uuidString)\",\"time\":{\"value\":2,\"timescale\":2},\"value\":0.1,\"interpolation\":\"linear\"}".utf8)
    let existing=try JSONDecoder().decode(AutomationPoint.self,from:data)
    let source=AutomationEnvelope(points:[.init(time:.zero,value:0.8)]),target=AutomationEnvelope(points:[existing]),(store,first,second)=clipboardStore(source:source,target:target)
    let board=NSPasteboard(name:.init(UUID().uuidString));defer{board.releaseGlobally()}
    store.selectedAutomationPoint=first.volume.points[0].id;store.copyAutomationPoint(to:board);store.selection=second.id;store.automationLane = .volume;store.playheadTime=second.start+cpTime(1)
    store.pasteAutomationPoints(from:board)
    #expect(store.selectedClip?.volume.points.count==1);#expect(store.selectedClip?.volume.points[0].id==id);#expect(store.selectedClip?.volume.points[0].value==0.8)
}

@MainActor @Test func automationClipboardCopyLimitKeepsExistingPrivateClipboardAndProject()throws{
    let points=(0...10000).map{AutomationPoint(time:cpTime(Int64($0),48000),value:0.5)},(store,_,_)=clipboardStore(source:.init(points:points))
    let board=NSPasteboard(name:.init(UUID().uuidString));defer{board.releaseGlobally()}
    let original=Data("existing private clipboard".utf8);board.setData(original,forType:AutomationPointClipboard.type)
    let document=store.document;store.copyVisibleAutomationPoints(to:board)
    #expect(board.data(forType:AutomationPointClipboard.type)==original);#expect(store.document==document);#expect(store.error?.contains("10,000")==true)
}
