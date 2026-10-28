import Foundation
import Testing
import LifeCore
import LifeMedia
@testable import LifeEditor

@MainActor @Test func titleLayoutRecipesPreserveContentAndUndo()async throws {
    let store=EditorStore()
    let clip=Clip(start:.init(value:2,timescale:1),duration:.init(value:5,timescale:1),title:.init(text:"Keep these words",fontSize:25,style:.init(fontName:"Georgia",background:.black,backgroundStyle:.init(shape:.pill)),animation:.init(kind:.typewriter,duration:1)))
    let original=ProjectDocument(sequence:.init(settings:.init(width:1920,height:1080),tracks:[.init(name:"Title",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    for preset in TitleLayoutPreset.allCases {
        TitleLayoutPresetControls(store:store).apply(preset)
        let changed=try #require(store.selectedClip)
        #expect(changed.title?.text==clip.title?.text)
        #expect(changed.title?.animation==clip.title?.animation)
        #expect(changed.title?.style?.fontName=="Georgia")
        #expect(changed.title?.style?.backgroundStyle==clip.title?.style?.backgroundStyle)
        #expect(changed.start==clip.start && changed.duration==clip.duration)
        let encoded=try JSONEncoder().encode(store.document)
        #expect(try JSONDecoder().decode(ProjectDocument.self,from:encoded)==store.document)
        let thumbnail=try await TitleLayoutThumbnails.shared.image(for:preset)
        #expect(thumbnail.width==320 && thumbnail.height==180)
        store.undo();#expect(store.document==original)
        store.redo();#expect(store.selectedClip==changed)
        store.undo()
    }
    for preset in TitleLayoutPreset.allCases {
        let small=try preset.applying(to:clip,canvasHeight:1)
        #expect(small.title?.fontSize==1)
    }
    store.document.sequence.tracks[0].isLocked=true
    let locked=store.document
    TitleLayoutPresetControls(store:store).apply(.title)
    #expect(store.document==locked)
}
