import Foundation
import Testing
@testable import LifeMedia
@Test func waveformCleanupCountsOnlyOwnedHashesAndNeverTraversesLinksOrOriginals() throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? fm.removeItem(at:root)}
    let folder=root.appendingPathComponent("org.lifeeditor.waveforms"),outside=root.appendingPathComponent("originals"),required=root.appendingPathComponent("Required")
    for path in [folder,outside,required]{try fm.createDirectory(at:path,withIntermediateDirectories:true)}
    let hash=String(repeating:"a",count:64),original=outside.appendingPathComponent(hash+".mov"),intermediate=required.appendingPathComponent(hash+".mov")
    try Data([1,2,3]).write(to:original);try Data([4,5]).write(to:intermediate)
    let owned=folder.appendingPathComponent(hash+".waveform"),unrelated=folder.appendingPathComponent("notes.waveform"),audio=folder.appendingPathComponent(hash+".wav")
    try Data([6,7,8,9]).write(to:owned);try Data([10]).write(to:unrelated);try Data([11]).write(to:audio)
    try fm.createSymbolicLink(at:folder.appendingPathComponent(String(repeating:"b",count:64)+".waveform"),withDestinationURL:original)
    try fm.createSymbolicLink(at:root.appendingPathComponent("org.lifeeditor.proxy"),withDestinationURL:outside)
    let storage=CacheStorage(root:root)
    #expect(try storage.usageBytes() == 4)
    try storage.cleanup(budget:0)
    #expect(!fm.fileExists(atPath:owned.path));#expect(fm.fileExists(atPath:original.path));#expect(fm.fileExists(atPath:intermediate.path));#expect(fm.fileExists(atPath:unrelated.path));#expect(fm.fileExists(atPath:audio.path))
}
