import Foundation
@preconcurrency import AVFoundation

/// Reader samples are transferred to one consumer without mutation.
struct ReaderSample:@unchecked Sendable{let buffer:CMSampleBuffer?}
/// One native pull at a time, with cancellation independent of the blocked read.
final class BlockingAssetReader:@unchecked Sendable {
    private let reader:AVAssetReader
    private let output:AVAssetReaderOutput
    private let worker:BlockingIOWorker
    private let cancellationQueue:DispatchQueue
    private let lock=NSLock()
    private var cancelled=false
    init(reader:AVAssetReader,output:AVAssetReaderOutput,label:String){
        self.reader=reader;self.output=output
        worker=BlockingIOWorker(label:label)
        cancellationQueue=DispatchQueue(label:label+".cancel",qos:.userInitiated)
    }
    private func checkCancellation()throws{if lock.withLock({cancelled}){throw CancellationError()}}
    func start()async throws{
        try await worker.run{[self] in
            try checkCancellation()
            guard reader.startReading() else{throw reader.error ?? MediaError.exportUnavailable}
        }
    }
    func next()async throws->ReaderSample{
        try await worker.run{[self] in try checkCancellation();return ReaderSample(buffer:output.copyNextSampleBuffer())}
    }
    func requireCompleted()async throws{
        try await worker.run{[self] in
            try checkCancellation()
            guard reader.status == .completed else{throw reader.error ?? MediaError.exportUnavailable}
        }
    }
    func cancel(){
        lock.withLock{cancelled=true}
        // Rechecking on each cancellation pass also covers startup races.
        cancellationQueue.async{[self] in if reader.status == .reading{reader.cancelReading()}}
    }
    func cancelAndWait()async{
        cancel()
        await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in cancellationQueue.async{continuation.resume()}}
    }
}
