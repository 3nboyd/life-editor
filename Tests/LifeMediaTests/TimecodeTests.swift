import Testing
import Foundation
@preconcurrency import AVFoundation
import LifeCore
@testable import LifeMedia

@Test func timecodeFramesAlignRationallyAndFlagDayBoundaries() throws {
    let fd=RationalTime(value:1001,timescale:30000),flags=kCMTimeCodeFlag_DropFrame|kCMTimeCodeFlag_24HourMax
    var reference=TimecodeAccumulator(),other=TimecodeAccumulator()
    try reference.append(frameNumber:107892,at:.zero,frameDuration:fd,quanta:30,flags:flags)
    try reference.append(frameNumber:107922,at:fd.scaled(by:30),frameDuration:fd,quanta:30,flags:flags)
    try other.append(frameNumber:107952,at:.zero,frameDuration:fd,quanta:30,flags:flags)
    let a=try #require(reference.reference),b=try #require(other.reference)
    #expect(try b.alignment(relativeTo:a).offset==fd.scaled(by:60))
    #expect(try !b.alignment(relativeTo:a).requiresDayReview)
    var late=TimecodeAccumulator(),early=TimecodeAccumulator()
    try late.append(frameNumber:2589407,at:.zero,frameDuration:fd,quanta:30,flags:flags)
    try late.append(frameNumber:0,at:fd,frameDuration:fd,quanta:30,flags:flags)
    try early.append(frameNumber:0,at:.zero,frameDuration:fd,quanta:30,flags:flags)
    let midnight=try #require(early.reference).alignment(relativeTo:try #require(late.reference))
    #expect(midnight.offset==fd && midnight.requiresDayReview)
    #expect(throws:TimecodeError.self){try reference.append(frameNumber:108100,at:.init(value:2,timescale:1),frameDuration:fd,quanta:30,flags:flags)}
    var invalid=TimecodeAccumulator()
    #expect(throws:TimecodeError.self){try invalid.append(frameNumber:0,at:.zero,frameDuration:.init(value:1,timescale:30),quanta:30,flags:flags)}
}

@MainActor @Test(.enabled(if:ProcessInfo.processInfo.environment["LIFE_RUN_MEDIA_INTEGRATION"]=="1"))
func nativeTimecodeReaderDecodesBigEndian32And64BitTracks() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("life-timecode-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    func make(_ name:String,size:Int,frames:Int64)async throws->URL{
        let url=directory.appendingPathComponent(name+".mov"),writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        var format:CMTimeCodeFormatDescription?
        let subtype=size==4 ? kCMTimeCodeFormatType_TimeCode32:kCMTimeCodeFormatType_TimeCode64
        try #require(CMTimeCodeFormatDescriptionCreate(allocator:kCFAllocatorDefault,timeCodeFormatType:subtype,frameDuration:CMTime(value:1,timescale:30),frameQuanta:30,flags:kCMTimeCodeFlag_24HourMax,extensions:nil,formatDescriptionOut:&format)==noErr)
        let description=try #require(format)
        let input=AVAssetWriterInput(mediaType:.timecode,outputSettings:nil,sourceFormatHint:description)
        try #require(writer.canAdd(input));writer.add(input)
        try #require(writer.startWriting());writer.startSession(atSourceTime:.zero)
        var block:CMBlockBuffer?
        try #require(CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:size,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:size,flags:0,blockBufferOut:&block)==kCMBlockBufferNoErr)
        let data=try #require(block),bits=UInt64(bitPattern:frames)
        let bytes=(0..<size).map{UInt8(truncatingIfNeeded:bits >> ((size-1-$0)*8))}
        try #require(bytes.withUnsafeBytes{CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:data,offsetIntoDestination:0,dataLength:size)}==kCMBlockBufferNoErr)
        var timing=CMSampleTimingInfo(duration:CMTime(value:2,timescale:1),presentationTimeStamp:.zero,decodeTimeStamp:.invalid),sampleSize=size
        var buffer:CMSampleBuffer?
        try #require(CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:data,formatDescription:description,sampleCount:1,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&sampleSize,sampleBufferOut:&buffer)==noErr)
        let deadline=ContinuousClock.now.advanced(by:.seconds(5))
        while !input.isReadyForMoreMediaData{try #require(writer.status == .writing && ContinuousClock.now<deadline);try await Task.sleep(for:.milliseconds(5))}
        try #require(input.append(try #require(buffer)));input.markAsFinished();await writer.finishWriting()
        try #require(writer.status == .completed);return url
    }
    let a=try await make("32",size:4,frames:108000),b=try await make("64",size:8,frames:108150)
    let first=try #require(await TimecodeReader.shared.read(a)),second=try #require(await TimecodeReader.shared.read(b))
    #expect(first.origin == .init(value:3600,timescale:1))
    #expect(try second.alignment(relativeTo:first).offset == .init(value:5,timescale:1))
}
