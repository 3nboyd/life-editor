import Foundation
import CoreImage
import CoreText
import CryptoKit
import LifeCore

/// Immutable title bitmaps are shared by preview/export. Typewriter reveals
/// whole graphemes in the full Core Text layout, so existing glyphs never jump.
enum TitleRenderer {
    private static let cache = TitleBitmapCache()
    static func image(_ title: TitleContent, size: CGSize, visibleCharacters: Int? = nil) -> CIImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 16384, size.height <= 16384, size.width * size.height <= 33_554_432 else { return nil }
        let count = visibleCharacters.map { max(0, min(title.text.count, $0)) }
        if count == 0 { return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size)) }
        var appearance = title; appearance.animation = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(appearance) else { return nil }
        data.append(Data("|\(size.width)x\(size.height)|\(count.map(String.init) ?? "full")".utf8))
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let image = cache.get(key) { return image }
        guard let image = rasterize(title, size: size, visibleCharacters: count) else { return nil }
        cache.put(image, key: key, cost: Int(size.width * size.height * 4))
        return image
    }
    static func animated(_ image: CIImage, title: TitleContent, localTime: RationalTime, canvas: CGRect) -> CIImage {
        guard let animation = title.animation else { return image }
        let elapsed = (try? animation.elapsedTime(at: localTime).seconds) ?? 0
        let p = max(0, min(1, elapsed / animation.duration))
        if p >= 1 { return image }
        if p <= 0 { return CIImage(color: .clear).cropped(to: canvas) }
        if animation.kind == .typewriter {
            return self.image(title, size: canvas.size, visibleCharacters: Int(floor(Double(title.text.count) * p))) ?? CIImage(color: .clear).cropped(to: canvas)
        }
        let eased = p * p * (3 - 2 * p)
        var opacity = eased
        var scale = 1.0
        var offset = CGPoint.zero
        switch animation.kind {
        case .fade: break
        case .slide:
            let distance = 1 - eased
            switch animation.direction {
            case 1: offset.x = -canvas.width * 0.16 * distance
            case 2: offset.y = -canvas.height * 0.16 * distance
            case 3: offset.y = canvas.height * 0.16 * distance
            default: offset.x = canvas.width * 0.16 * distance
            }
        case .scale: scale = 0.7 + eased * 0.3
        case .pop:
            let x = p - 1
            let back = 1 + 2.70158 * x * x * x + 1.70158 * x * x
            scale = 0.6 + back * 0.4; opacity = min(1, p * 4)
        case .bounce:
            let spring = 1 - exp(-6 * p) * cos(4 * .pi * p)
            scale = 0.8 + spring * 0.2
            offset.y = -canvas.height * 0.08 * (1 - spring); opacity = min(1, p * 4)
        case .typewriter: break
        }
        let style = title.style ?? TitleStyle()
        let anchor = CGPoint(x: style.x * canvas.width, y: (1 - style.y) * canvas.height)
        return image.transformed(by: CGAffineTransform(translationX: -anchor.x, y: -anchor.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: anchor.x + offset.x, y: anchor.y + offset.y))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
    }
    private static func rasterize(_ title: TitleContent, size: CGSize, visibleCharacters: Int?) -> CIImage? {
        // Core Text renders to a stable bitmap shared by preview and export.
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let style = title.style ?? TitleStyle()
        func color(_ value: RGBAColor) -> CGColor { CGColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha) }
        let font = CTFontCreateWithName((style.fontName ?? "Helvetica-Bold") as CFString, title.fontSize, nil)
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) {
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: $0)
            return CTParagraphStyleCreate(&setting, 1)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(style.color),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
        if style.outlineWidth > 0 {
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -style.outlineWidth * 100 / title.fontSize
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = color(style.outlineColor)
        }
        let text = NSAttributedString(string: title.text, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: size.width * 0.9, height: size.height * 0.9), nil)
        let padding = max(2, title.fontSize * 0.25)
        let bounds = CGRect(x: style.x * size.width - measured.width / 2 - padding,
                            y: (1 - style.y) * size.height - measured.height / 2 - padding,
                            width: ceil(measured.width) + padding * 2, height: ceil(measured.height) + padding * 2)
        context.setFillColor(color(style.background))
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: min(bounds.height, bounds.width) * style.cornerRadius,
                               cornerHeight: min(bounds.height, bounds.width) * style.cornerRadius, transform: nil))
        context.fillPath()
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: bounds.insetBy(dx: padding, dy: padding), transform: nil), nil)
        if let count = visibleCharacters, count < title.text.count {
            let limit = title.text.prefix(count).utf16.count
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            let origin = bounds.insetBy(dx: padding, dy: padding).origin
            for (index, line) in lines.enumerated() {
                context.textPosition = CGPoint(x: origin.x + origins[index].x, y: origin.y + origins[index].y)
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let count = CTRunGetGlyphCount(run)
                    var indices = [CFIndex](repeating: 0, count: count)
                    CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                    var start: Int?
                    for glyph in 0...count {
                        let visible = glyph < count && indices[glyph] < limit
                        if visible && start == nil { start = glyph }
                        if !visible, let begin = start {
                            context.textMatrix = .identity
                            context.textPosition = CGPoint(x: origin.x + origins[index].x, y: origin.y + origins[index].y)
                            CTRunDraw(run, context, CFRange(location: begin, length: glyph - begin)); start = nil
                        }
                    }
                }
            }
        } else { CTFrameDraw(frame, context) }
        return context.makeImage().map(CIImage.init(cgImage:))
    
    }
}

/// Strict 64MB/128-entry LRU. Entries are immutable Core Image/CGImage bitmaps;
/// a lock protects only the dictionary, never a shared mutable drawing context.
private final class TitleBitmapCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: (CIImage, Int)] = [:]
    private var order: [String] = []
    private var cost = 0
    func get(_ key: String) -> CIImage? {
        lock.withLock {
            guard let value = values[key] else { return nil }
            order.removeAll { $0 == key }; order.append(key); return value.0
        }
    }
    func put(_ image: CIImage, key: String, cost bytes: Int) {
        guard bytes <= 64_000_000 else { return }
        lock.withLock {
            if let old = values.removeValue(forKey: key) { cost -= old.1; order.removeAll { $0 == key } }
            while cost + bytes > 64_000_000 || order.count >= 128 {
                let oldest = order.removeFirst()
                if let value = values.removeValue(forKey: oldest) { cost -= value.1 }
            }
            values[key] = (image, bytes); order.append(key); cost += bytes
        }
    }
}
