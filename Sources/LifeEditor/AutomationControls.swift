import SwiftUI
import LifeCore

enum AutomationLane:String,CaseIterable { case volume,opacity
    var maximumValue:Double { self == .volume ? AudioSettings.maximumLinearGain:1 }
    var label:String { self == .volume ? "Volume":"Opacity" }
}
enum AutomationScale {
    static func position(_ value:Double,lane:AutomationLane)->Double {
        guard value > 0 else { return 0 }
        return lane == .volume ? min(1,max(0,(20*log10(value)+60)/84)):min(1,value)
    }
    static func value(_ position:Double,lane:AutomationLane)->Double {
        let fraction=min(1,max(0,position))
        return lane == .volume ? (fraction <= 0 ? 0:pow(10,(fraction*84-60)/20)):fraction
    }
    static func label(_ value:Double,lane:AutomationLane)->String {
        lane == .volume ? (value <= 0 ? "−∞ dB":String(format:"%.1f dB",20*log10(value))):String(format:"%.0f%%",value*100)
    }
    static func parse(_ text:String,lane:AutomationLane)->Double? {
        let normalized=text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().replacingOccurrences(of:"−",with:"-")
        if lane == .volume && ["-∞","-inf","silence"].contains(normalized) { return 0 }
        guard let number=Double(normalized),number.isFinite else { return nil }
        if lane == .volume { return (-96...24).contains(number) ? pow(10,number/20):nil }
        return (0...100).contains(number) ? number/100:nil
    }
    static func field(_ value:Double,lane:AutomationLane)->String { lane == .volume ? (value <= 0 ? "−∞":String(format:"%.1f",20*log10(value))):String(format:"%.1f",value*100) }
}
struct AutomationControls:View {
    @ObservedObject var store:EditorStore
    @State private var baseText="0"
    @State private var pointText="0"
    private func refresh(){baseText=AutomationScale.field(store.currentAutomationEnvelope.baseValue,lane:store.automationLane);if let point=store.currentAutomationPoint {pointText=AutomationScale.field(point.value*store.currentAutomationEnvelope.baseValue,lane:store.automationLane)}}
    private func commit(_ text:String,point:Bool){
        guard let value=AutomationScale.parse(text,lane:store.automationLane) else {store.error=store.automationLane == .volume ? "Enter −96…24 dB, or −∞ for silence.":"Enter 0…100%.";refresh();return}
        if point,let id=store.currentAutomationPoint?.id{store.updateAutomationPoint(id:id,effectiveValue:value)}else{store.setAutomationBase(value)};refresh()
    }
    var body:some View {
        VStack(alignment:.leading,spacing:9){
            if store.selectedIsAdjustment{Text("Opacity").font(.caption).foregroundStyle(.secondary)}else{Picker("Automation",selection:Binding(get:{store.automationLane},set:{store.automationLane=$0;store.selectedAutomationPoint=nil;refresh()})){
                ForEach(AutomationLane.allCases,id:\.self){Text($0.label).tag($0)}
            }.pickerStyle(.segmented).accessibilityLabel("Automation lane")}
            HStack{
                Text(store.automationLane == .volume ? "dB":"%")
                TextField("Level",text:$baseText).textFieldStyle(.roundedBorder).onSubmit{commit(baseText,point:false)}.accessibilityLabel("Overall \(store.automationLane.label.lowercased())")
                Button{store.setAutomationBase(0)}label:{Image(systemName:store.automationLane == .volume ? "speaker.slash":"eye.slash")}.help(store.automationLane == .volume ? "Silence":"Zero opacity").accessibilityLabel(store.automationLane == .volume ? "Silence":"Zero opacity")
            }
            Slider(value:Binding(get:{AutomationScale.position(store.currentAutomationEnvelope.baseValue,lane:store.automationLane)},set:{store.setAutomationBase(AutomationScale.value($0,lane:store.automationLane))}),in:0...1,onEditingChanged:{if $0{store.beginGesture()}else{store.endGesture()}}).accessibilityLabel("Overall \(store.automationLane.label.lowercased())")
            HStack{
                Text("Fade")
                TextField("In",value:Binding(get:{store.automationFadeDuration(incoming:true)},set:{store.setLaneFade($0,incoming:true)}),format:.number.precision(.fractionLength(3))).accessibilityLabel("Fade in seconds")
                Text("→")
                TextField("Out",value:Binding(get:{store.automationFadeDuration(incoming:false)},set:{store.setLaneFade($0,incoming:false)}),format:.number.precision(.fractionLength(3))).accessibilityLabel("Fade out seconds")
            }.textFieldStyle(.roundedBorder)
            HStack{
                Button{store.selectAdjacentAutomationPoint(-1)}label:{Image(systemName:"backward.end")}.help("Previous point · ⌥[").accessibilityLabel("Previous automation point").keyboardShortcut("[",modifiers:.option)
                Spacer()
                Button{store.addAutomationPoint(at:store.playhead)}label:{Image(systemName:"plus.diamond")}.help("Add point at playhead · ⌘-click curve").accessibilityLabel("Add automation point")
                Button(action:store.deleteAutomationPoint){Image(systemName:"trash")}.disabled(store.currentAutomationPoint == nil).help("Delete point · Delete").accessibilityLabel("Delete automation point")
                Spacer()
                Button{store.selectAdjacentAutomationPoint(1)}label:{Image(systemName:"forward.end")}.help("Next point · ⌥]").accessibilityLabel("Next automation point").keyboardShortcut("]",modifiers:.option)
            }
            HStack{
                Button{store.selectAllVisibleAutomationPoints()}label:{Image(systemName:"checkmark.circle")}.disabled(store.visibleAutomationPoints.isEmpty).help("Select visible points · ⌥⌘A").accessibilityLabel("Select all visible automation points").keyboardShortcut("a",modifiers:[.command,.option])
                Menu{
                    Button(store.selectedVisibleAutomationPoints.count>1 ? "Selected points":"Point"){store.copyAutomationPoint()}.disabled(store.currentAutomationPoint == nil).keyboardShortcut("c",modifiers:[.command,.option])
                    Button("Visible points"){store.copyVisibleAutomationPoints()}.disabled(store.visibleAutomationPoints.isEmpty).keyboardShortcut("c",modifiers:[.command,.option,.shift])
                }label:{Image(systemName:"doc.on.doc").frame(width:24,height:24)}.menuStyle(.borderlessButton).fixedSize().help("Copy automation points · ⌥⌘C").accessibilityLabel("Copy automation points")
                Button{store.pasteAutomationPoints()}label:{Image(systemName:"doc.on.clipboard").frame(width:24,height:24)}.disabled(store.selectedClip == nil || store.placementProposal != nil).help("Paste automation points at playhead · ⌥⌘V").accessibilityLabel("Paste automation points at playhead").keyboardShortcut("v",modifiers:[.command,.option])
                Spacer()
            }
            if store.selectedVisibleAutomationPoints.count>1 {HStack{Text("\(store.selectedVisibleAutomationPoints.count) points");if store.selectedVisibleAutomationPoints.contains(where:{$0.interpolation != store.currentAutomationPoint?.interpolation}){Text("Mixed curves").foregroundStyle(.secondary)}}.font(.caption)}
            if let point=store.currentAutomationPoint,let clip=store.selectedClip {
                HStack{
                    Text("Time")
                    TextField("Seconds",value:Binding(get:{store.automationLocalTime(point)},set:{store.updateAutomationPoint(id:point.id,sequenceTime:clip.start.seconds+$0)}),format:.number.precision(.fractionLength(5))).accessibilityLabel("Automation point time in seconds")
                    TextField(store.automationLane == .volume ? "dB":"%",text:$pointText).onSubmit{commit(pointText,point:true)}.accessibilityLabel("Automation point \(store.automationLane == .volume ? "decibels":"percent")")
                }.textFieldStyle(.roundedBorder)
                Picker("Curve",selection:Binding(get:{store.currentAutomationPoint?.interpolation ?? .linear},set:{store.updateAutomationPoint(id:point.id,interpolation:$0)})){
                    Text("Linear").tag(Interpolation.linear);Text("Ease").tag(Interpolation.eased);Text("Hold").tag(Interpolation.hold)
                }.pickerStyle(.segmented).accessibilityLabel("Automation curve after selected point")
            }
        }.font(.system(size:12)).onAppear{if store.selectedIsAdjustment{store.automationLane = .opacity};refresh()}.onChange(of:store.selection){if store.selectedIsAdjustment{store.automationLane = .opacity};refresh()}.onChange(of:store.automationLane){refresh()}.onChange(of:store.selectedAutomationPoint){refresh()}.onChange(of:store.selectedAutomationPointIDs){refresh()}.onChange(of:store.currentAutomationEnvelope){refresh()}
    }
}
