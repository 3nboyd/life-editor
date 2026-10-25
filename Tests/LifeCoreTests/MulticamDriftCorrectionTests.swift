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
    let markers=[Marker(time:.init(value:50,timescale:1),name:"Source note",clipID:first.id),Marker(time:.init(value:40,timescale:1),name:"Timeline note")]
    let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Camera",kind:.video,clips:[first,second]),Track(name:"Master",kind:.audio,clips:[audio])],markers:markers,multicamGroups:[group]),assets:[camera,master])
    let correction=try driftFit(),proposal=try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:document)
    #expect(proposal.document.assets==document.assets)
    #expect(proposal.document.sequence.markers==markers)
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
    var boundedReference=document;boundedReference.assets[1].duration = .init(value:410,timescale:1);boundedReference.sequence.tracks[1].clips[0].duration = .init(value:410,timescale:1)
    let delayed=try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:boundedReference,offsetAdjustmentSeconds:30)
    #expect(abs(delayed.document.sequence.tracks[0].clips[0].start.seconds-proposal.document.sequence.tracks[0].clips[0].start.seconds-30)<1.0/48000)
    #expect(correction.late.referenceSeconds<410 && correction.late.referenceSeconds+30>410)
    #expect(delayed.document.sequence.tracks[0].clips[0].speed==correction.speed)
    var locked=document;locked.sequence.tracks[0].isLocked=true
    #expect(throws:DocumentError.lockedTrack){try MulticamDriftCorrection.applying(correction,to:camera.id,referenceID:master.id,in:locked)}
}

@MainActor @Test func driftCorrectionSharesExactFragmentGridForAdjacentAndGappedPrimeRates()throws {
    for rate in [1.0001,1.000237] {
        let source=MediaAsset(url:URL(fileURLWithPath:"/camera.mov"),kind:.video,duration:.init(value:600,timescale:1))
        let master=MediaAsset(url:URL(fileURLWithPath:"/master.wav"),kind:.audio,duration:.init(value:600,timescale:1))
        let clips=[0,100,250].map{Clip(assetID:source.id,start:.init(value:Int64($0),timescale:1),duration:.init(value:100,timescale:1),sourceStart:.init(value:Int64($0),timescale:1))}
        let group=MulticamGroup(angleAssetIDs:[source.id],masterAudioAssetID:master.id,cuts:[.init(time:.zero,angleID:source.id)])
        let document=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Camera",kind:.video,clips:clips),Track(name:"Master",kind:.audio,clips:[Clip(assetID:master.id,duration:master.duration)])],multicamGroups:[group]),assets:[source,master])
        func anchor(_ source:Double)->DriftAnchor{.init(sourceSeconds:source,referenceSeconds:0.1234567+source/rate,confidence:0.9,uncertaintySeconds:0.023)}
        let correction=try AffineDriftCorrection.fit(early:anchor(20),middle:anchor(200),late:anchor(400))
        let proposal=try MulticamDriftCorrection.applying(correction,to:source.id,referenceID:master.id,in:document)
        let result=proposal.document.sequence.tracks[0].clips
        #expect(result[0].end==result[1].start)
        #expect(abs((result[2].start-result[1].end).seconds-50/rate)<0.000000001)
        let starts=try DriftTimingGrid.translationStarts(for:result,deltaSeconds:0.13791,sampleRate:48000)
        #expect(try starts[result[0].id]!.checkedAdding(result[0].duration)==starts[result[1].id]!)
        #expect(try starts[result[2].id]!.checkedSubtracting(starts[result[1].id]!)==result[2].start-result[1].start)
        #expect(result.map(\.sourceStart)==clips.map(\.sourceStart))
    }
}
