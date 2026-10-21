import SwiftUI
import LifeCore
import LifeMedia

struct ExportSheet:View {
    @ObservedObject var store:EditorStore
    @Environment(\.dismiss) private var dismiss
    @State private var format:ExportFormat = .h264
    @State private var size=1080
    @State private var aspect=0
    @State private var rate=0
    @State private var selectedRange=false
    private var dimensions:(Int,Int) {
        switch aspect {case 1:return (size,size*16/9/2*2);case 2:return (size,size);case 3:return (size,size*5/4/2*2);default:return (size*16/9/2*2,size)}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            HStack{Text("Export").font(.headline);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Close export").accessibilityLabel("Close export").disabled(store.exporting)}
            if store.exporting {
                ProgressView(value:store.exportProgress).accessibilityLabel("Export progress")
                HStack{Text("\(Int(store.exportProgress*100))%").monospacedDigit();Spacer();Button("Cancel"){store.cancelExport()}}
            }else{
                Picker("Format",selection:$format){Text("H.264 · MP4").tag(ExportFormat.h264);Text("HEVC · MP4").tag(ExportFormat.hevc);Text("ProRes · MOV").tag(ExportFormat.proRes);Text("WAV").tag(ExportFormat.wav);Text("AIFF").tag(ExportFormat.aiff);Text("M4A").tag(ExportFormat.m4a)}
                if format.hasVideo {
                    Picker("Frame",selection:$aspect){Text("16:9").tag(0);Text("9:16").tag(1);Text("1:1").tag(2);Text("4:5").tag(3)}.pickerStyle(.segmented)
                    Picker("Size",selection:$size){Text("720p").tag(720);Text("1080p").tag(1080);Text("4K").tag(2160)}.pickerStyle(.segmented)
                    Picker("FPS",selection:$rate){Text("Project").tag(0);Text("24").tag(24);Text("25").tag(25);Text("29.97").tag(2997);Text("30").tag(30);Text("50").tag(50);Text("59.94").tag(5994);Text("60").tag(60)}
                }
                Toggle("Selected clip range",isOn:$selectedRange).disabled(store.selectedClip==nil)
                HStack{Spacer();Button("Export…"){
                    var options=ExportOptions(format:format)
                    if format.hasVideo {options.width=dimensions.0;options.height=dimensions.1}
                    if rate>0 {options.frameRate = rate==2997 ? .init(numerator:30000,denominator:1001):rate==5994 ? .init(numerator:60000,denominator:1001):.init(numerator:Int64(rate))}
                    if selectedRange,let clip=store.selectedClip{options.rangeStart=clip.start;options.rangeDuration=clip.duration}
                    store.beginExport(options:options)
                }.keyboardShortcut(.defaultAction)}
            }
        }.padding(24).frame(width:380)
            .onChange(of:store.exporting){was,isNow in if was && !isNow && store.error==nil{dismiss()}}
    }
}
