import Testing
import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers
import LifeCore
@testable import LifeMedia

@MainActor @Test func stillProbeAndThumbnailHonorOrientationAndBoundDecodeSize() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-still-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    func jpeg(_ width:Int,_ height:Int,orientation:Int,_ name:String)throws->URL{
        let context=try #require(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));context.fill(CGRect(x:0,y:0,width:width/2,height:height))
        context.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));context.fill(CGRect(x:width/2,y:0,width:width/2,height:height))
        let image=try #require(context.makeImage()),url=directory.appendingPathComponent(name+".jpg")
        let destination=try #require(CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyOrientation:orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination));return url
    }
    let rotated=try jpeg(80,40,orientation:6,"rotated")
    let dimensions=try #require(StillImage.dimensions(rotated))
    #expect(dimensions.width==40 && dimensions.height==80)
    let original=try #require(StillImage.original(rotated)),thumbnail=try #require(StillImage.thumbnail(rotated))
    #expect(original.extent.width==40 && original.extent.height==80)
    #expect(thumbnail.extent.width==40 && thumbnail.extent.height==80)
    let pipeline=MediaPipeline(),probe=try await pipeline.probe(rotated)
    #expect(probe.width==40 && probe.height==80 && probe.asset.kind == .image)
    let large=try jpeg(1024,512,orientation:1,"large")
    let bounded=try await pipeline.thumbnail(asset:MediaAsset(url:large,kind:.image,duration:.init(value:5,timescale:1)))
    #expect(bounded.width<=320 && bounded.height<=180)
    #expect(StillImage.dimensions(directory.appendingPathComponent("missing.jpg"))==nil)
}
