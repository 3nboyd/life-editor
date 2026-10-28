import Foundation
import Testing
@testable import LifeCore

@MainActor @Test func titleBackgroundValidationMigrationAndTypographyIndependence()throws {
    let background=TitleBackgroundStyle(shape:.speechBubble,padding:19,cornerRadius:0.4,borderWidth:3,borderColor:.white,shadowColor:.black,shadowBlur:9,shadowOffsetX:4,shadowOffsetY:7)
    let style=TitleStyle(fontName:"Missing-Font-For-Preservation",background:.init(red:0.2,green:0.3,blue:0.4),cornerRadius:0.08,backgroundStyle:background)
    let clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"A line\nAnother line",fontSize:31,style:style,animation:.init(kind:.typewriter)))
    let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
    try document.validate();#expect(try ProjectDocument.decode(document.encoded())==document)
    for family in TextFamily.allCases {
        let changed=try TextPresets.applying(family,to:clip)
        #expect(changed.title?.style?.backgroundStyle==background)
        #expect(changed.title?.style?.background==style.background)
        #expect(changed.title?.style?.cornerRadius==style.cornerRadius)
        #expect(changed.title?.animation==clip.title?.animation)
    }
    let editor=ProjectEditor(document:document);var next=document;next.sequence.tracks[0].clips[0].title?.style?.backgroundStyle?.shape = .none
    try editor.perform(.replace(next));editor.undo();#expect(editor.document==document);editor.redo();#expect(editor.document==next)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".lifeedit");defer{try? FileManager.default.removeItem(at:root)}
    try ProjectPackage.write(next,to:root);#expect(try ProjectPackage.read(from:root)==next)
    #expect(next.sequence.tracks[0].clips[0].title?.style?.background==style.background)
    for key in [\TitleBackgroundStyle.padding,\.cornerRadius,\.borderWidth,\.shadowBlur,\.shadowOffsetX,\.shadowOffsetY] {
        for value in [Double.nan,Double.infinity,-Double.infinity,10000] {
            var invalid=document;invalid.sequence.tracks[0].clips[0].title?.style?.backgroundStyle?[keyPath:key]=value
            #expect(throws:(any Error).self){try invalid.validate()}
        }
    }
    var invalid=document;invalid.sequence.tracks[0].clips[0].title?.style?.backgroundStyle?.borderColor.red = .nan
    #expect(throws:(any Error).self){try invalid.validate()}
    let legacyClip=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Legacy",style:.init(fontName:"Unavailable Font",background:.black,cornerRadius:0.1)))
    var legacy=ProjectDocument(sequence:.init(tracks:[.init(name:"Legacy",kind:.title,clips:[legacyClip])]))
    for version in 1...5 {
        legacy.version=version;let bytes=try JSONEncoder().encode(legacy),migrated=try ProjectDocument.decode(bytes)
        var expected=legacy;expected.version=ProjectDocument.currentVersion;#expect(migrated==expected)
        #expect(migrated.sequence.tracks[0].clips[0].title?.style?.backgroundStyle==nil)
    }
    #expect(throws:DocumentError.unsupportedVersion(10)){try ProjectDocument.decode(Data(#"{"version":10,"opaque":true}"#.utf8))}
}
