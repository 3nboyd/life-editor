import Foundation
import AppKit
import Testing
import LifeCore
@testable import LifeEditor

@MainActor @Test func clipClipboardRejectsHostileTimesAndPreservesState()throws {
    let store=EditorStore(),clip=Clip(start:.init(value:2,timescale:1),duration:.init(value:2,timescale:1),title:.init(text:"Keep"))
    let original=ProjectDocument(sequence:.init(tracks:[.init(name:"Text",kind:.title,clips:[clip])]))
    store.replace(original);store.selection=clip.id
    let board=NSPasteboard(name:.init(UUID().uuidString));defer{board.releaseGlobally()}
    #expect(store.copySelection(to:board))
    let type=NSPasteboard.PasteboardType("org.lifeeditor.clips"),data=try #require(board.data(forType:type))
    var json=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
    let base=try #require(json["clips"] as? [[String:Any]])
    for value in [Int64.min,Int64.max] {
        var items=base,item=items[0],content=try #require(item["clip"] as? [String:Any])
        content["start"]=["value":value,"timescale":1];item["clip"]=content;items[0]=item;json["clips"]=items
        let malicious=try JSONSerialization.data(withJSONObject:json)
        board.setData(malicious,forType:type);store.pasteSelection(from:board)
        #expect(store.document==original);#expect(store.selection==clip.id)
        #expect(board.data(forType:type)==malicious)
    }
    board.setData(Data(repeating:32,count:8*1024*1024+1),forType:type)
    store.pasteSelection(from:board);#expect(store.document==original)
    board.setData(data,forType:type);store.playheadTime = .init(value:10,timescale:1)
    store.pasteSelection(from:board)
    let changed=store.document
    #expect(changed.sequence.tracks.count==2)
    #expect(changed.sequence.tracks[1].clips[0].start == .init(value:10,timescale:1))
    #expect(changed.sequence.tracks[1].clips[0].id != clip.id)
    store.undo();#expect(store.document==original)
    store.redo();#expect(store.document==changed)
}
