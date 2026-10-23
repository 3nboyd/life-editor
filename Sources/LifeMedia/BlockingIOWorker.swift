import Foundation

/// Blocking media calls run on a dispatch worker, never on Swift's cooperative executor.
/// Callers await each operation, so a stream has at most one queued operation.
/// Apple: https://developer.apple.com/videos/play/wwdc2022/110350/
final class BlockingIOWorker:Sendable {
    private let queue:DispatchQueue
    init(label:String){queue=DispatchQueue(label:label,qos:.userInitiated)}
    func run<Value:Sendable>(_ operation:@escaping @Sendable ()throws->Value)async throws->Value{
        try Task.checkCancellation()
        let value:Value=try await withCheckedThrowingContinuation{continuation in
            queue.async{
                do{continuation.resume(returning:try operation())}
                catch{continuation.resume(throwing:error)}
            }
        }
        try Task.checkCancellation();return value
    }
}

/// Four exports may progress concurrently; admission suspends tasks without blocking a thread.
actor ExportAdmission {
    static let shared=ExportAdmission()
    private var active=0
    private var queue:[UUID]=[]
    private var waiting:[UUID:CheckedContinuation<Void,any Error>]=[:]
    func acquire()async throws{
        try Task.checkCancellation()
        if active<4{active+=1;return}
        guard waiting.count<32 else{throw MediaError.exportUnavailable};let id=UUID()
        try await withTaskCancellationHandler{try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,any Error>) in queue.append(id);waiting[id]=continuation}}onCancel:{Task{await self.cancel(id)}}
    }
    private func cancel(_ id:UUID){queue.removeAll{$0==id};waiting.removeValue(forKey:id)?.resume(throwing:CancellationError())}
    func release(){while !queue.isEmpty{let id=queue.removeFirst();if let continuation=waiting.removeValue(forKey:id){continuation.resume();return}};active-=1}
}
