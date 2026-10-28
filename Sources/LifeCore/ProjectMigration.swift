import Foundation

/// The small header is decoded before interpreting any schema-specific project content.
/// Migration changes only the version: v1–v7 data has lossless Codable representations; absent solo state defaults to off.
enum ProjectMigration {
    private struct Header:Decodable { let version:Int }
    static func headerVersion(in data:Data)throws->Int {try JSONDecoder().decode(Header.self,from:data).version}
    static func decode(_ data:Data)throws->ProjectDocument {
        let version=try headerVersion(in:data)
        guard (1...ProjectDocument.currentVersion).contains(version) else{throw DocumentError.unsupportedVersion(version)}
        var document=try JSONDecoder().decode(ProjectDocument.self,from:data)
        if version<ProjectDocument.currentVersion {document.version=ProjectDocument.currentVersion}
        try document.validate();return document
    }
}
