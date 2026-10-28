import Foundation
import Testing
@testable import LifeCore

@MainActor struct TrackSoloTests {
    @Test func soloIsAdditiveMuteWinsAndVideoRemainsVisible() throws {
        let clip=Clip(duration:.init(value:1,timescale:1))
        var sequence=Sequence(tracks:[Track(name:"Camera",kind:.video,clips:[clip]),Track(name:"Music",kind:.audio,clips:[Clip(duration:clip.duration)]),Track(name:"Voice",kind:.audio,clips:[Clip(duration:clip.duration)])])
        #expect(sequence.tracks.allSatisfy{sequence.isAudioAudible(on:$0)})
        sequence.tracks[1].isSoloed=true
        #expect(sequence.tracks.map{sequence.isAudioAudible(on:$0)} == [false,true,false])
        let visible=TimelineEvaluator.evaluate(.init(document:.init(sequence:sequence)),at:.zero)
        #expect(visible.count==3 && visible[0].opacity==1 && visible[0].volume==0)
        sequence.tracks[0].isSoloed=true;sequence.tracks[1].isMuted=true
        #expect(sequence.tracks.map{sequence.isAudioAudible(on:$0)} == [true,false,false])
        sequence.tracks[0].isHidden=true
        #expect(sequence.isAudioAudible(on:sequence.tracks[0]))
        let hidden=TimelineEvaluator.evaluate(.init(document:.init(sequence:sequence)),at:.zero)
        #expect(hidden[0].opacity==0 && hidden[0].volume==1)
        sequence.tracks[0].isSoloed=false
        #expect(sequence.tracks.allSatisfy{!sequence.isAudioAudible(on:$0)})
    }
    @Test func soloRoundTripsMigratesMissingStateAndRejectsInvalidKinds() throws {
        let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Solo",kind:.audio,isSoloed:true)]))
        #expect(try ProjectDocument.decode(document.encoded())==document)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".lifeedit")
        defer{try? FileManager.default.removeItem(at:root)}
        try ProjectPackage.write(document,to:root);#expect(try ProjectPackage.read(from:root)==document)
        var json=try #require(JSONSerialization.jsonObject(with:document.encoded()) as? [String:Any])
        json["version"]=7
        var sequence=try #require(json["sequence"] as? [String:Any]),tracks=try #require(sequence["tracks"] as? [[String:Any]])
        tracks[0].removeValue(forKey:"isSoloed");sequence["tracks"]=tracks;json["sequence"]=sequence
        let migrated=try ProjectDocument.decode(JSONSerialization.data(withJSONObject:json))
        #expect(!migrated.sequence.tracks[0].isSoloed && migrated.version==8)
        for kind in [TrackKind.image,.title,.caption,.shape,.drawing,.adjustment] {
            let invalid=ProjectDocument(sequence:.init(tracks:[.init(name:"Invalid",kind:kind,isSoloed:true)]))
            #expect(throws:DocumentError.invalidTiming){try invalid.validate()}
        }
    }
}
