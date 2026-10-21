import Foundation
import LifeCore

struct RecoveryStore:Sendable {
    let root:URL
    init(){root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Life Editor/Recovery",isDirectory:true)}
    func recoverableProjects()->[ProjectDocument] {
        guard let folders=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) else{return []}
        return folders.compactMap{try? ProjectPackage.recoverLatest(in:$0)}
    }
    func checkpoint(_ document:ProjectDocument)throws{
        try ProjectPackage.checkpoint(document,in:root.appendingPathComponent(document.id.uuidString,isDirectory:true),keeping:5)
    }
}
