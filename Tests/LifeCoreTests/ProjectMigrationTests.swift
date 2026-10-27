import Testing
import Foundation
@testable import LifeCore

// A literal schema-1 document, independent of the current encoder and initializer defaults.
private let legacyProject=Data(#"""
{
 "version":1,"id":"00000000-0000-0000-0000-000000000001","name":"Rehearsal 🎵",
 "assets":[
  {"id":"00000000-0000-0000-0000-000000000006","url":"file:///tmp/camera.mov","kind":"video","duration":{"value":10,"timescale":1}},
  {"id":"00000000-0000-0000-0000-000000000007","url":"file:///tmp/master.wav","kind":"audio","duration":{"value":10,"timescale":1}}
 ],
 "sequence":{
  "settings":{"width":1920,"height":1080,"frameRate":{"numerator":30000,"denominator":1001},"audioSampleRate":48000},
  "tracks":[
   {"id":"00000000-0000-0000-0000-000000000002","name":"Camera","kind":"video","isMuted":false,"isHidden":false,"isLocked":false,"clips":[
    {"id":"00000000-0000-0000-0000-000000000004","name":"Take 1","assetID":"00000000-0000-0000-0000-000000000006","start":{"value":0,"timescale":1},"duration":{"value":60060,"timescale":30000},"sourceStart":{"value":3003,"timescale":30000},"speed":1,"preservesPitch":true,"linkID":"00000000-0000-0000-0000-00000000000b",
     "volume":{"baseValue":0.5,"evaluationOffset":{"value":0,"timescale":1},"points":[{"id":"00000000-0000-0000-0000-000000000009","time":{"value":1,"timescale":48000},"value":0,"interpolation":"linear"},{"id":"00000000-0000-0000-0000-00000000000a","time":{"value":1,"timescale":1},"value":1,"interpolation":"hold"}]},"opacity":{"baseValue":1,"points":[],"evaluationOffset":{"value":0,"timescale":1}}}
   ]},
   {"id":"00000000-0000-0000-0000-000000000003","name":"Master","kind":"audio","isMuted":false,"isHidden":false,"isLocked":false,"clips":[
    {"id":"00000000-0000-0000-0000-000000000005","name":"Stereo","assetID":"00000000-0000-0000-0000-000000000007","start":{"value":1,"timescale":48000},"duration":{"value":2,"timescale":1},"sourceStart":{"value":4,"timescale":48000},"speed":1,"preservesPitch":true,"linkID":"00000000-0000-0000-0000-00000000000b","volume":{"baseValue":1,"points":[],"evaluationOffset":{"value":0,"timescale":1}},"opacity":{"baseValue":1,"points":[],"evaluationOffset":{"value":0,"timescale":1}}}
   ]}
  ],
  "markers":[{"id":"00000000-0000-0000-0000-000000000008","time":{"value":1,"timescale":1},"duration":{"value":1,"timescale":2},"name":"Chorus","note":"Keep the room tone\nSecond line","clipID":"00000000-0000-0000-0000-000000000004"}],
  "multicamGroups":[]
 }
}
"""#.utf8)

@Test func migrationPreservesLiteralLegacyMediaTimingAnnotationsAndAutomation()throws {
    let legacy=try JSONDecoder().decode(ProjectDocument.self,from:legacyProject)
    #expect(legacy.version==1)
    var expected=legacy;expected.version=ProjectDocument.currentVersion
    let migrated=try ProjectDocument.decode(legacyProject)
    #expect(migrated==expected);#expect(ProjectDocument().version==6)
    #expect(migrated.sequence.settings.frameRate==FrameRate(numerator:30000,denominator:1001))
    #expect(migrated.sequence.tracks[1].clips[0].start==RationalTime(value:1,timescale:48000))
    #expect(migrated.sequence.tracks[0].clips[0].volume.points[0].time==RationalTime(value:1,timescale:48000))
    #expect(migrated.sequence.markers[0].note=="Keep the room tone\nSecond line")
    #expect(migrated.sequence.tracks[0].clips[0].freezeFrame==nil)
    #expect(try ProjectDocument.decode(migrated.encoded())==migrated)
    #expect(throws:DocumentError.unsupportedVersion(1)){try legacy.encoded()}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".lifeedit");defer{try? FileManager.default.removeItem(at:directory)}
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try legacyProject.write(to:directory.appendingPathComponent(ProjectPackage.projectFilename))
    let loaded=try ProjectPackage.read(from:directory);#expect(loaded==migrated)
    try ProjectPackage.write(loaded,to:directory);#expect(try ProjectPackage.read(from:directory)==migrated)
    #expect(try ProjectMigration.headerVersion(in:Data(contentsOf:directory.appendingPathComponent(ProjectPackage.projectFilename)))==ProjectDocument.currentVersion)
}
@Test func migrationRejectsUnknownFutureStructureBeforeModelDecodeAndNeverOverwrites()throws {
    let data=Data(#"{"version":999,"sequence":"future encoding","assets":{"unrecognized":true},"opaque":"preserve me"}"#.utf8)
    #expect(throws:DocumentError.unsupportedVersion(999)){try ProjectDocument.decode(data)}
    #expect(throws:DocumentError.unsupportedVersion(0)){try ProjectDocument.decode(Data(#"{"version":0}"#.utf8))}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".lifeedit");defer{try? FileManager.default.removeItem(at:directory)}
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let file=directory.appendingPathComponent(ProjectPackage.projectFilename);try data.write(to:file)
    #expect(throws:DocumentError.unsupportedVersion(999)){try ProjectPackage.read(from:directory)}
    #expect(throws:DocumentError.unsupportedVersion(999)){try ProjectPackage.write(ProjectDocument(),to:directory)}
    #expect(try Data(contentsOf:file)==data)
    var future=ProjectDocument();future.version=999
    #expect(throws:DocumentError.unsupportedVersion(999)){try future.encoded()}
}
@Test func recoveryRotationPreservesFutureOpaqueCheckpointsAndMigratesLegacyRecovery()throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:directory)}
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let future=directory.appendingPathComponent("checkpoint-00000000000000000000-future.json"),data=Data(#"{"version":999,"unknown":{"keep":"exact"}}"#.utf8)
    try data.write(to:future);try legacyProject.write(to:directory.appendingPathComponent("checkpoint-00000000000000000001-legacy.json"))
    #expect(try ProjectPackage.recoverLatest(in:directory)==ProjectDocument.decode(legacyProject))
    let current=ProjectDocument(name:"Latest")
    try ProjectPackage.checkpoint(current,in:directory,keeping:1)
    try ProjectPackage.checkpoint(current,in:directory,keeping:1)
    #expect(try Data(contentsOf:future)==data)
    #expect(try FileManager.default.contentsOfDirectory(atPath:directory.path).count==2)
    #expect(try ProjectPackage.recoverLatest(in:directory)==current)
}

private let schemaTwoAdjustment=Data(#"""
{
 "version":2,"id":"00000000-0000-0000-0000-00000000f101","name":"Adjustment study","assets":[],
 "sequence":{
  "settings":{"width":1280,"height":720,"frameRate":{"numerator":30,"denominator":1},"audioSampleRate":48000},
  "tracks":[{"id":"00000000-0000-0000-0000-00000000f102","name":"Adjust","kind":"adjustment","isMuted":false,"isHidden":false,"isLocked":false,"clips":[
   {"id":"00000000-0000-0000-0000-00000000f103","name":"Film fade","start":{"value":1,"timescale":1},"duration":{"value":2,"timescale":1},"sourceStart":{"value":1,"timescale":2},"speed":1,"preservesPitch":true,"audioEnabled":false,
    "effects":[{"id":"00000000-0000-0000-0000-00000000f104","stableID":"life.filter.VHS","parameters":{"grain":0.3},"strength":0.6,"seed":99,"isEnabled":true}],
    "volume":{"baseValue":1,"points":[],"evaluationOffset":{"value":0,"timescale":1}},
    "opacity":{"baseValue":0.75,"evaluationOffset":{"value":1,"timescale":4},"points":[{"id":"00000000-0000-0000-0000-00000000f105","time":{"value":0,"timescale":1},"value":0,"interpolation":"linear"},{"id":"00000000-0000-0000-0000-00000000f106","time":{"value":1,"timescale":1},"value":1,"interpolation":"eased"}]}}
  ]}],"markers":[],"multicamGroups":[]
 }
}
"""#.utf8)
@Test func migrationPreservesSchemaTwoAdjustmentEffectsOpacityAndAnimationClock()throws{
    let legacy=try JSONDecoder().decode(ProjectDocument.self,from:schemaTwoAdjustment);#expect(legacy.version==2)
    var expected=legacy;expected.version=ProjectDocument.currentVersion
    let migrated=try ProjectDocument.decode(schemaTwoAdjustment);#expect(migrated==expected);#expect(migrated.version==6)
    let clip=try #require(migrated.sequence.tracks.first?.clips.first)
    #expect(clip.effects?[0].seed==99 && clip.effects?[0].strength==0.6)
    #expect(clip.opacity.evaluationOffset==RationalTime(value:1,timescale:4));#expect(clip.sourceStart==RationalTime(value:1,timescale:2))
    try AdjustmentLayers.validate(in:migrated)
    #expect(try ProjectDocument.decode(migrated.encoded())==migrated)
    #expect(throws:DocumentError.unsupportedVersion(2)){try legacy.encoded()}
    #expect(throws:DocumentError.unsupportedVersion(7)){try ProjectDocument.decode(Data(#"{"version":7,"sequence":{"unknownNewLayout":true}}"#.utf8))}
}

@Test func migrationPreservesSchemaThreeLayerDecisionsWithoutRewritingEffects()throws{
    // Derive only the header from the literal legacy fixture, never from today's encoder.
    let data=Data(String(decoding:schemaTwoAdjustment,as:UTF8.self).replacingOccurrences(of:"\"version\":2",with:"\"version\":3").utf8)
    let legacy=try JSONDecoder().decode(ProjectDocument.self,from:data)
    #expect(legacy.version==3)
    var expected=legacy;expected.version=ProjectDocument.currentVersion
    let migrated=try ProjectDocument.decode(data)
    #expect(migrated==expected)
    #expect(try ProjectDocument.decode(migrated.encoded())==expected)
    #expect(throws:DocumentError.unsupportedVersion(3)){try legacy.encoded()}
}

@Test func migrationPreservesSchemaFourTonalControls()throws{
    var legacy=try JSONDecoder().decode(ProjectDocument.self,from:schemaTwoAdjustment)
    legacy.version=4
    legacy.sequence.tracks[0].clips[0].effects = [EffectInstance(stableID:"life.adjust.brilliance",parameters:["value":0.65],strength:0.8,seed:17)]
    let data=try JSONEncoder().encode(legacy)
    var expected=legacy;expected.version=ProjectDocument.currentVersion
    let migrated=try ProjectDocument.decode(data)
    #expect(migrated==expected)
    #expect(try ProjectDocument.decode(migrated.encoded())==expected)
    #expect(throws:DocumentError.unsupportedVersion(4)){try legacy.encoded()}
}
