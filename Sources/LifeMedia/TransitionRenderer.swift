import Foundation
import CoreImage
import LifeCore

/// Original deterministic transition graphs. Pair rendering precedes compositing
/// over the lower visual tracks, in both playback and offline output.
public enum TransitionRenderer {
    public static func image(from outgoing: CIImage, to incoming: CIImage,
                             transition: VideoTransition, progress: Double, canvas: CGRect) -> CIImage {
        let p = max(0, min(1, progress))
        if p <= 0 { return outgoing.cropped(to: canvas) }
        if p >= 1 { return incoming.cropped(to: canvas) }
        func mix(_ left: CIImage, _ right: CIImage) -> CIImage {
            left.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": right, "inputTime": p]).cropped(to: canvas)
        }
        func alpha(_ image: CIImage, _ value: Double) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: value)])
        }
        func translate(_ image: CIImage, _ fraction: Double) -> CIImage {
            let direction: CGPoint
            switch transition.direction {
            case 1: direction = CGPoint(x: -canvas.width, y: 0)
            case 2: direction = CGPoint(x: 0, y: -canvas.height)
            case 3: direction = CGPoint(x: 0, y: canvas.height)
            default: direction = CGPoint(x: canvas.width, y: 0)
            }
            return image.transformed(by: CGAffineTransform(translationX: direction.x * fraction, y: direction.y * fraction))
        }
        func scale(_ image: CIImage, _ factor: Double) -> CIImage {
            image.transformed(by: CGAffineTransform(translationX: -canvas.midX, y: -canvas.midY))
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                .transformed(by: CGAffineTransform(translationX: canvas.midX, y: canvas.midY))
        }
        func blurred(_ image: CIImage, _ radius: Double) -> CIImage {
            image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius]).cropped(to: canvas)
        }
        func solid(_ color: RGBAColor) -> CIImage {
            CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)).cropped(to: canvas)
        }
        let peak = sin(p * .pi)
        // Stable UUID bytes, never process-randomized Swift Hasher state.
        let seed = transition.id.uuidString.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) } % 1009
        var result: CIImage
        switch transition.kind {
        case .crossDissolve: result = mix(outgoing, incoming)
        case .fadeBlack, .fadeWhite, .dipColor:
            let color = transition.kind == .fadeWhite ? RGBAColor.white : transition.kind == .fadeBlack ? RGBAColor.black : transition.color
            let dip = solid(color)
            result = p < 0.5
                ? outgoing.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": dip, "inputTime": p * 2])
                : dip.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": incoming, "inputTime": (p - 0.5) * 2])
        case .push:
            result = translate(incoming, 1 - p).composited(over: translate(outgoing, -p))
        case .slide:
            result = translate(incoming, 1 - p).composited(over: outgoing)
        case .wipe:
            var region = canvas
            switch transition.direction {
            case 1: region.size.width *= p
            case 2: region.size.height *= p
            case 3: region.origin.y += canvas.height * (1 - p); region.size.height *= p
            default: region.origin.x += canvas.width * (1 - p); region.size.width *= p
            }
            result = incoming.cropped(to: region).composited(over: outgoing)
        case .zoom:
            result = alpha(scale(incoming, 0.6 + 0.4 * p), p).composited(over: alpha(scale(outgoing, 1 + p * 0.6), 1 - p))
        case .blur:
            result = mix(blurred(outgoing, p * 24), blurred(incoming, (1 - p) * 24))
        case .whipPan:
            let pair = translate(incoming, 1 - p).composited(over: translate(outgoing, -p))
            result = pair.clampedToExtent().applyingFilter("CIMotionBlur", parameters: ["inputRadius": peak * 32,
                "inputAngle": transition.direction > 1 ? Double.pi / 2 : 0])
        case .shake:
            let x = sin(p * 67 + Double(seed)) * canvas.width * 0.035 * peak
            let y = cos(p * 89 + Double(seed)) * canvas.height * 0.025 * peak
            result = mix(outgoing, incoming).transformed(by: CGAffineTransform(translationX: x, y: y))
        case .glitch:
            let pair = mix(outgoing, incoming)
            let offset = canvas.width * 0.035 * peak * sin(p * 113 + Double(seed))
            let red = pair.applyingFilter("CIColorMatrix", parameters: ["inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
                .transformed(by: CGAffineTransform(translationX: offset, y: 0))
            let green = pair.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            let blue = pair.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
                .transformed(by: CGAffineTransform(translationX: -offset, y: 0))
            result = red.applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": green])
                .applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": blue])
        case .flash:
            result = alpha(solid(.white), peak * 0.9).composited(over: mix(outgoing, incoming))
        case .lightLeak:
            let start = CGPoint(x: canvas.minX + canvas.width * (p * 2 - 0.5), y: canvas.midY)
            let leak = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(cgPoint: start),
                "inputPoint1": CIVector(x: start.x + canvas.width * 0.6, y: canvas.midY),
                "inputColor0": CIColor(red: 1, green: 0.35, blue: 0.06, alpha: peak * 0.65), "inputColor1": CIColor.clear])!.outputImage!
            result = leak.composited(over: mix(outgoing, incoming))
        }
        return result.cropped(to: canvas)
    }
}
