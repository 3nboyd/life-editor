import SwiftUI
import LifeCore

struct AudioControls:View {
    @ObservedObject var store:EditorStore
    private func binding(_ path:WritableKeyPath<AudioSettings,Double>)->Binding<Double>{
        Binding(get:{(store.selectedClip?.audio ?? AudioSettings())[keyPath:path]},set:{value in store.editAudio{$0[keyPath:path]=value}})
    }
    private func control(_ label:String,_ path:WritableKeyPath<AudioSettings,Double>,_ range:ClosedRange<Double>)->some View{
        VStack(spacing:4){
            HStack{Text(label);Spacer();Text(String(format:"%.1f",binding(path).wrappedValue)).monospacedDigit()}
            Slider(value:binding(path),in:range,onEditingChanged:{active in if active{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel(label)
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{
                if store.measuringAudio{ProgressView().controlSize(.small);Button("Cancel",action:store.cancelAudioMeasurement)}
                else{Button("Measure",action:store.measureAudio).help("Measure sequence audio")}
                Spacer()
                if let value=store.audioMeasurement {Text(value.peakDBFS.isFinite ? String(format:"%.1f dBFS",value.peakDBFS):"−∞ dBFS").foregroundStyle(value.peakDBFS>=0 ? .red:.secondary).monospacedDigit().accessibilityLabel("Sequence sample peak")}
            }
            if let value=store.audioMeasurement,let loudness=value.loudnessLUFS {Text(loudness.isFinite ? String(format:"%.1f LUFS",loudness):"−∞ LUFS").monospacedDigit().accessibilityLabel("Integrated loudness")}
            if let meter=store.currentAudioMeter{
                meterBar("L",meter.leftDBFS);meterBar("R",meter.rightDBFS)
            }
            if store.selectedClip?.assetID != nil {
                Divider()
                Button("Normalize…",action:store.suggestNormalization).disabled(store.measuringAudio).help("Preview peak normalization to −1 dBFS")
                if let suggestion=store.normalization,suggestion.clipID==store.selection{
                    HStack{Text(String(format:"%+.1f dB",suggestion.gainAdjustmentDB)).monospacedDigit();Spacer();Button("Apply",action:store.applyNormalization)}
                    if suggestion.limitedByHeadroom{Text("Gain limit").foregroundStyle(.secondary)}
                }
                control("Gain · dB",\.gainDB,-96...24)
                control("Pan",\.pan,-1...1)
                Picker("Channels",selection:Binding(get:{store.selectedClip?.audio?.channels ?? .stereo},set:{value in store.editAudio{$0.channels=value}})){
                    ForEach(AudioChannelMode.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}
                }
                control("Low · dB",\.eqLowDB,-18...18)
                control("Mid · dB",\.eqMidDB,-18...18)
                control("High · dB",\.eqHighDB,-18...18)
                Toggle("Limiter",isOn:Binding(get:{store.selectedClip?.audio?.limiterEnabled ?? false},set:{value in store.editAudio{$0.limiterEnabled=value}}))
                if store.selectedClip?.audio?.limiterEnabled == true{control("Ceiling · dBFS",\.limiterCeilingDB,-12...0)}
                Button("Reset Audio"){store.editSelected{$0.audio=nil}}
            }
        }.font(.system(size:12))
    }
    private func meterBar(_ label:String,_ db:Double)->some View{
        HStack{Text(label).frame(width:12);GeometryReader{geometry in
            ZStack(alignment:.leading){Capsule().fill(.white.opacity(0.08));Capsule().fill(db>=0 ? Color.red:Color.accentColor).frame(width:geometry.size.width*min(1,max(0,(db+60)/60)))}
        }.frame(height:6);Text(db.isFinite ? String(format:"%.1f",db):"−∞").monospacedDigit().frame(width:36)}.accessibilityElement(children:.ignore).accessibilityLabel("\(label) sample peak").accessibilityValue(db.isFinite ? String(format:"%.1f decibels",db):"Silence")
    }
}
