import Foundation
import Testing
import AppKit
import SwiftUI
import LifeCore
@testable import LifeEditor
@Test func sharedColorHSVAndHexRoundtripWithAlpha() throws {
    let original=RGBAColor(red:0.2,green:0.6,blue:0.8,alpha:0.35)
    let hsv=try #require(ColorConversion.hsv(original)),back=try #require(ColorConversion.rgb(hsv))
    #expect(abs(back.red-original.red)<1e-12);#expect(abs(back.green-original.green)<1e-12);#expect(abs(back.blue-original.blue)<1e-12);#expect(back.alpha == original.alpha)
    #expect(ColorConversion.rgb(HSVColor(hue:0,saturation:1,value:1)) == RGBAColor(red:1,green:0,blue:0))
    #expect(ColorConversion.rgb(HSVColor(hue:1,saturation:1,value:1)) == RGBAColor(red:1,green:0,blue:0))
    #expect(ColorConversion.hex(.white) == "#FFFFFFFF")
    #expect(ColorConversion.hex(.black,includeAlpha:false) == "#000000")
    #expect(ColorConversion.parseHex("#0f08") == RGBAColor(red:0,green:1,blue:0,alpha:136.0/255))
    #expect(ColorConversion.parseHex("abc") == RGBAColor(red:170.0/255,green:187.0/255,blue:204.0/255))
    let encoded=try #require(ColorConversion.hex(original))
    let quantized=try #require(ColorConversion.parseHex(encoded))
    #expect(abs(quantized.alpha-original.alpha)<=0.5/255)
}
@Test func sharedColorConversionRejectsInvalidDigitsAndNumericBounds() {
    for text in ["","#","#12","#12345","#1234567","#GG0000","#123456789","-FFFFFF","##FFFFFF"] { #expect(ColorConversion.parseHex(text) == nil) }
    #expect(ColorConversion.hsv(RGBAColor(red:.nan,green:0,blue:0)) == nil)
    #expect(ColorConversion.hex(RGBAColor(red:1.1,green:0,blue:0)) == nil)
    #expect(ColorConversion.rgb(HSVColor(hue:-0.1,saturation:1,value:1)) == nil)
    #expect(ColorConversion.rgb(HSVColor(hue:0,saturation:.infinity,value:1)) == nil)
    #expect(ColorConversion.rgb(HSVColor(hue:0,saturation:1,value:1,alpha:2)) == nil)
}
@MainActor @Test func sharedColorSwatchesPersistDeduplicateAndStayBounded() throws {
    let suite="LifeEditor.ColorTests."+UUID().uuidString,defaults=try #require(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    let library=ColorSwatchLibrary(defaults:defaults)
    for index in 0..<20 { let color=RGBAColor(red:Double(index)/20,green:0.4,blue:0.7,alpha:0.8);library.save(color) }
    #expect(library.recent.count == 12);#expect(library.saved.count == 16)
    let latest=try #require(library.recent.first);library.remember(latest);library.save(latest)
    #expect(library.recent.count == 12);#expect(library.saved.count == 16)
    let restored=ColorSwatchLibrary(defaults:defaults)
    #expect(restored.recent == library.recent);#expect(restored.saved == library.saved)
    restored.remove(latest);#expect(restored.saved.count == 15)
    #expect(ColorSwatchLibrary(defaults:defaults).saved.count == 15)
}
@MainActor @Test func sharedColorPopoverFitsCompactInspectorAndBindingEditsUndo() throws {
    _ = NSApplication.shared
    let suite="LifeEditor.ColorLayoutTests."+UUID().uuidString,defaults=try #require(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    let store=EditorStore(),clip=Clip(duration:.init(value:3,timescale:1),title:TitleContent(text:"Color"))
    store.replace(ProjectDocument(sequence:Sequence(tracks:[Track(name:"Title",kind:.title,clips:[clip])])));store.selection=clip.id
    let before=store.document
    let color=Binding<RGBAColor>(get:{store.selectedClip?.title?.style?.color ?? .white},set:{value in store.editSelected{clip in var style=clip.title?.style ?? .init();style.color=value;clip.title?.style=style}})
    let host=NSHostingView(rootView:ColorPopover(color:color,store:store,sample:{},library:ColorSwatchLibrary(defaults:defaults)).preferredColorScheme(.dark))
    host.frame=NSRect(x:0,y:0,width:280,height:500);host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width<=280);#expect(host.fittingSize.height<=500)
    let bitmap=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
    let png=try #require(bitmap.representation(using:.png,properties:[:]))
    try png.write(to:URL(fileURLWithPath:"/tmp/life-editor-shared-color.png"))
    color.wrappedValue=try #require(ColorConversion.parseHex("#33669980"))
    #expect(store.selectedClip?.title?.style?.color.alpha == 128.0/255)
    store.undo();#expect(store.document == before)
}
