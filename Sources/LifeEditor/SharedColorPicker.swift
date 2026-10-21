import SwiftUI
import LifeCore

struct HSVColor:Equatable { var hue:Double;var saturation:Double;var value:Double;var alpha:Double=1 }
enum ColorConversion {
    static func valid(_ color:RGBAColor)->Bool { [color.red,color.green,color.blue,color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    static func hsv(_ color:RGBAColor)->HSVColor? {
        guard valid(color) else { return nil }
        let maximum=max(color.red,color.green,color.blue),minimum=min(color.red,color.green,color.blue),delta=maximum-minimum
        var hue=0.0
        if delta>0 {
            if maximum == color.red { hue=(color.green-color.blue)/delta }
            else if maximum == color.green { hue=(color.blue-color.red)/delta+2 }
            else { hue=(color.red-color.green)/delta+4 }
            hue /= 6;if hue<0 { hue += 1 }
        }
        return HSVColor(hue:hue,saturation:maximum == 0 ? 0:delta/maximum,value:maximum,alpha:color.alpha)
    }
    static func rgb(_ hsv:HSVColor)->RGBAColor? {
        guard [hsv.hue,hsv.saturation,hsv.value,hsv.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let position=(hsv.hue == 1 ? 0:hsv.hue)*6,sector=Int(position),fraction=position-Double(sector)
        let p=hsv.value*(1-hsv.saturation),q=hsv.value*(1-fraction*hsv.saturation),t=hsv.value*(1-(1-fraction)*hsv.saturation)
        let rgb:(Double,Double,Double)
        switch sector { case 0:rgb=(hsv.value,t,p);case 1:rgb=(q,hsv.value,p);case 2:rgb=(p,hsv.value,t);case 3:rgb=(p,q,hsv.value);case 4:rgb=(t,p,hsv.value);default:rgb=(hsv.value,p,q) }
        return RGBAColor(red:rgb.0,green:rgb.1,blue:rgb.2,alpha:hsv.alpha)
    }
    static func hex(_ color:RGBAColor,includeAlpha:Bool=true)->String? {
        guard valid(color) else { return nil }
        let components=[color.red,color.green,color.blue]+(includeAlpha ? [color.alpha]:[])
        return "#"+components.map { String(format:"%02X",Int(($0*255).rounded())) }.joined()
    }
    static func parseHex(_ text:String)->RGBAColor? {
        var value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard [3,4,6,8].contains(value.count),value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn:"0123456789abcdefABCDEF").contains($0) }) else { return nil }
        if value.count<=4 { value=value.map { String(repeating:String($0),count:2) }.joined() }
        guard let bits=UInt32(value,radix:16) else { return nil }
        if value.count == 6 { return RGBAColor(red:Double((bits>>16)&255)/255,green:Double((bits>>8)&255)/255,blue:Double(bits&255)/255) }
        return RGBAColor(red:Double((bits>>24)&255)/255,green:Double((bits>>16)&255)/255,blue:Double((bits>>8)&255)/255,alpha:Double(bits&255)/255)
    }
}
@MainActor final class ColorSwatchLibrary:ObservableObject {
    static let shared=ColorSwatchLibrary()
    @Published private(set) var recent:[RGBAColor]
    @Published private(set) var saved:[RGBAColor]
    private let defaults:UserDefaults
    private let recentKey="LifeEditor.colors.recent.v1",savedKey="LifeEditor.colors.saved.v1"
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        recent=Self.load(defaults.data(forKey:"LifeEditor.colors.recent.v1"),limit:12)
        saved=Self.load(defaults.data(forKey:"LifeEditor.colors.saved.v1"),limit:16)
    }
    func remember(_ color:RGBAColor) {
        guard ColorConversion.valid(color) else { return }
        recent.removeAll { ColorConversion.hex($0) == ColorConversion.hex(color) };recent.insert(color,at:0);recent=Array(recent.prefix(12));persist()
    }
    func save(_ color:RGBAColor) {
        guard ColorConversion.valid(color),!saved.contains(where:{ColorConversion.hex($0)==ColorConversion.hex(color)}) else { return }
        saved.append(color);saved=Array(saved.suffix(16));remember(color);persist()
    }
    func remove(_ color:RGBAColor) { saved.removeAll { $0 == color };persist() }
    private func persist() { if let data=try? JSONEncoder().encode(recent){defaults.set(data,forKey:recentKey)};if let data=try? JSONEncoder().encode(saved){defaults.set(data,forKey:savedKey)} }
    private static func load(_ data:Data?,limit:Int)->[RGBAColor] { guard let data,let colors=try? JSONDecoder().decode([RGBAColor].self,from:data) else { return [] };return Array(colors.filter(ColorConversion.valid).prefix(limit)) }
}
struct SharedColorPicker:View {
    let label:String
    @Binding var color:RGBAColor
    @ObservedObject var store:EditorStore
    @State private var presented=false
    var body:some View {
        Button{presented.toggle()}label:{HStack(spacing:6){Text(label).lineLimit(1);Spacer(minLength:2);ColorChip(color:color).frame(width:24,height:20)}.frame(minHeight:30).contentShape(Rectangle())}
            .buttonStyle(.plain).help(label+" color").accessibilityLabel(label+" color").accessibilityValue(ColorConversion.hex(color) ?? "Unavailable")
            .popover(isPresented:$presented){ColorPopover(color:$color,store:store){
                presented=false
                store.beginColorSampling { value in color=value;ColorSwatchLibrary.shared.remember(value) }
            }}
    }
}
private struct ColorChip:View {
    let color:RGBAColor
    var body:some View {
        ZStack{
            Canvas{context,size in for row in 0..<Int(ceil(size.height/6)){for column in 0..<Int(ceil(size.width/6)){context.fill(Path(CGRect(x:Double(column)*6,y:Double(row)*6,width:6,height:6)),with:.color((row+column)%2 == 0 ? Color(white:0.35):Color(white:0.6)))}}}
            Color(.sRGB,red:color.red,green:color.green,blue:color.blue,opacity:color.alpha)
        }.clipShape(RoundedRectangle(cornerRadius:3)).overlay{RoundedRectangle(cornerRadius:3).stroke(.white.opacity(0.25),lineWidth:1)}
    }
}
struct ColorPopover:View {
    @Binding var color:RGBAColor
    @ObservedObject var store:EditorStore
    var sample:()->Void
    @ObservedObject var library=ColorSwatchLibrary.shared
    @State private var hsv=HSVColor(hue:0,saturation:0,value:1)
    @State private var hexText=""
    @State private var rgbText=["0","0","0"]
    @State private var alphaText="100"
    @State private var inputError:String?
    @State private var gestureActive=false
    private func begin(){if !gestureActive{gestureActive=true;store.beginGesture()}}
    private func end(){if gestureActive{gestureActive=false;store.endGesture()}}
    private func refresh(){
        if var new=ColorConversion.hsv(color){if new.saturation == 0 || new.value == 0 {new.hue=hsv.hue};hsv=new}
        hexText=ColorConversion.hex(color,includeAlpha:color.alpha<1) ?? ""
        rgbText=[color.red,color.green,color.blue].map{String(format:"%.0f",$0*255)};alphaText=String(format:"%.1f",color.alpha*100)
    }
    private func updateHSV(_ change:(inout HSVColor)->Void){var next=hsv;change(&next);guard let rgb=ColorConversion.rgb(next) else{return};hsv=next;color=rgb;inputError=nil}
    private func commitRGB(_ index:Int){
        guard let value=Double(rgbText[index]),value.isFinite,(0...255).contains(value) else{inputError="RGB 0–255";refresh();return}
        var next=color;if index == 0{next.red=value/255}else if index == 1{next.green=value/255}else{next.blue=value/255};color=next;inputError=nil;refresh()
    }
    private func commitAlpha(){guard let value=Double(alphaText),value.isFinite,(0...100).contains(value) else{inputError="Alpha 0–100%";refresh();return};color.alpha=value/100;inputError=nil;refresh()}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            sampleRow
            HStack(spacing:12){hueWheel;saturationSquare}
            hexRow
            HStack(spacing:8){ForEach(0..<3,id:\.self){componentField($0)}}
            alphaRow
            if let inputError{Text(inputError).font(.caption).foregroundStyle(.red)}
            if !library.recent.isEmpty{Text("Recent").font(.caption).foregroundStyle(.secondary);swatches(library.recent,saved:false)}
            savedRow
            if !library.saved.isEmpty{swatches(library.saved,saved:true)}
        }.font(.system(size:12)).frame(width:256).padding(12).onAppear(perform:refresh).onChange(of:color){refresh()}.onDisappear{end();library.remember(color)}
    }
    private var sampleRow:some View {
        HStack{
            ColorChip(color:color).frame(width:44,height:28)
            Text("sRGB").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action:sample){Image(systemName:"eyedropper").frame(width:24,height:24)}.help("Sample viewer color · ⌥I").accessibilityLabel("Sample viewer color").keyboardShortcut("i",modifiers:.option)
        }
    }
    private var hueWheel:some View {
        let hues=(0...12).map{Color(hue:Double($0)/12,saturation:1,brightness:1)}
        let angle=hsv.hue*2*Double.pi
        return ZStack{
            Circle().stroke(AngularGradient(colors:hues,center:.center),lineWidth:12).padding(6)
            Circle().stroke(Color.white,lineWidth:2).frame(width:12,height:12).shadow(color:.black,radius:1).offset(x:cos(angle)*42,y:sin(angle)*42)
        }.frame(width:96,height:96).contentShape(Circle())
            .gesture(DragGesture(minimumDistance:0).onChanged{value in
                begin();var hue=atan2(value.location.y-48,value.location.x-48)/(2*Double.pi);if hue<0{hue += 1};updateHSV{$0.hue=hue}
            }.onEnded{_ in end()})
            .accessibilityElement(children:.ignore).accessibilityLabel("Hue").accessibilityValue(String(format:"%.0f degrees",hsv.hue*360)).accessibilityAdjustableAction{direction in
                if direction == .increment{updateHSV{$0.hue=($0.hue+1.0/360).truncatingRemainder(dividingBy:1)}}else if direction == .decrement{updateHSV{$0.hue=($0.hue+1-1.0/360).truncatingRemainder(dividingBy:1)}}
            }
    }
    private var saturationSquare:some View {
        ZStack(alignment:.topLeading){
            Color(hue:hsv.hue,saturation:1,brightness:1)
            LinearGradient(colors:[Color.white,Color.white.opacity(0)],startPoint:.leading,endPoint:.trailing)
            LinearGradient(colors:[Color.clear,Color.black],startPoint:.top,endPoint:.bottom)
            Circle().stroke(Color.white,lineWidth:2).background{Circle().stroke(Color.black,lineWidth:3)}.frame(width:10,height:10).position(x:hsv.saturation*148,y:(1-hsv.value)*96)
        }.frame(width:148,height:96).clipShape(RoundedRectangle(cornerRadius:4)).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged{value in
                begin();updateHSV{$0.saturation=min(1,max(0,value.location.x/148));$0.value=1-min(1,max(0,value.location.y/96))}
            }.onEnded{_ in end()})
            .accessibilityElement(children:.ignore).accessibilityLabel("Saturation and brightness").accessibilityValue(String(format:"%.0f percent saturation, %.0f percent brightness",hsv.saturation*100,hsv.value*100))
    }
    private var hexRow:some View {
        HStack{Text("HEX");TextField("HEX",text:$hexText).textFieldStyle(.roundedBorder).monospaced().onSubmit{
            if let next=ColorConversion.parseHex(hexText){color=next;inputError=nil;refresh()}else{inputError="HEX: 3, 4, 6 or 8 digits"}
        }.accessibilityLabel("sRGB hex color")}
    }
    private func componentField(_ index:Int)->some View {
        let name=["Red","Green","Blue"][index]
        return HStack(spacing:3){
            Text(["R","G","B"][index])
            TextField(name,text:Binding(get:{rgbText[index]},set:{rgbText[index]=$0})).textFieldStyle(.roundedBorder).onSubmit{commitRGB(index)}.accessibilityLabel(name+" 0 to 255")
        }
    }
    private var alphaRow:some View {
        HStack{
            Text("α")
            Slider(value:Binding(get:{color.alpha},set:{color.alpha=$0}),in:0...1,onEditingChanged:{if $0{begin()}else{end()}}).accessibilityLabel("Alpha")
            TextField("Alpha",text:$alphaText).textFieldStyle(.roundedBorder).frame(width:48).onSubmit{commitAlpha()}.accessibilityLabel("Alpha percent")
        }
    }
    private var savedRow:some View {
        HStack{Text("Saved").font(.caption).foregroundStyle(.secondary);Spacer();Button{library.save(color)}label:{Image(systemName:"plus").frame(width:20,height:20)}.help("Save swatch").accessibilityLabel("Save color swatch")}
    }
    private func swatches(_ colors:[RGBAColor],saved:Bool)->some View {
        LazyVGrid(columns:Array(repeating:GridItem(.fixed(26),spacing:6),count:8),spacing:6){ForEach(Array(colors.enumerated()),id:\.offset){_,value in
            Button{color=value;library.remember(value)}label:{ColorChip(color:value).frame(width:24,height:24)}.buttonStyle(.plain).help(ColorConversion.hex(value) ?? "Color").accessibilityLabel((saved ? "Saved ":"Recent ")+(ColorConversion.hex(value) ?? "color"))
                .contextMenu{if saved{Button("Remove"){library.remove(value)}}}
        }}
    }
}
