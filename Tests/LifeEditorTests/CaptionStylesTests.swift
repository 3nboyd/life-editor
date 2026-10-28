import Foundation
import Testing
import LifeCore
import LifeMedia
@testable import LifeEditor

@MainActor @Test func captionPresetsPreserveCueContentTimingAndUndo()async throws {
    let cues=try SRT.parse("1\n00:00:00,250 --> 00:00:01,250\nAt rehearsal\n\n2\n00:00:01,500 --> 00:00:02,750\nOne more take\n")
    let clips=cues.map(\.clip),store=EditorStore()
    let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Captions",kind:.caption,clips:clips)]))
    store.replace(document);store.selection=clips[0].id
    var thumbnails=Set<Data>()
    for preset in CaptionPreset.allCases {
        store.applyCaptionPreset(preset)
        let changed=store.document,title=try #require(store.selectedClip?.title)
        #expect(title.text==clips[0].title?.text)
        #expect(store.selectedClip?.start==clips[0].start && store.selectedClip?.duration==clips[0].duration)
        try changed.validate()
        #expect(try ProjectDocument.decode(changed.encoded())==changed)
        let image=try await CaptionThumbnails.shared.image(for:preset)
        thumbnails.insert(Data(try #require(image.dataProvider?.data) as Data))
        store.matchCaptionTrackStyle();let matched=store.document
        #expect(matched.sequence.tracks[0].clips[1].title?.style==title.style)
        let exported=matched.sequence.tracks[0].clips.map{CaptionCue(start:$0.start,duration:$0.duration,text:$0.title!.text)}
        #expect(try SRT.encode(exported)==SRT.encode(cues))
        store.undo();#expect(store.document==changed)
        store.undo();#expect(store.document==document)
        store.redo();#expect(store.document==changed)
        store.undo()
    }
    #expect(thumbnails.count==4)
    for height in [1,16384] {
        for preset in CaptionPreset.allCases {
            let clip=try preset.applying(to:clips[0],canvasHeight:height)
            try ProjectDocument(sequence:.init(tracks:[.init(name:"Caption",kind:.caption,clips:[clip])])).validate()
        }
    }
}

@MainActor @Test func captionStylesRespectLocksAndKeepAnimationEffectsAndEnvelopes()throws {
    var clip=CaptionCue(start:.zero,duration:.init(value:2,timescale:1),text:"Words").clip
    clip.title?.animation = .init(kind:.slide)
    clip.effects=[NativeEffectRegistry.make("life.adjust.saturation")]
    clip.opacity = .init(points:[.init(time:.zero,value:0.5)])
    let styled=try CaptionPreset.pill.applying(to:clip,canvasHeight:1080)
    #expect(styled.title?.animation==clip.title?.animation)
    #expect(styled.effects==clip.effects && styled.opacity==clip.opacity)
    let store=EditorStore(),locked=ProjectDocument(sequence:.init(tracks:[.init(name:"Captions",kind:.caption,clips:[clip],isLocked:true)]))
    store.replace(locked);store.selection=clip.id
    store.applyCaptionPreset(.box);store.matchCaptionTrackStyle();#expect(store.document==locked)
}
