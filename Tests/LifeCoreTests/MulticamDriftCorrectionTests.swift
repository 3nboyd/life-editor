import Foundation
import Testing
@testable import LifeCore

private func driftFit(_ slope:Double=1.001,_ origin:Double=2)throws->AffineDriftCorrection {
    func anchor(_ source:Double)->DriftAnchor{.init(sourceSeconds:source,referenceSeconds:origin+slope*source,confidence:0.9,uncertaintySeconds:0.023)}
    return try .fit(early:anchor(20),middle:anchor(200),late:anchor(400))
}
@Test func affineDriftFitsUnitsSignRoundedRateAndRejectsUnreliableNonlinearAnchors()throws {
    let fit=try driftFit()
    #expect(abs(fit.speed-0.999001)<0.0000001)
    #expect(abs(fit.sourceOrigin+20/fit.speed-22.02)<0.000001)
    let reverse=try driftFit(0.999)
    #expect(reverse.speed>1)
    var middle=fit.middle;middle.referenceSeconds+=0.2
    #expect(throws:DriftCorrectionError.nonlinear){try AffineDriftCorrection.fit(early:fit.early,middle:middle,late:fit.late)}
    var early=fit.early;early.confidence=0.2
    #expect(throws:DriftCorrectionError.unreliable){try AffineDriftCorrection.fit(early:early,middle:fit.middle,late:fit.late)}
}
@MainActor @Test func driftCandidatePreservesMasterOriginalsMarkersCutsAndUndo()throws {
    let camera=MediaAsset(url:URL(fileURLWithPath:"/camera.mov"),kind:.video,duration:.init(value:600,timescale:1))
    let master=MediaAsset(url:URL(fileURLWithPath:"/master.wav"),kind:.audio,duration:.init(value:600,timescale:1))
    let first=Clip(assetID:camera.id,duration:.init(value:100,timescale:1),preservesPitch:false,volume:.init(points:[.init(time:.init(value:50,timescale:1),value:0.5)]))
    let second=Clip(assetID:camera.id,start:.init(value:200,timescale:1),duration:.init(value:100,timescale:1),sourceStart:.init(value:200,timescale:1))
    let audio=Clip(assetID:master.id,duration:.init(value:600,timescale:1))
    let group=MulticamGroup(angleAssetIDs:[camera.id],masterAudioAssetID:master.id,cuts:[.init(time:.zero,angleID:camera.id)])
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Camera",kind:.video,clips:[first,second]),Track(name:"Master",kind:.audio,clips:[audio])],multicamGroups:[group]),assets:[camera,master])
    let correction=try driftFit(),proposal=try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:document)
    #expect(proposal.document.assets==document.assets)
    #expect(proposal.document.sequence.tracks[1]==document.sequence.tracks[1])
    #expect(proposal.document.sequence.multicamGroups==document.sequence.multicamGroups)
    let adjusted=proposal.document.sequence.tracks[0].clips
    #expect(adjusted.map(\.id)==[first.id,second.id])
    #expect(adjusted[0].preservesPitch==false)
    #expect(adjusted[1].sourceStart==second.sourceStart)
    #expect(abs(adjusted[1].start.seconds-(correction.sourceOrigin+200/correction.speed))<1.0/48000)
    #expect(abs(adjusted[0].volume.points[0].time.seconds-50/correction.speed)<0.00001)
    let editor=ProjectEditor(document:document);try editor.perform(.replace(proposal.document));editor.undo();#expect(editor.document==document)
    #expect(try ProjectDocument.decode(proposal.document.encoded())==proposal.document)
    var reused=document;var duplicate=first;duplicate.id=UUID();reused.sequence.tracks.append(Track(name:"Unrelated reuse",kind:.video,clips:[duplicate]))
    #expect(throws:DriftCorrectionError.unsupportedContext){try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:reused)}
    var slipped=document;slipped.sequence.tracks[0].clips[1].start = .init(value:6001,timescale:30)
    #expect(throws:DriftCorrectionError.unsupportedContext){try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:slipped)}
    var shortSource=document;shortSource.assets[0].duration = .init(value:350,timescale:1)
    #expect(throws:DriftCorrectionError.invalidRange){try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:shortSource)}
    let negative=try driftFit(1.001,-2)
    #expect(throws:DriftCorrectionError.negativePreroll){try MulticamDriftCorrection.applying(negative,to:camera.id,referenceID:master.id,in:document)}
    var locked=document;locked.sequence.tracks[0].isLocked=true
    #expect(throws:DocumentError.lockedTrack){try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:locked)}
}
