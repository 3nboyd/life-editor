import Foundation
import LifeCore

struct RecoveryStore:Sendable {
    let root:URL
    init(root:URL?=nil){self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Life Editor/Recovery",isDirectory:true)}
    func recoverableProjects()->[ProjectDocument] {
        guard let folders=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) else{return []}
        return folders.compactMap{try? ProjectPackage.recoverLatest(in:$0)}
    }
    func checkpoint(_ document:ProjectDocument)throws{
        try ProjectPackage.checkpoint(document,in:root.appendingPathComponent(document.id.uuidString,isDirectory:true),keeping:5)
    }
}

/// One serial executor owns checkpoint commits. Cancellation is checked when a
/// queued request begins, so an obsolete request cannot commit after a newer one.
actor RecoveryWriter {
    static let shared=RecoveryWriter()
    private let write:@Sendable(ProjectDocument)throws->Void
    init(store:RecoveryStore=RecoveryStore()){write={try store.checkpoint($0)}}
    init(write:@escaping @Sendable(ProjectDocument)throws->Void){self.write=write}
    func checkpoint(_ document:ProjectDocument)throws{try Task.checkCancellation();try write(document)}
}
