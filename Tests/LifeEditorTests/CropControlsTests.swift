import Testing
import Foundation
import AppKit
import ImageIO
import LifeCore
@testable import LifeEditor

@MainActor @Test func cropControlsReadActualImageDimensionsAndRejectMissingMedia() async throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("life-crop-source-\(UUID()).png")
    defer{try? FileManager.default.removeItem(at:url)}
    let context=try #require(CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:800,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
    let image=try #require(context.makeImage()),destination=try #require(CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil))
    CGImageDestinationAddImage(destination,image,nil);try #require(CGImageDestinationFinalize(destination))
    let asset=MediaAsset(url:url,kind:.image,duration:.init(value:1,timescale:1)),canvas=CropSize(width:100,height:100)
    #expect(try await VisualControls.sourceDimensions(asset:asset,canvas:canvas)==CropSize(width:200,height:100))
    #expect(try await VisualControls.sourceDimensions(asset:nil,canvas:canvas)==canvas)
    let orientedURL=url.deletingPathExtension().appendingPathExtension("jpg")
    defer{try? FileManager.default.removeItem(at:orientedURL)}
    let orientedDestination=try #require(CGImageDestinationCreateWithURL(orientedURL as CFURL,"public.jpeg" as CFString,1,nil))
    CGImageDestinationAddImage(orientedDestination,image,[kCGImagePropertyOrientation as String:6] as CFDictionary)
    try #require(CGImageDestinationFinalize(orientedDestination))
    let oriented=MediaAsset(url:orientedURL,kind:.image,duration:.init(value:1,timescale:1))
    let orientedSize=try await VisualControls.sourceDimensions(asset:oriented,canvas:canvas)
    #expect(orientedSize==CropSize(width:100,height:200))
    let cropped=try CropGeometry.applying(.landscape,to:.init(),source:orientedSize)
    let ratio=orientedSize.width*(1-cropped.cropLeft-cropped.cropRight)/(orientedSize.height*(1-cropped.cropTop-cropped.cropBottom))
    #expect(abs(ratio-16.0/9)<0.0001)
    let missing=MediaAsset(url:URL(fileURLWithPath:"/tmp/no-life-crop-source-\(UUID()).png"),kind:.image,duration:.init(value:1,timescale:1))
    await #expect(throws:CropGeometryError.self){try await VisualControls.sourceDimensions(asset:missing,canvas:canvas)}
}
