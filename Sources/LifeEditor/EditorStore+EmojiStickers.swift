import Foundation
import LifeCore

extension EditorStore {
    /// Emoji remain ordinary editable, timed text objects. Core Text supplies
    /// Apple's installed color glyphs in both preview and offline rendering.
    func addEmojiSticker(_ text:String) {
        let content=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !content.isEmpty,content.count<=64 else{error="Enter up to 64 characters.";return}
        var next=document
        let title=TitleContent(text:content,fontSize:max(1,min(4096,Double(next.sequence.settings.height)*0.18)),
                               style:.init(fontName:"AppleColorEmoji",x:0.5,y:0.5))
        let clip=Clip(name:"Emoji",start:time(playhead),duration:.init(value:3,timescale:1),title:title)
        next.sequence.tracks.append(Track(name:"Emoji",kind:.title,clips:[clip]))
        replace(next)
        if document == next{selection=clip.id;panel = .title;drawingMode=0}
    }
}
