import Testing
import Foundation
import LifeCore
private func mt(_ n:Int64,_ scale:Int64=1)->RationalTime{.init(value:n,timescale:scale)}
private func markerFixture()->(ProjectDocument,UUID,UUID){
    let camera=MediaAsset(url:URL(fileURLWithPath:"/tmp/marker-camera.mov"),kind:.video,duration:mt(100))
    let audio=MediaAsset(url:URL(fileURLWithPath:"/tmp/marker-audio.wav"),kind:.audio,duration:mt(100))
    let first=Clip(assetID:camera.id,start:mt(10),duration:mt(2),sourceStart:mt(1))
    let reference=Clip(assetID:camera.id,start:mt(20),duration:mt(4),sourceStart:mt(3))
    let target=Clip(assetID:audio.id,duration:mt(10))
    let a=Marker(time:mt(5),duration:mt(1),name:"Clap",clipID:reference.id)
    let b=Marker(time:mt(8)+mt(1,48000),clipID:target.id)
    return (ProjectDocument(sequence:Sequence(tracks:[Track(name:"Camera",kind:.video,clips:[first,reference]),Track(name:"Master",kind:.audio,clips:[target])],markers:[a,b]),assets:[camera,audio]),a.id,b.id)
}
@Test func sourceMarkerAlignmentRetainsSamplePrecisionAndSelectedReferencePlacement()throws{
    let (document,a,b)=markerFixture()
    let alignment=try MarkerSynchronization.alignment(referenceMarkerID:a,targetMarkerID:b,in:document)
    #expect(alignment.offset == mt(5)-mt(1,48000))
    #expect(alignment.referenceAssetID==document.assets[0].id)
    #expect(alignment.targetAssetID==document.assets[1].id)
}
@Test func markerAlignmentRejectsTimelineSameSourceOutOfRangeAndRetimedMarkers()throws{
    let (original,a,b)=markerFixture()
    var document=original;document.sequence.markers[0].clipID=nil
    #expect(throws:MarkerSynchronizationError.self){try MarkerSynchronization.alignment(referenceMarkerID:a,targetMarkerID:b,in:document)}
    document=original;document.sequence.markers[1].clipID=document.sequence.tracks[0].clips[0].id
    #expect(throws:MarkerSynchronizationError.self){try MarkerSynchronization.alignment(referenceMarkerID:a,targetMarkerID:b,in:document)}
    document=original;document.sequence.markers[1].time=mt(100)
    #expect(throws:MarkerSynchronizationError.self){try MarkerSynchronization.alignment(referenceMarkerID:a,targetMarkerID:b,in:document)}
    document=original;document.sequence.tracks[0].clips[1].speed=2
    #expect(throws:MarkerSynchronizationError.self){try MarkerSynchronization.alignment(referenceMarkerID:a,targetMarkerID:b,in:document)}
}
