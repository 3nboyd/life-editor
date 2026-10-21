import SwiftUI
import AVFoundation
import CoreImage
import LifeCore
import LifeMedia

struct TransitionsBrowser:View {
    @ObservedObject var store:EditorStore
    @State private var frames:[TransitionKind:CGImage]=[:]
    @State private var hovered:TransitionKind?
    @State private var outgoing:CIImage?
    @State private var incoming:CIImage?
    private let context=CIContext()
    private var pair:(Clip,Clip)?{store.transitionPair()}
    var body:some View {
        VStack(spacing:12){
            if let transition=store.currentTransition {
                HStack{Text(title(transition.kind));Spacer();Button{store.apply(.removeTransition(id:transition.id));store.selectedTransition=nil}label:{Image(systemName:"trash")}.buttonStyle(.plain).help("Remove transition").accessibilityLabel("Remove transition")}
                let maximum=(try? TransitionResolver.availableDuration(leftClipID:transition.leftClipID,rightClipID:transition.rightClipID,in:store.document,excluding:transition.id))?.seconds ?? 0
                HStack{Text("Duration");TextField("Seconds",value:Binding(get:{store.currentTransition?.duration.seconds ?? 0},set:{v in store.setTransitionDuration(v)}),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder)}
                if maximum>0 {
                    Slider(value:Binding(get:{store.currentTransition?.duration.seconds ?? 0},set:{store.setTransitionDuration($0)}),in:store.document.sequence.settings.frameRate.frameDuration.seconds...max(maximum,store.document.sequence.settings.frameRate.frameDuration.seconds),onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel("Transition duration")
                }
                if TransitionResolver.resolve(transition,in:store.document)==nil {Text("Unavailable").foregroundStyle(.orange).font(.caption)}
                Picker("Direction",selection:Binding(get:{store.currentTransition?.direction ?? 0},set:{v in store.editTransition{$0.direction=v}})){Image(systemName:"arrow.left").tag(0);Image(systemName:"arrow.right").tag(1);Image(systemName:"arrow.up").tag(2);Image(systemName:"arrow.down").tag(3)}.pickerStyle(.segmented)
                if transition.kind == .dipColor {
                    SharedColorPicker(label:"Color",color:Binding(get:{store.currentTransition?.color ?? .black},set:{value in store.editTransition{$0.color=value}}),store:store)
                }
                Toggle("Bypass",isOn:Binding(get:{!(store.currentTransition?.isEnabled ?? true)},set:{value in store.editTransition{$0.isEnabled = !value}})).toggleStyle(.button)
            }
            ScrollView{
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){
                    ForEach(TransitionKind.allCases,id:\.self){kind in
                        Button{if let pair{store.applyTransition(kind,left:pair.0.id,right:pair.1.id)}}label:{
                            VStack(alignment:.leading,spacing:4){
                                if let image=frames[kind]{Image(decorative:image,scale:1).resizable().aspectRatio(contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:4))}
                                Text(title(kind)).font(.caption).lineLimit(1)
                            }
                        }.buttonStyle(.plain).disabled(pair==nil).help(title(kind)).accessibilityLabel(title(kind))
                            .onHover{inside in hovered=inside ? kind:nil}
                            .onDrag{NSItemProvider(object:("life.transition."+kind.rawValue) as NSString)}
                    }
                }
            }
        }.task(id:pair.map{$0.0.id.uuidString+$0.1.id.uuidString}){await loadFrames()}
            .task(id:hovered){
                guard let kind=hovered,let a=outgoing,let b=incoming else{return}
                let template=VideoTransition(kind:kind,trackID:UUID(),leftClipID:UUID(),rightClipID:UUID(),duration:.init(value:1,timescale:1))
                for tick in 0..<120 {
                    guard !Task.isCancelled else{return}
                    let image=TransitionRenderer.image(from:a,to:b,transition:template,progress:Double(tick%45)/44,canvas:a.extent)
                    frames[kind]=context.createCGImage(image,from:a.extent)
                    do{try await Task.sleep(for:.milliseconds(33))}catch{return}
                }
            }
    }
    private func loadFrames() async {
        frames=[:];guard let pair else{return}
        do{
            let a=try await thumbnail(pair.0,nearEnd:true),b=try await thumbnail(pair.1,nearEnd:false)
            guard !Task.isCancelled else{return}
            outgoing=a;incoming=b
            for kind in TransitionKind.allCases {
                let transition=VideoTransition(kind:kind,trackID:UUID(),leftClipID:pair.0.id,rightClipID:pair.1.id,duration:.init(value:1,timescale:1))
                frames[kind]=context.createCGImage(TransitionRenderer.image(from:a,to:b,transition:transition,progress:0.4,canvas:a.extent),from:a.extent)
            }
        }catch{if !Task.isCancelled{store.error=error.localizedDescription}}
    }
    private func thumbnail(_ original:Clip,nearEnd:Bool) async throws ->CIImage {
        var clip=original;clip.start = .zero;clip.audioEnabled=false
        let settings=store.document.sequence.settings
        let document=ProjectDocument(sequence:Sequence(settings:settings,tracks:[Track(name:"Preview",kind:clip.title != nil ? .title:clip.graphic != nil ? .shape:.video,clips:[clip])]),assets:store.document.assets)
        let prepared=try await MediaPipeline().prepare(ProjectSnapshot(document:document))
        let generator=AVAssetImageGenerator(asset:prepared.playerItem.asset);generator.videoComposition=prepared.playerItem.videoComposition;generator.maximumSize=CGSize(width:160,height:90)
        generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        let seconds=nearEnd ? max(0,clip.duration.seconds-settings.frameRate.frameDuration.seconds):min(settings.frameRate.frameDuration.seconds,clip.duration.seconds/2)
        let result=try await generator.image(at:CMTime(seconds:seconds,preferredTimescale:48000))
        let image=CIImage(cgImage:result.image)
        return image.transformed(by:CGAffineTransform(scaleX:160/image.extent.width,y:90/image.extent.height)).cropped(to:CGRect(x:0,y:0,width:160,height:90))
    }
    private func title(_ kind:TransitionKind)->String {
        switch kind{case .crossDissolve:"Dissolve";case .fadeBlack:"Black";case .fadeWhite:"White";case .dipColor:"Dip Color";case .push:"Push";case .slide:"Slide";case .wipe:"Wipe";case .zoom:"Zoom";case .blur:"Blur";case .whipPan:"Whip Pan";case .shake:"Shake";case .glitch:"Glitch";case .flash:"Flash";case .lightLeak:"Light Leak"}
    }
}
