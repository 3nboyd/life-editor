import AppKit

/// Installed faces only. Persist PostScript names, never machine-specific indexes.
@MainActor struct InstalledTitleFonts {
    struct Face:Equatable,Identifiable {
        var name:String
        var family:String
        var label:String
        var weight:Int
        var traits:UInt
        var id:String{name}
    }
    let faces:[Face]
    static let shared=InstalledTitleFonts()
    init(faces:[Face]){self.faces=faces}
    init(){
        let manager=NSFontManager.shared
        faces=manager.availableFontFamilies.sorted{ $0.localizedStandardCompare($1) == .orderedAscending }.flatMap{family in
            (manager.availableMembers(ofFontFamily:family) ?? []).compactMap{member -> Face? in
                guard member.count>=4,let name=member[0] as? String,let label=member[1] as? String,
                      let weight=member[2] as? NSNumber,let traits=member[3] as? NSNumber,
                      NSFont(name:name,size:12) != nil else{return nil}
                return Face(name:name,family:family,label:label,weight:weight.intValue,traits:traits.uintValue)
            }
        }
    }
    var families:[String]{Array(Set(faces.map(\.family))).sorted{$0.localizedStandardCompare($1) == .orderedAscending}}
    func face(named name:String)->Face?{
        if let face=faces.first(where:{$0.name==name}){return face}
        // Registered fonts and valid aliases may not appear in the family catalog.
        guard let font=NSFont(name:name,size:12) else{return nil}
        let manager=NSFontManager.shared
        return Face(name:name,family:font.familyName ?? name,label:font.displayName ?? name,weight:manager.weight(of:font),traits:manager.traits(of:font).rawValue)
    }
    func faces(in family:String)->[Face]{faces.filter{$0.family==family}.sorted{left,right in
        left.weight == right.weight ? left.label.localizedStandardCompare(right.label) == .orderedAscending:left.weight<right.weight
    }}
    func matchingFace(in family:String,from name:String)->Face?{
        let original=face(named:name)
        // Prefer matching italic/width characteristics before nearest native weight.
        let mask=NSFontTraitMask.italicFontMask.rawValue | NSFontTraitMask.condensedFontMask.rawValue | NSFontTraitMask.expandedFontMask.rawValue
        return faces(in:family).min{left,right in
            func score(_ candidate:Face)->Int{
                let differences=((candidate.traits ^ (original?.traits ?? 0)) & mask).nonzeroBitCount
                return differences*100+abs(candidate.weight-(original?.weight ?? 5))
            }
            return score(left)<score(right)
        }
    }
}
