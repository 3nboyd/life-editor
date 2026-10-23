@preconcurrency import AVFoundation
import Testing
import Foundation
@testable import LifeMedia
private final class BlockingProbe:@unchecked Sendable{
    let lock=NSLock();var active=0,maximum=0,beats=0,started=false,completed=false
    func enter(){lock.withLock{active+=1;maximum=max(maximum,active);started=true}}
    func leave(){lock.withLock{active-=1}}
    func beat(){lock.withLock{if active>0{beats+=1}}}
    func finish(){lock.withLock{completed=true}}
    var values:(maximum:Int,beats:Int,started:Bool,completed:Bool){lock.withLock{(maximum,beats,started,completed)}}
}
@Test func blockingIOWorkersOverlapWithoutOccupyingCooperativeExecutor()async throws{
    let probe=BlockingProbe()
    let heartbeat=Task.detached{for _ in 0..<12{try await Task.sleep(for:.milliseconds(5));probe.beat()}}
    try await withThrowingTaskGroup(of:Void.self){group in
        for index in 0..<16{group.addTask{let worker=BlockingIOWorker(label:"life.test.blocking.\(index)");try await worker.run{probe.enter();defer{probe.leave()};Thread.sleep(forTimeInterval:0.1)}}}
        try await group.waitForAll()
    }
    try await heartbeat.value
    #expect(probe.values.maximum>=2);#expect(probe.values.beats>=3)
}
@Test func blockingIOCancellationWaitsForNativeOperationToUnwind()async throws{
    let probe=BlockingProbe(),release=DispatchSemaphore(value:0),worker=BlockingIOWorker(label:"life.test.unwind")
    let job=Task{defer{probe.finish()};try await worker.run{probe.enter();defer{probe.leave()};release.wait()}}
    let deadline=ContinuousClock.now.advanced(by:.seconds(3))
    while !probe.values.started{try #require(ContinuousClock.now<deadline);try await Task.sleep(for:.milliseconds(2))}
    job.cancel();try await Task.sleep(for:.milliseconds(20));#expect(!probe.values.completed)
    release.signal()
    do{try await job.value;Issue.record("Cancelled blocking operation returned success")}catch is CancellationError{}catch{Issue.record("Unexpected cancellation \(error)")}
    #expect(probe.values.completed)
}

@MainActor @Test func blockingReaderCancellationHandlesBothStartupStates()async throws{
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".wav")
    defer{try? FileManager.default.removeItem(at:url)}
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4800)!;buffer.frameLength=4800
    for index in 0..<4800{buffer.floatChannelData![0][index]=0}
    do{let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)}
    let source=AVURLAsset(url:url),tracks=try await source.loadTracks(withMediaType:.audio)
    let track=try #require(tracks.first)
    for beforeStart in [true,false]{
        let reader=try AVAssetReader(asset:source),output=AVAssetReaderTrackOutput(track:track,outputSettings:nil)
        reader.add(output)
        let io=BlockingAssetReader(reader:reader,output:output,label:"org.lifeeditor.tests.reader")
        if !beforeStart{try await io.start()}
        io.cancel()
        await #expect(throws:CancellationError.self){
            if beforeStart{try await io.start()}else{_ = try await io.next()}
        }
        await io.cancelAndWait()
        #expect(reader.status == (beforeStart ? .unknown:.cancelled))
    }
}
