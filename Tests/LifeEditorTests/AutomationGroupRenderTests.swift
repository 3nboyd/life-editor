import Testing
import AppKit
import AVFoundation
import LifeCore
import LifeMedia
@testable import LifeEditor
@MainActor @Test func automationGroupEditedVolumeAndOpacityPersistAndMatchSharedPreviewExport()async throws{
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("tone.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:96000)!
    buffer.frameLength=96000;for index in 0..<96000{let value=Float(sin(Double(index)*2 * .pi*440/48000))*0.2;buffer.floatChannelData![0][index]=value;buffer.floatChannelData![1][index]=value}
    do{let file=try AVAudioFile(forWriting:url,settings:format.settings);try file.write(from:buffer)}
    let two=RationalTime(value:2,timescale:1),three=RationalTime(value:3,timescale:1)
    let envelope=AutomationEnvelope(points:[.init(time:.init(value:3,timescale:4),value:0.5),.init(time:.init(value:5,timescale:4),value:1)])
    let initialEnvelope=AutomationEnvelope(points:[.init(time:.init(value:1,timescale:2),value:0.25),.init(time:.init(value:1,timescale:1),value:0.5)])
    let asset=MediaAsset(url:url,kind:.audio,duration:two),audioSource=Clip(assetID:asset.id,duration:two,volume:envelope),audioTarget=Clip(assetID:asset.id,start:three,duration:two,volume:initialEnvelope)
    let shape=GraphicContent.shape(.init(kind:.rectangle,rect:.init(x:0,y:0,width:1,height:1),fill:.init(red:1,green:0,blue:0),strokeWidth:0))
    let opacityReference=AutomationEnvelope(points:[.init(time:.init(value:3,timescale:4),value:0.5),.init(time:.init(value:5,timescale:4),value:0.75)])
    let pictureSource=Clip(duration:two,opacity:opacityReference,graphic:shape),pictureTarget=Clip(start:three,duration:two,opacity:initialEnvelope,graphic:shape)
    let document=ProjectDocument(sequence:Sequence(settings:ProjectSettings(width:64,height:64),tracks:[Track(name:"Music",kind:.audio,clips:[audioSource,audioTarget]),Track(name:"Picture",kind:.shape,clips:[pictureSource,pictureTarget])]),assets:[asset])
    let store=EditorStore();store.replace(document)
    for (target,lane) in [(audioTarget,AutomationLane.volume),(pictureTarget,AutomationLane.opacity)]{
        store.selection=target.id;store.automationLane=lane;store.selectAllVisibleAutomationPoints()
        let anchor=try #require(store.selectedVisibleAutomationPoints.first),before=store.document
        #expect(store.updateSelectedAutomationPoints(anchorID:anchor.id,sequenceTime:3.75,effectiveValue:0.5))
        let edited=try #require(store.selectedClip),actual=lane == .volume ? edited.volume:edited.opacity
        for tick in [1,2,4,6,7]{let time=RationalTime(value:Int64(tick),timescale:4);#expect(abs(actual.value(at:time)-(lane == .volume ? envelope:opacityReference).value(at:time))<0.0000001)}
        let after=store.document;store.undo();#expect(store.document==before);store.redo();#expect(store.document==after)
    }
    let package=directory.appendingPathComponent("Points.lifeedit");try ProjectPackage.write(store.document,to:package);let reopened=try ProjectPackage.read(from:package);#expect(reopened==store.document)
    let snapshot=ProjectSnapshot(document:reopened),pipeline=MediaPipeline(),prepared=try await pipeline.prepare(snapshot),preview=AVAssetImageGenerator(asset:prepared.playerItem.asset)
    preview.videoComposition=prepared.playerItem.videoComposition;preview.requestedTimeToleranceBefore = .zero;preview.requestedTimeToleranceAfter = .zero
    let a=try await preview.image(at:CMTime(value:1,timescale:2)).image,b=try await preview.image(at:CMTime(value:7,timescale:2)).image
    func pixel(_ image:CGImage)->[UInt8]{var values=[UInt8](repeating:0,count:4);values.withUnsafeMutableBytes{let context=CGContext(data:$0.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;context.draw(image,in:CGRect(x:-32,y:-32,width:64,height:64))};return values}
    #expect(pixel(a)==pixel(b))
    let source=PlaybackMeterSource(item:prepared.playerItem),first=try await PlaybackAudioMeter.read(source,at:.init(value:1,timescale:2)),second=try await PlaybackAudioMeter.read(source,at:.init(value:7,timescale:2))
    #expect(abs(first.frame.leftDBFS-second.frame.leftDBFS)<0.001)
    let exported=directory.appendingPathComponent("points.mov");try await pipeline.export(snapshot,to:exported,options:.init(format:.proRes))
    let output=AVURLAsset(url:exported),generator=AVAssetImageGenerator(asset:output)
    let decoded=try await generator.image(at:CMTime(value:7,timescale:2)).image,p=pixel(b),q=pixel(decoded)
    for channel in 0..<3{#expect(abs(Int(p[channel])-Int(q[channel]))<20)}
    let exportedSource=PlaybackMeterSource(item:AVPlayerItem(asset:output)),audio=try await PlaybackAudioMeter.read(exportedSource,at:.init(value:7,timescale:2))
    #expect(abs(audio.frame.leftDBFS-second.frame.leftDBFS)<0.3)
}
