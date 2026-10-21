import Foundation
import Testing
@testable import LifeCore
private func graphicDoc(_ content: GraphicContent) -> ProjectDocument {
    ProjectDocument(sequence:Sequence(tracks:[Track(name:"Graphic",kind:.shape,clips:[Clip(duration:RationalTime(value:3,timescale:1),graphic:content)])]))
}
@Test func normalizedGraphicsAndStylesRoundtripWithoutResolutionCoordinates() throws {
    let shape=ShapeContent(kind:.roundedRectangle,rect:GraphicRect(x:0.1,y:0.2,width:0.6,height:0.5),fill:RGBAColor(red:1,green:0.2,blue:0.1,alpha:0.5),stroke:.white,strokeWidth:0.02,cornerRadius:0.05)
    let doc=graphicDoc(.shape(shape))
    #expect(try ProjectDocument.decode(doc.encoded()) == doc)
    var resized=doc; resized.sequence.settings.width=3840; resized.sequence.settings.height=2160
    #expect(resized.sequence.tracks[0].clips[0].graphic == doc.sequence.tracks[0].clips[0].graphic)
    let stroke=DrawingStroke(points:[GraphicPoint(x:0.1,y:0.2),GraphicPoint(x:0.7,y:0.9)],color:.white,width:0.01,tool:.highlighter)
    let drawing=graphicDoc(.drawing(DrawingContent(strokes:[stroke])))
    #expect(try ProjectDocument.decode(drawing.encoded()) == drawing)
    let legacy=ProjectDocument(sequence:Sequence(tracks:[Track(name:"Video",kind:.video,clips:[Clip(duration:RationalTime(value:1,timescale:1))])]))
    #expect(try ProjectDocument.decode(legacy.encoded()).sequence.tracks[0].clips[0].graphic == nil)
}
@Test func graphicsRejectInvalidGeometryAndExcessivePaths() throws {
    #expect(!GraphicContent.shape(ShapeContent(kind:.ellipse,rect:GraphicRect(x:0.8,width:0.4))).isValid)
    #expect(!GraphicContent.shape(ShapeContent(kind:.rectangle,strokeWidth:.nan)).isValid)
    #expect(!GraphicContent.shape(ShapeContent(kind:.rectangle,rect:GraphicRect(width:0))).isValid)
    #expect(GraphicContent.shape(ShapeContent(kind:.line,rect:GraphicRect(x:0.1,y:0.1,width:0.5,height:0))).isValid)
    let badStroke=DrawingStroke(points:[GraphicPoint(x:.infinity,y:0.5)])
    #expect(!GraphicContent.drawing(DrawingContent(strokes:[badStroke])).isValid)
    let tooMany=DrawingStroke(points:Array(repeating:GraphicPoint(x:0.1,y:0.1),count:10001))
    #expect(!GraphicContent.drawing(DrawingContent(strokes:[tooMany])).isValid)
    let stroke=DrawingStroke(points:[GraphicPoint(x:0.1,y:0.1)])
    #expect(!GraphicContent.drawing(DrawingContent(strokes:[stroke,stroke])).isValid)
    var conflicting=graphicDoc(.shape(ShapeContent(kind:.rectangle)))
    conflicting.sequence.tracks[0].clips[0].title=TitleContent(text:"Cannot also be a title")
    #expect(throws:DocumentError.invalidTiming) { try conflicting.validate() }
}
@MainActor @Test func graphicEditingUndoRestoresExactDocument() throws {
    let doc=graphicDoc(.drawing(DrawingContent()))
    let editor=ProjectEditor(document:doc)
    var next=doc
    next.sequence.tracks[0].clips[0].graphic = .drawing(DrawingContent(strokes:[DrawingStroke(points:[GraphicPoint(x:0.1,y:0.2),GraphicPoint(x:0.4,y:0.8)],color:RGBAColor(red:0,green:1,blue:1))]))
    try editor.perform(.replace(next)); editor.undo(); #expect(editor.document == doc)
    editor.redo(); #expect(editor.document == next)
}
