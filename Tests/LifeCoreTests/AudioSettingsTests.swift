import Foundation
import Testing
@testable import LifeCore
private func audioDocument(_ settings: AudioSettings? = nil) -> ProjectDocument {
    ProjectDocument(sequence:Sequence(tracks:[Track(name:"Audio",kind:.audio,clips:[Clip(duration:RationalTime(value:2,timescale:1),audio:settings)])]))
}
@Test func audioSettingsPreserveBackwardCompatibilityAndEveryChannelMode() throws {
    let legacy=audioDocument()
    #expect(!String(decoding:try legacy.encoded(),as:UTF8.self).contains("\"gainDB\""))
    #expect(try ProjectDocument.decode(legacy.encoded()).sequence.tracks[0].clips[0].audio == nil)
    for mode in AudioChannelMode.allCases {
        let doc=audioDocument(AudioSettings(gainDB:12,pan:-0.3,channels:mode,eqLowDB:2,eqMidDB:-3,eqHighDB:4,limiterEnabled:true,limiterCeilingDB:-2))
        #expect(try ProjectDocument.decode(doc.encoded()) == doc)
    }
}
@Test func audioSettingsRejectNonfiniteAndOutOfRangeParameters() throws {
    let bad:[AudioSettings]=[AudioSettings(gainDB:.infinity),AudioSettings(gainDB:25),AudioSettings(gainDB:-97),AudioSettings(pan:1.1),AudioSettings(eqLowDB:19),AudioSettings(eqMidDB:-19),AudioSettings(eqHighDB:.nan),AudioSettings(limiterCeilingDB:0.1),AudioSettings(limiterCeilingDB:-13)]
    for settings in bad {
        #expect(!settings.isValid)
        #expect(throws:DocumentError.invalidTiming) { try audioDocument(settings).validate() }
    }
    #expect(AudioSettings(gainDB:-96,pan:-1,eqLowDB:-18,eqMidDB:18,limiterCeilingDB:-12).isValid)
    #expect(AudioSettings(gainDB:24,pan:1,limiterCeilingDB:0).isValid)
    var doc=audioDocument(); doc.sequence.tracks[0].clips[0].volume.baseValue=AudioSettings.maximumLinearGain
    try doc.validate()
    doc.sequence.tracks[0].clips[0].volume.baseValue=AudioSettings.maximumLinearGain+0.1
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
}
@MainActor @Test func audioSettingsUndoKeepsTheSingleAutomationEnvelope() throws {
    var doc=audioDocument()
    doc.sequence.tracks[0].clips[0].volume=AutomationEnvelope(points:[AutomationPoint(time:.zero,value:0),AutomationPoint(time:RationalTime(value:2,timescale:1),value:1)])
    let editor=ProjectEditor(document:doc), envelope=doc.sequence.tracks[0].clips[0].volume
    var next=doc; next.sequence.tracks[0].clips[0].audio=AudioSettings(gainDB:3,pan:0.2,channels:.left,eqLowDB:2,limiterEnabled:true)
    try editor.perform(.replace(next))
    #expect(editor.document.sequence.tracks[0].clips[0].volume == envelope)
    editor.undo(); #expect(editor.document == doc)
    editor.redo(); #expect(editor.document == next)
}
@Test func rmsMeasurementDoesNotClaimLoudnessAndSilenceRemainsRepresentable() {
    let measurement=AudioMeasurement(peakDBFS:-3,rmsDBFS:-12,sampleCount:48000)
    #expect(measurement.loudnessLUFS == nil)
    let silent=AudioMeasurement(peakDBFS:-.infinity,rmsDBFS:-.infinity,sampleCount:48000)
    #expect(silent.peakDBFS == -.infinity)
    #expect(silent.loudnessLUFS == nil)
}

@Test func automationEffectiveGainAndOpacityAreBounded() throws {
    var doc=audioDocument()
    doc.sequence.tracks[0].clips[0].volume=AutomationEnvelope(baseValue:2,points:[AutomationPoint(time:.zero,value:AudioSettings.maximumLinearGain)])
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
    doc.sequence.tracks[0].clips[0].volume=AutomationEnvelope(baseValue:2,points:[AutomationPoint(time:.zero,value:AudioSettings.maximumLinearGain/2)])
    try doc.validate()
    doc.sequence.tracks[0].clips[0].opacity=AutomationEnvelope(baseValue:0.5,points:[AutomationPoint(time:.zero,value:2.1)])
    #expect(throws:DocumentError.invalidTiming) { try doc.validate() }
    doc.sequence.tracks[0].clips[0].opacity.points[0].value=2
    try doc.validate()
}
