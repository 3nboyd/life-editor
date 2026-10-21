import Foundation
import LifeCore

/// Machine access data lives beside caches, never in a portable project.
struct MediaBookmarks {
    private let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Life Editor/Bookmarks",isDirectory:true)
    func remember(_ document:ProjectDocument) {
        let url=root.appendingPathComponent(document.id.uuidString+".json")
        var entries=(try? JSONDecoder().decode([UUID:Data].self,from:Data(contentsOf:url))) ?? [:]
        for asset in document.assets where asset.url.isFileURL {
            if let data=try? asset.url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil){entries[asset.id]=data}
        }
        do{try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONEncoder().encode(entries).write(to:url,options:.atomic)}catch{}
    }
    func resolve(_ document:ProjectDocument)->ProjectDocument {
        guard let data=try? Data(contentsOf:root.appendingPathComponent(document.id.uuidString+".json")),let entries=try? JSONDecoder().decode([UUID:Data].self,from:data) else{return document}
        var result=document
        for index in result.assets.indices where !FileManager.default.fileExists(atPath:result.assets[index].url.path) {
            guard let bookmark=entries[result.assets[index].id] else{continue}
            var stale=false
            if let url=try? URL(resolvingBookmarkData:bookmark,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale),FileManager.default.fileExists(atPath:url.path){result.assets[index].url=url}
        }
        return result
    }
}
