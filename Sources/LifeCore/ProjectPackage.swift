import Foundation

public enum PackageError: Error, Equatable { case destinationExists, unsafeReference, missingAsset(UUID), invalidCheckpointLimit }
public enum ProjectPackage {
    public static let projectFilename="project.json"
    public static func read(from url: URL) throws -> ProjectDocument {
        var document=try ProjectDocument.decode(Data(contentsOf:url.appendingPathComponent(projectFilename)))
        for i in document.assets.indices {
            document.assets[i].url=try resolved(document.assets[i].url,in:url)
            if let prepared=document.assets[i].preparedURL { document.assets[i].preparedURL=try resolved(prepared,in:url) }
        }
        return document
    }
    public static func write(_ document: ProjectDocument, to url: URL) throws {
        var portable=document
        for i in portable.assets.indices {
            portable.assets[i].url=relative(portable.assets[i].url,in:url)
            if let prepared=portable.assets[i].preparedURL { portable.assets[i].preparedURL=relative(prepared,in:url) }
        }
        let data=try portable.encoded()
        if FileManager.default.fileExists(atPath:url.appendingPathComponent(projectFilename).path) { _ = try read(from:url) }
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        try data.write(to:url.appendingPathComponent(projectFilename),options:.atomic)
    }
    public static func missingAssets(in document: ProjectDocument) -> [MediaAsset] {
        document.assets.filter { asset in
            ([asset.url]+(asset.preparedURL.map { [$0] } ?? [])).contains { !$0.isFileURL || !FileManager.default.fileExists(atPath:$0.path) }
        }
    }
    public static func relinking(_ document: ProjectDocument, assetID: UUID, to url: URL) throws -> ProjectDocument {
        guard url.isFileURL, FileManager.default.fileExists(atPath:url.path) else { throw PackageError.missingAsset(assetID) }
        var result=document
        guard let i=result.assets.firstIndex(where: { $0.id == assetID }) else { throw PackageError.missingAsset(assetID) }
        result.assets[i].url=url; result.assets[i].preparedURL=nil; try result.validate(); return result
    }
    /// Creates a new portable package. Originals and an existing destination are never replaced.
    public static func collect(_ document: ProjectDocument, to destination: URL) throws {
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path) else { throw PackageError.destinationExists }
        try document.validate()
        let staging=destination.deletingLastPathComponent().appendingPathComponent(".life-collect-\(UUID().uuidString)")
        defer { try? fm.removeItem(at:staging) }
        try fm.createDirectory(at:staging.appendingPathComponent("Media"),withIntermediateDirectories:true)
        var collected=document
        for i in document.assets.indices {
            let asset=document.assets[i]
            guard asset.url.isFileURL, fm.fileExists(atPath:asset.url.path) else { throw PackageError.missingAsset(asset.id) }
            let name=asset.id.uuidString+(asset.url.pathExtension.isEmpty ? "" : "."+asset.url.pathExtension)
            let relative="Media/"+name
            try fm.copyItem(at:asset.url,to:staging.appendingPathComponent(relative))
            collected.assets[i].url=URL(string:relative)!
            if let prepared=asset.preparedURL {
                guard prepared.isFileURL, fm.fileExists(atPath:prepared.path) else { throw PackageError.missingAsset(asset.id) }
                let preparedName=asset.id.uuidString+"-prepared"+(prepared.pathExtension.isEmpty ? "" : "."+prepared.pathExtension)
                let preparedRelative="Media/"+preparedName
                let preparedDestination=staging.appendingPathComponent(preparedRelative)
                try fm.copyItem(at:prepared,to:preparedDestination)
                let sidecar=prepared.deletingPathExtension().appendingPathExtension("probe.json")
                if fm.fileExists(atPath:sidecar.path) {
                    try fm.copyItem(at:sidecar,to:preparedDestination.deletingPathExtension().appendingPathExtension("probe.json"))
                }
                collected.assets[i].preparedURL=URL(string:preparedRelative)!
            }
        }
        try write(collected,to:staging)
        try fm.moveItem(at:staging,to:destination)
    }
    private static func resolved(_ reference: URL, in package: URL) throws -> URL {
        guard reference.scheme == nil else { return reference }
        let path=reference.relativeString.removingPercentEncoding ?? reference.relativeString
        guard !path.hasPrefix("/"), !path.split(separator:"/").contains("..") else { throw PackageError.unsafeReference }
        return package.appendingPathComponent(path).standardizedFileURL
    }
    private static func relative(_ reference: URL, in package: URL) -> URL {
        guard reference.isFileURL else { return reference }
        let root=package.standardizedFileURL.path+"/", path=reference.standardizedFileURL.path
        guard path.hasPrefix(root) else { return reference }
        return URL(string:String(path.dropFirst(root.count)).addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!)!
    }
    /// Checkpoints contain committed document state; media remains referenced in its original location.
    public static func checkpoint(_ document: ProjectDocument, in directory: URL, keeping limit: Int = 5) throws {
        guard limit > 0 else { throw PackageError.invalidCheckpointLimit }
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        let name="checkpoint-\(String(format:"%020.6f",Date().timeIntervalSince1970))-\(UUID().uuidString).json"
        try document.encoded().write(to:directory.appendingPathComponent(name),options:.atomic)
        let checkpoints=try fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("checkpoint-") && $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        // Recovery files from a newer app may contain work this build cannot interpret.
        // Retain them verbatim; only the supported recovery history consumes this rotation limit.
        let supported=checkpoints.filter { file in
            guard let data=try? Data(contentsOf:file),let version=try? ProjectMigration.headerVersion(in:data) else{return true}
            return version<=ProjectDocument.currentVersion
        }
        for old in supported.dropFirst(limit) { try fm.removeItem(at:old) }
    }
    public static func recoverLatest(in directory: URL) throws -> ProjectDocument? {
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("checkpoint-") && $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files { if let doc=try? ProjectDocument.decode(Data(contentsOf:file)) { return doc } }
        return nil
    }
}
