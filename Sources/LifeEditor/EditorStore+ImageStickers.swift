import AppKit
import UniformTypeIdentifiers
import LifeCore

extension EditorStore {
    func importImageSticker() {
        guard !busy, placementProposal == nil else { return }
        let picker=NSOpenPanel()
        picker.allowedContentTypes=[.image];picker.allowsOtherFileTypes=false
        guard picker.runModal() == .OK,let url=picker.url else{return}
        busy=true;importProgress=0
        importTask=Task {
            defer{busy=false}
            do{try await insertImageSticker(from:url)}
            catch is CancellationError{}
            catch{self.error=Self.message(error)}
        }
    }

    /// Uses the normal referenced image asset, so collection and relinking keep
    /// their existing semantics. Alpha is decoded by the shared compositor.
    func insertImageSticker(from url:URL) async throws {
        let generation=projectGeneration,start=time(playhead)
        let probe=try await media.probe(url)
        try Task.checkCancellation()
        guard generation == projectGeneration else{return}
        guard probe.asset.kind == .image else{throw StickerImportError.imageRequired}
        var next=document
        let clip=Clip(name:url.deletingPathExtension().lastPathComponent,assetID:probe.asset.id,
                      start:start,duration:.init(value:3,timescale:1),visual:.init(scaleX:0.3,scaleY:0.3))
        next.assets.append(probe.asset)
        next.sequence.tracks.append(Track(name:"Sticker",kind:.image,clips:[clip]))
        replace(next)
        if document == next{selection=clip.id;panel = .clip;drawingMode=0}
    }
}

private enum StickerImportError:LocalizedError {
    case imageRequired
    var errorDescription:String?{"Choose an image for the sticker."}
}
