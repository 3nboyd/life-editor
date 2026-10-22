import Foundation
import Testing
@testable import LifeCore

@MainActor struct CropGeometryTests {
    private let source=CropSize(width:200,height:100),canvas=CropSize(width:100,height:100)
    @Test func presetsUseSourceAspectAndRetainOrClampCropCenter() throws {
        let initial=VisualTransform(cropLeft:0.3,cropRight:0.1,cropTop:0.2,cropBottom:0.2)
        let square=try CropGeometry.applying(.square,to:initial,source:source)
        #expect(abs(square.cropLeft-0.35)<1e-10);#expect(abs(square.cropRight-0.15)<1e-10)
        #expect(square.cropTop==0 && square.cropBottom==0)
        let portrait=try CropGeometry.applying(.portrait,to:initial,source:source)
        let ratio=source.width*(1-portrait.cropLeft-portrait.cropRight)/(source.height*(1-portrait.cropTop-portrait.cropBottom))
        #expect(abs(ratio-9.0/16)<1e-10)
        let clamped=try CropGeometry.applying(.landscape,to:.init(cropLeft:0.8,cropRight:0.01),source:source)
        #expect(abs(clamped.cropRight)<1e-10)
        #expect(try CropGeometry.applying(.free,to:initial,source:source)==initial)
        #expect(CropGeometry.resettingCrop(in:initial).cropLeft==0)
    }
    @Test func fitAndFillUseRotatedBoundsAndExactRendererPivotWithFlips() throws {
        let normal=VisualTransform()
        #expect(try CropGeometry.placing(normal,source:source,canvas:canvas,mode:.fit).scaleX==1)
        #expect(try CropGeometry.placing(normal,source:source,canvas:canvas,mode:.fill).scaleX==2)
        let input=VisualTransform(rotationDegrees:90,cropLeft:0.1,cropRight:0.3,flipHorizontal:true)
        let fit=try CropGeometry.placing(input,source:source,canvas:canvas,mode:.fit)
        #expect(abs(fit.scaleX-5.0/3)<1e-10);#expect(fit.scaleX==fit.scaleY)
        #expect(abs(fit.x-0.5)<1e-10);#expect(abs(fit.y-2.0/3)<1e-10)
        #expect(fit.flipHorizontal && fit.rotationDegrees==90)
        let rotated=VisualTransform(rotationDegrees:45)
        let filled=try CropGeometry.placing(rotated,source:source,canvas:canvas,mode:.fill)
        #expect(abs(filled.scaleX-2*sqrt(2))<1e-10)
        let contained=try CropGeometry.placing(rotated,source:source,canvas:canvas,mode:.fit)
        #expect(abs(contained.scaleX-2*sqrt(2)/3)<1e-10)
    }
    @Test func invalidAndExtremeGeometryRejectWithoutMutationAndSettingsRoundTrip() throws {
        #expect(throws:CropGeometryError.self){try CropGeometry.placing(.init(),source:.init(width:0,height:100),canvas:canvas,mode:.fill)}
        #expect(throws:CropGeometryError.self){try CropGeometry.placing(.init(cropLeft:0.999999),source:source,canvas:canvas,mode:.fill)}
        #expect(throws:CropGeometryError.self){try CropGeometry.applying(.square,to:.init(rotationDegrees:.nan),source:source)}
        let parts=CropGeometry.straightenComponents(95);#expect(parts.base==90 && parts.angle==5)
        let clip=Clip(duration:.init(value:1,timescale:1),title:.init(text:"Canvas"))
        let original=ProjectDocument(sequence:.init(settings:.init(width:100,height:100),tracks:[.init(name:"Title",kind:.title,clips:[clip])]))
        var edited=original;edited.sequence.tracks[0].clips[0].visual=try CropGeometry.placing(.init(rotationDegrees:5),source:source,canvas:canvas,mode:.fill)
        let editor=ProjectEditor(document:original);try editor.perform(.replace(edited));editor.undo();#expect(editor.document==original);editor.redo();#expect(editor.document==edited)
        #expect(try ProjectDocument.decode(edited.encoded())==edited);#expect(edited.sequence.settings==original.sequence.settings)
    }
}
