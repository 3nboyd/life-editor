import Foundation
import Testing
@testable import LifeCore

@MainActor @Test func titleTypographyPersistenceMigrationValidationAndPresetPreservation()throws {
    let layout=TitleTypography(alignment:.right,letterSpacing:3,lineSpacing:17)
    let clip=Clip(duration:.init(value:2,timescale:1),title:.init(text:"A long line\nShort",style:.init(fontName:"Unavailable-Font",typography:layout)))
    let document=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
    try document.validate();#expect(try ProjectDocument.decode(document.encoded())==document)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".lifeedit");defer{try? FileManager.default.removeItem(at:root)}
    try ProjectPackage.write(document,to:root);#expect(try ProjectPackage.read(from:root)==document)
    for family in TextFamily.allCases{#expect(try TextPresets.applying(family,to:clip).title?.style?.typography==layout)}
    var legacy=document;legacy.version=6;legacy.sequence.tracks[0].clips[0].title?.style?.typography=nil
    let migrated=try ProjectDocument.decode(JSONEncoder().encode(legacy));#expect(migrated.version==ProjectDocument.currentVersion);#expect(migrated.sequence.tracks[0].clips[0].title?.style?.typography==nil)
    for key in [\TitleTypography.letterSpacing,\.lineSpacing] {
        for value in [Double.nan,.infinity,-.infinity,-21,513]{
            var invalid=document;invalid.sequence.tracks[0].clips[0].title?.style?.typography?[keyPath:key]=value
            #expect(throws:(any Error).self){try invalid.validate()}
        }
    }
    #expect(TitleTypography(letterSpacing:-20,lineSpacing:512).isValid)
    #expect(throws:DocumentError.unsupportedVersion(10)){try ProjectDocument.decode(Data(#"{"version":10}"#.utf8))}
}
