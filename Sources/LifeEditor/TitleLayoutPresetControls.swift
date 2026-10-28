import SwiftUI
import LifeCore
import LifeMedia

struct TitleLayoutPresetControls:View {
    @ObservedObject var store:EditorStore
    @State private var expanded=false
    @State private var thumbnails:[TitleLayoutPreset:CGImage]=[:]
    var body:some View {
        DisclosureGroup("Layout",isExpanded:$expanded){
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){
                ForEach(TitleLayoutPreset.allCases,id:\.self){preset in
                    Button{apply(preset)}label:{
                        VStack(spacing:3){
                            if let image=thumbnails[preset]{Image(nsImage:NSImage(cgImage:image,size:.zero)).resizable().scaledToFit().frame(height:56)}
                            else{Color.clear.frame(height:56)}
                            Text(preset.rawValue).font(.caption)
                        }.frame(maxWidth:.infinity).padding(5).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:6))
                    }.buttonStyle(.plain).help("Apply \(preset.rawValue) layout").accessibilityLabel("Apply \(preset.rawValue) layout")
                }
            }.padding(.top,6)
        }.task{
            do{for preset in TitleLayoutPreset.allCases{try Task.checkCancellation();thumbnails[preset]=try await TitleLayoutThumbnails.shared.image(for:preset)}}
            catch{if !Task.isCancelled{store.error=error.localizedDescription}}
        }
    }
    func apply(_ preset:TitleLayoutPreset){
        guard let clip=store.selectedClip else{return}
        do{let updated=try preset.applying(to:clip,canvasHeight:store.document.sequence.settings.height);store.editSelected{$0=updated}}
        catch{store.error=error.localizedDescription}
    }
}
