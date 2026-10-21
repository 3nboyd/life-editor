import Testing
@testable import LifeAnalysis

@Test func silentAnalysisHasNoInventedTempoOrSync() {
    let silence=AudioFingerprint(values:Array(repeating:0,count:1000),samplesPerSecond:50)
    #expect(AudioAnalyzer.beats(silence)==nil)
    #expect(AudioAnalyzer.synchronize(reference:silence,other:silence)==nil)
}
@Test func knownTempoAndOffsetRemainMeasurable() throws {
    var beats=[Float](repeating:0,count:2000)
    for i in stride(from:7,to:beats.count,by:25){beats[i]=1}
    let estimate=try #require(AudioAnalyzer.beats(.init(values:beats,samplesPerSecond:50)))
    #expect(abs(estimate.bpm-120)<0.01)
    #expect(abs(estimate.offset-0.14)<0.01)
    #expect(estimate.confidence>0.9)
}
@Test func waveformSyncFindsNonPeriodicKnownOffset() throws {
    var reference=[Float](repeating:0,count:2000)
    for (i,value) in [(100,Float(0.8)),(172,0.5),(391,1),(811,0.7),(1409,0.9)]{reference[i]=value}
    let delayed=Array(repeating:Float(0),count:37)+reference.dropLast(37)
    let estimate=try #require(AudioAnalyzer.synchronize(reference:.init(values:reference,samplesPerSecond:50),other:.init(values:delayed,samplesPerSecond:50),maxOffset:2))
    #expect(abs(estimate.offset+0.74)<0.001)
    #expect(estimate.confidence>0.99)
}

@Test func repetitiveSyncIsFlaggedAmbiguous() throws {
    var values=[Float](repeating:0,count:2000)
    for index in stride(from:0,to:values.count,by:25){values[index]=1}
    let repeated=AudioFingerprint(values:values,samplesPerSecond:50)
    let estimate=try #require(AudioAnalyzer.synchronize(reference:repeated,other:repeated,maxOffset:2))
    #expect(estimate.confidence<0.6)
}
