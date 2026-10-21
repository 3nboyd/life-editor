import Testing
import Foundation
import LifeCore
@testable import LifeEditor

private final class CheckpointGate:@unchecked Sendable {
    let started=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var active=0,maximum=0
    func waitUntilStarted(){started.wait()}
    func enter(){lock.lock();active+=1;maximum=max(maximum,active);lock.unlock()}
    func leave(){lock.lock();active-=1;lock.unlock()}
    var maximumActive:Int{lock.lock();defer{lock.unlock()};return maximum}
}
@Test func checkpointWriterSerializesSlowCommitsAndSkipsCancelledQueuedSnapshots() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("life-checkpoint-order-"+UUID().uuidString,isDirectory:true)
    defer{try? FileManager.default.removeItem(at:root)}
    let store=RecoveryStore(root:root),gate=CheckpointGate()
    let first=ProjectDocument(name:"First")
    var last=first;last.name="Latest"
    var obsolete=first;obsolete.name="Cancelled"
    let latest=last,stale=obsolete
    let writer=RecoveryWriter(write:{snapshot in
        gate.enter();defer{gate.leave()}
        if snapshot.name=="First"{gate.started.signal();gate.release.wait()}
        try store.checkpoint(snapshot)
    })
    let initial=Task{try await writer.checkpoint(first)}
    await Task.detached{gate.waitUntilStarted()}.value
    initial.cancel() // An in-progress atomic commit may finish, before the next starts.
    let queued=Task{try await writer.checkpoint(stale)};queued.cancel()
    let current=Task{try await writer.checkpoint(latest)}
    gate.release.signal()
    try await initial.value
    do{try await queued.value;Issue.record("Cancelled checkpoint committed")}catch is CancellationError{}catch{throw error}
    try await current.value
    #expect(gate.maximumActive==1)
    #expect(try ProjectPackage.recoverLatest(in:root.appendingPathComponent(first.id.uuidString))==latest)
}
