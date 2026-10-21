import Foundation
import Testing
@testable import LifeCore
private func seconds(_ n: Int64) -> RationalTime { .init(value:n,timescale:1) }
@Test func portableCollectionTransfersAndProtectsOriginals() throws {
    let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at:root) }
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    let original=root.appendingPathComponent("original.wav"), bytes=Data([1,2,3,4])
    try bytes.write(to:original)
    let asset=MediaAsset(url:original,kind:.audio,duration:seconds(5)), package=root.appendingPathComponent("A.lifeedit")
    let doc=ProjectDocument(assets:[asset])
    try ProjectPackage.collect(doc,to:package)
    let moved=root.appendingPathComponent("Moved.lifeedit"); try fm.moveItem(at:package,to:moved)
    let loaded=try ProjectPackage.read(from:moved)
    #expect(try Data(contentsOf:loaded.assets[0].url) == bytes)
    #expect(try Data(contentsOf:original) == bytes)
    #expect(throws:PackageError.destinationExists) { try ProjectPackage.collect(doc,to:moved) }
    var broken=doc; broken.assets[0].url=root.appendingPathComponent("absent.wav")
    let failed=root.appendingPathComponent("Failed.lifeedit")
    #expect(throws:(any Error).self) { try ProjectPackage.collect(broken,to:failed) }
    #expect(!fm.fileExists(atPath:failed.path))
    #expect(try Data(contentsOf:original) == bytes)
    #expect(ProjectPackage.missingAssets(in:broken).count == 1)
    #expect(try ProjectPackage.relinking(broken,assetID:asset.id,to:original) == doc)
}
@Test func recoveryRotatesAndSkipsCorruptNewest() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    for i in 0..<7 { try ProjectPackage.checkpoint(ProjectDocument(name:"Version \(i)"),in:root,keeping:3) }
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).count == 3)
    #expect(try ProjectPackage.recoverLatest(in:root)?.name == "Version 6")
    try Data("bad".utf8).write(to:root.appendingPathComponent("checkpoint-99999999999999999999.json"))
    #expect(try ProjectPackage.recoverLatest(in:root)?.name == "Version 6")
}
@Test func srtUnicodeMultilineAndValidation() throws {
    let source="1\r\n00:00:01,001 --> 00:00:03,002\r\nMúsica 🎵\r\nSecond line\r\n"
    let cues=try SRT.parse(source)
    #expect(cues[0].text == "Música 🎵\nSecond line")
    let roundtrip=try SRT.parse(SRT.encode(cues))
    #expect(roundtrip[0].text == cues[0].text)
    #expect(roundtrip[0].start == cues[0].start)
    #expect(roundtrip[0].duration == cues[0].duration)
    #expect(throws:(any Error).self) { try SRT.parse("1\n00:70:00,000 --> 00:70:01,000\nBad") }
    #expect(throws:(any Error).self) { try SRT.parse("1\n00:00:03,000 --> 00:00:01,000\nBad") }
}
@MainActor @Test func expandedCommandsRestoreExactStateAndRejectCrossingRipple() throws {
    let first=Clip(duration:seconds(2)), second=Clip(start:seconds(4),duration:seconds(2))
    let track=Track(name:"Audio",kind:.audio,clips:[first,second])
    let doc=ProjectDocument(sequence:.init(tracks:[track])), editor=ProjectEditor(document:doc)
    try editor.perform(.rippleDelete(clipID:first.id))
    #expect(editor.document.sequence.tracks[0].clips[0].start == seconds(2))
    editor.undo(); #expect(editor.document == doc)
    try editor.perform(.duplicate(clipID:first.id,to:seconds(2)))
    #expect(editor.document.sequence.tracks[0].clips.count == 3)
    editor.undo(); #expect(editor.document == doc)
    try editor.perform(.renameTrack(trackID:track.id,name:"Master")); editor.undo(); #expect(editor.document == doc)
    try editor.perform(.removeTrack(trackID:track.id)); editor.undo(); #expect(editor.document == doc)
    var crossing=doc; crossing.sequence.tracks.append(Track(name:"Other",kind:.audio,clips:[Clip(start:seconds(1),duration:seconds(4))]))
    let other=ProjectEditor(document:crossing)
    #expect(throws:DocumentError.overlap) { try other.perform(.rippleDelete(clipID:first.id)) }
    #expect(other.document == crossing)
}
@Test func versionOneDecodesWithoutOptionalGridAndGridRoundtrips() throws {
    let original=ProjectDocument()
    let data=try original.encoded()
    #expect(try ProjectDocument.decode(data).sequence.musicalGrid == nil)
    var doc=original; doc.sequence.musicalGrid=MusicalGrid(bpm:97.5,offset:.init(value:1,timescale:48000),beatsPerBar:3,subdivision:2)
    #expect(try ProjectDocument.decode(doc.encoded()) == doc)
    doc.sequence.musicalGrid?.bpm=0
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
}
@Test func packageRejectsTraversalAndPreservesSpaceReferences() throws {
    let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at:root) }
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    let media=root.appendingPathComponent("a b.wav"); try Data([5]).write(to:media)
    let doc=ProjectDocument(assets:[MediaAsset(url:media,kind:.audio,duration:seconds(1))])
    try ProjectPackage.write(doc,to:root)
    #expect(try ProjectPackage.read(from:root).assets[0].url == media)
    var unsafe=doc; unsafe.assets[0].url=URL(string:"../outside.wav")!
    try unsafe.encoded().write(to:root.appendingPathComponent(ProjectPackage.projectFilename))
    #expect(throws:PackageError.unsafeReference) { try ProjectPackage.read(from:root) }
}
@Test func creativeFieldsRoundtripAndLegacyDecode() throws {
    let legacy=ProjectDocument(sequence:.init(tracks:[Track(name:"Titles",kind:.title,clips:[Clip(duration:seconds(3),title:TitleContent(text:"Hello"))])]))
    let old=try ProjectDocument.decode(legacy.encoded())
    #expect(old.sequence.tracks[0].clips[0].effects == nil)
    #expect(old.sequence.tracks[0].clips[0].visual == nil)
    #expect(old.sequence.tracks[0].clips[0].title?.style == nil)
    var doc=legacy
    doc.sequence.tracks[0].clips[0].effects=[NativeEffectRegistry.make("life.filter.VHS",strength:0.7,seed:43),EffectInstance(stableID:"thirdparty.missing",parameters:["preserved":2])]
    doc.sequence.tracks[0].clips[0].visual=VisualTransform(scaleX:1.2,rotationDegrees:12,cropTop:0.1)
    doc.sequence.tracks[0].clips[0].title?.style=TitleStyle(fontName:"Unavailable Font",color:RGBAColor(red:1,green:0.2,blue:0.4),background:.black,cornerRadius:0.3,outlineWidth:2)
    #expect(try ProjectDocument.decode(doc.encoded()) == doc)
    #expect(NativeEffectRegistry.definitions.count == 16)
    #expect(Set(NativeEffectRegistry.definitions.map(\.stableID)).count == 16)
    #expect(doc.sequence.tracks[0].clips[0].effects?[0].parameters["grain"] == 0.2)
}
@Test func malformedCreativeNumbersAreRejected() throws {
    let clip=Clip(duration:seconds(1),title:TitleContent(text:"Hi"))
    var doc=ProjectDocument(sequence:.init(tracks:[Track(name:"V",kind:.video,clips:[clip])]))
    doc.sequence.tracks[0].clips[0].effects=[EffectInstance(stableID:"life.filter.VHS",parameters:["grain":2])]
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
    doc.sequence.tracks[0].clips[0].effects=[EffectInstance(stableID:"missing",parameters:["bad":.infinity])]
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
    doc.sequence.tracks[0].clips[0].effects=nil
    doc.sequence.tracks[0].clips[0].visual=VisualTransform(cropLeft:0.6,cropRight:0.6)
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
    doc.sequence.tracks[0].clips[0].visual=nil
    doc.sequence.tracks[0].clips[0].title?.style=TitleStyle(color:RGBAColor(red:-1,green:1,blue:1))
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
}
@MainActor @Test func creativeSettingsUndoExactly() throws {
    let doc=ProjectDocument(sequence:.init(tracks:[Track(name:"Title",kind:.title,clips:[Clip(duration:seconds(2),title:TitleContent(text:"Title"))])]))
    let editor=ProjectEditor(document:doc)
    var next=doc; next.sequence.tracks[0].clips[0].effects=[NativeEffectRegistry.make("life.filter.LA")]
    next.sequence.tracks[0].clips[0].title?.style=TitleStyle(background:.black,outlineWidth:2)
    try editor.perform(.replace(next)); editor.undo(); #expect(editor.document == doc)
    editor.redo(); #expect(editor.document == next)
}
@Test func preparedIntermediateCollectsTransfersAndRelinkClearsIt() throws {
    let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at:root) }
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    let original=root.appendingPathComponent("original.webm"), prepared=root.appendingPathComponent("prepared.mov")
    try Data([1,2]).write(to:original); try Data([3,4]).write(to:prepared)
    try Data("{\"streams\":[]}".utf8).write(to:prepared.deletingPathExtension().appendingPathExtension("probe.json"))
    let asset=MediaAsset(url:original,kind:.video,duration:seconds(3),preparedURL:prepared), doc=ProjectDocument(assets:[asset])
    let package=root.appendingPathComponent("one.lifeedit"), moved=root.appendingPathComponent("two.lifeedit")
    try ProjectPackage.collect(doc,to:package); try fm.moveItem(at:package,to:moved)
    let result=try ProjectPackage.read(from:moved)
    #expect(try Data(contentsOf:result.assets[0].url) == Data([1,2]))
    #expect(try Data(contentsOf:#require(result.assets[0].preparedURL)) == Data([3,4]))
    #expect(result.assets[0].preparedURL?.lastPathComponent.contains("-prepared") == true)
    let collectedSidecar=try #require(result.assets[0].preparedURL).deletingPathExtension().appendingPathExtension("probe.json")
    #expect(try String(contentsOf:collectedSidecar,encoding:.utf8) == "{\"streams\":[]}")
    try ProjectPackage.write(result,to:moved)
    #expect(try ProjectPackage.read(from:moved) == result)
    let relinked=try ProjectPackage.relinking(result,assetID:asset.id,to:original)
    #expect(relinked.assets[0].preparedURL == nil)
    try fm.removeItem(at:prepared)
    #expect(ProjectPackage.missingAssets(in:doc).map(\.id) == [asset.id])
    let failed=root.appendingPathComponent("failed.lifeedit")
    #expect(throws:PackageError.missingAsset(asset.id)) { try ProjectPackage.collect(doc,to:failed) }
    #expect(!fm.fileExists(atPath:failed.path))
    #expect(try Data(contentsOf:original) == Data([1,2]))
}
@Test func versionOneAssetsWithoutPreparedURLRemainReadable() throws {
    let doc=ProjectDocument(assets:[MediaAsset(url:URL(fileURLWithPath:"/tmp/original.mov"),kind:.video,duration:seconds(1))])
    let encoded=try doc.encoded()
    #expect(!String(decoding:encoded,as:UTF8.self).contains("preparedURL"))
    #expect(try ProjectDocument.decode(encoded).assets[0].preparedURL == nil)
}
