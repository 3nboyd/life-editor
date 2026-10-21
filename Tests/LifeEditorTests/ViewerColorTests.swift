import Testing
import CoreImage
import CoreVideo
@testable import LifeEditor

@MainActor @Test func viewerSamplerUsesCanvasCoordinatesAndRejectsInvalidPoints() throws {
    var buffer:CVPixelBuffer?
    #expect(CVPixelBufferCreate(nil,20,10,kCVPixelFormatType_32BGRA,nil,&buffer)==kCVReturnSuccess)
    let pixels=try #require(buffer)
    let canvas=CGRect(x:0,y:0,width:20,height:10)
    let red=CIImage(color:.red).cropped(to:CGRect(x:0,y:5,width:10,height:5))
    let blue=CIImage(color:.blue).cropped(to:canvas)
    CIContext().render(red.composited(over:blue),to:pixels,bounds:canvas,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
    let topLeft=try #require(ViewerColorSampler.sample(pixels,x:0.1,y:0.1))
    #expect(topLeft.red>0.98 && topLeft.blue<0.02)
    let lowerRight=try #require(ViewerColorSampler.sample(pixels,x:1,y:1))
    #expect(lowerRight.blue>0.98 && lowerRight.red<0.02)
    #expect(ViewerColorSampler.sample(pixels,x:Double.nan,y:0)==nil)
    #expect(ViewerColorSampler.sample(pixels,x:1.1,y:0)==nil)
    let store=EditorStore();var called=false
    store.beginColorSampling{_ in called=true}
    #expect(!store.samplingColor && store.error != nil && !called)
}
