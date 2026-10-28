import SwiftUI
import LifeCore

struct TitleFontControls:View {
    @ObservedObject var store:EditorStore
    @State private var choosingFamily=false
    @State private var search=""
    let catalog:InstalledTitleFonts
    init(store:EditorStore,catalog:InstalledTitleFonts = .shared){self.store=store;self.catalog=catalog}
    var currentName:String{store.selectedClip?.title?.style?.fontName ?? "Helvetica-Bold"}
    private var current:InstalledTitleFonts.Face?{catalog.face(named:currentName)}
    private var families:[String]{catalog.families.filter{search.isEmpty || $0.localizedStandardContains(search)}}
    var body:some View {
        VStack(spacing:8){
            HStack{
                Text("Font")
                Button{search="";choosingFamily=true}label:{
                    HStack{Text(current?.family ?? currentName).lineLimit(1).truncationMode(.middle);Spacer(minLength:4);Image(systemName:"chevron.up.chevron.down").font(.caption2)}
                }.accessibilityLabel("Font family: "+(current?.family ?? currentName)).help("Choose installed font family")
                    .popover(isPresented:$choosingFamily){
                        VStack(spacing:8){
                            TextField("Search fonts",text:$search).textFieldStyle(.roundedBorder).accessibilityLabel("Search installed font families")
                            ScrollView{
                                LazyVStack(spacing:2){
                                    ForEach(families,id:\.self){family in
                                        Button{selectFamily(family);choosingFamily=false}label:{
                                            HStack{Text(family).lineLimit(1);Spacer();if current?.family==family{Image(systemName:"checkmark")}}.padding(.horizontal,8).frame(minHeight:30).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityAddTraits(current?.family==family ? .isSelected:[]).help(family)
                                    }
                                }
                            }
                        }.padding(12).frame(width:280,height:340)
                    }
            }
            if let current {
                Picker("Face",selection:Binding(get:{currentName},set:{selectFace($0)})){
                    if !catalog.faces(in:current.family).contains(where:{$0.name==currentName}){Text(current.label).tag(currentName)}
                    ForEach(catalog.faces(in:current.family)){face in Text(face.label).tag(face.name)}
                }.accessibilityLabel("Font face and weight").help("Choose font face and weight")
            }else{
                Label("Missing font",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .help(currentName).accessibilityLabel("Missing font: "+currentName)
            }
        }
    }
    func selectFamily(_ family:String){
        guard let face=catalog.matchingFace(in:family,from:currentName) else{return}
        selectFace(face.name)
    }
    func selectFace(_ name:String){
        guard catalog.face(named:name) != nil,name != currentName else{return}
        store.editSelected{clip in
            guard var title=clip.title else{return};var style=title.style ?? .init();style.fontName=name;title.style=style;clip.title=title
        }
    }
}
