import Foundation
import Testing
import LifeCore
@testable import LifeAnalysis

private func driftSignal(_ time:Double)->Float {
    // Deterministic, nonperiodic broad transients survive small clock-rate
    // differences while avoiding the ambiguous peaks of a metronome.
    let index=Int(time),phase=time-Double(index)
    var hash=UInt64(max(0,index)) &+ 0x9e3779b97f4a7c15
    hash=(hash ^ (hash >> 30)) &* 0xbf58476d1ce4e5b9
    hash=(hash ^ (hash >> 27)) &* 0x94d049bb133111eb
    hash ^= hash >> 31
    guard hash%3==0 else{return 0}
    let center=0.15+Double((hash >> 16)%700)/1000
    let height=0.2+Double((hash >> 32)%800)/1000
    return Float(height*exp(-pow((phase-center)/0.07,2)))
}
@Test func anchoredDriftAnalysisMeasuresBothSignsAndCoversLongSourceSearchSpan()throws {
    let rate=43.0,duration=4000.0,origin=3.0
    let reference=AudioFingerprint(values:(0..<Int(duration*rate)).map{driftSignal(Double($0)/rate)},samplesPerSecond:rate)
    for slope in [0.999,1.001] {
        let other=AudioFingerprint(values:(0..<Int((duration-origin)/slope*rate)).map{driftSignal(origin+slope*Double($0)/rate)},samplesPerSecond:rate)
        let fit=try #require(try AudioAnalyzer.drift(reference:reference,other:other,coarseOffset:origin))
        #expect(abs(fit.speed-1/slope)<0.0001)
        #expect(abs(fit.sourceOrigin-origin)<0.04)
        #expect(fit.confidence>=0.6)
        #expect(fit.late.sourceSeconds-fit.early.sourceSeconds>3800)
    }
}
@Test func anchoredDriftAnalysisRejectsSilencePeriodicShortAndNonlinearRecordings()throws {
    let rate=43.0
    let silent=AudioFingerprint(values:Array(repeating:0,count:10000),samplesPerSecond:rate)
    #expect(try AudioAnalyzer.drift(reference:silent,other:silent,coarseOffset:0)==nil)
    let periodic=AudioFingerprint(values:(0..<20000).map{Float($0%43==0 ? 1:0)},samplesPerSecond:rate)
    #expect(try AudioAnalyzer.drift(reference:periodic,other:periodic,coarseOffset:0)==nil)
    let duration=800.0,origin=3.0
    let reference=AudioFingerprint(values:(0..<Int(duration*rate)).map{driftSignal(Double($0)/rate)},samplesPerSecond:rate)
    let warped=AudioFingerprint(values:(0..<Int((duration-origin)*rate)).map{index in let t=Double(index)/rate;return driftSignal(origin+t+0.25*sin(.pi*t/duration))},samplesPerSecond:rate)
    do{#expect(try AudioAnalyzer.drift(reference:reference,other:warped,coarseOffset:origin)==nil)}catch DriftCorrectionError.nonlinear {}catch{throw error}
    let short=AudioFingerprint(values:(0..<1000).map{driftSignal(Double($0)/rate)},samplesPerSecond:rate)
    #expect(try AudioAnalyzer.drift(reference:short,other:short,coarseOffset:0)==nil)
}

@Test func anchoredDriftAnalysisBoundsDerivedDurationAndHonorsCancellation()async throws {
    let tiny=AudioFingerprint(values:[1],samplesPerSecond:1e-300)
    #expect(try AudioAnalyzer.drift(reference:tiny,other:tiny,coarseOffset:0)==nil)
    let oversized=AudioFingerprint(values:[1,2],samplesPerSecond:0.00001)
    #expect(try AudioAnalyzer.drift(reference:oversized,other:oversized,coarseOffset:0)==nil)
    let input=AudioFingerprint(values:[1,2],samplesPerSecond:43)
    let task=Task{try AudioAnalyzer.drift(reference:input,other:input,coarseOffset:0)}
    task.cancel()
    do{_ = try await task.value;Issue.record("Cancelled analysis succeeded")}catch is CancellationError{}catch{throw error}
}
