import SwiftUI
import LifeCore
import LifeMedia

struct TextPresetControls:View {
    @ObservedObject var store:EditorStore
    @State private var thumbnails:[TextFamily:CGImage]=[:]
    @State private var thumbnailError=false
    var body:some View {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){
            ForEach(TextFamily.allCases,id:\.self){family in
                Button{apply(family)}label:{
                    VStack(spacing:3){
                        if let image=thumbnails[family]{Image(nsImage:NSImage(cgImage:image,size:.zero)).resizable().scaledToFit().frame(height:48)}
                        else{Image(systemName:thumbnailError ? "exclamationmark.triangle":"textformat").frame(height:48).foregroundStyle(.secondary)}
                        Text(family.rawValue).font(.caption).lineLimit(1)
                    }.frame(maxWidth:.infinity).padding(5).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).help("Apply \(family.rawValue) text appearance").accessibilityLabel("Apply \(family.rawValue) text preset")
            }
        }.task{await loadThumbnails()}
    }
    func apply(_ family:TextFamily){
        guard let clip=store.selectedClip else{return}
        do{let updated=try TextPresets.applying(family,to:clip);store.editSelected{$0=updated}}
        catch{store.error=error.localizedDescription}
    }
    private func loadThumbnails()async {
        do{for family in TextFamily.allCases{try Task.checkCancellation();let image=try await TitleThumbnails.shared.image(for:family);try Task.checkCancellation();thumbnails[family]=image}}
        catch{if !Task.isCancelled{thumbnailError=true}}
    }
}
