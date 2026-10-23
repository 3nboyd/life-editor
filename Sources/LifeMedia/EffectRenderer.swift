import Foundation
import CoreImage
import LifeCore

/// Original native looks; the same pure graph is used for thumbnails, playback and export.
enum EffectRenderer {
    private static let noise = ImmutableColorKernel(CIColorKernel(source: """
        kernel vec4 seededGrain(__sample s, float amount, float seed) {
            vec2 p = destCoord();
            float n = fract(sin(dot(p, vec2(12.9898,78.233)) + seed) * 43758.5453) - 0.5;
            return vec4(clamp(s.rgb + vec3(n * amount * s.a), 0.0, s.a), s.a);
        }
        """))
    // Original SDR tonal operators in the renderer's linear working space.
    // The neighborhood is edge-clamped before blurring; alpha is never changed.
    private static let tonal=ImmutableColorKernel(CIColorKernel(source:"""
        kernel vec4 lifeTonal(__sample s, __sample neighborhood, float value, float mode) {
            vec3 rgb = s.a > 0.000001 ? s.rgb / s.a : vec3(0.0);
            float y = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
            float delta = 0.0;
            if (mode < 0.5) {
                delta = value * 0.2 * smoothstep(0.45, 1.0, y);
            } else if (mode < 1.5) {
                delta = -value * 0.2 * (1.0 - smoothstep(0.0, 0.6, y));
            } else {
                vec3 localRGB = neighborhood.a > 0.000001 ? neighborhood.rgb / neighborhood.a : vec3(0.0);
                float mean = dot(localRGB, vec3(0.2126, 0.7152, 0.0722));
                float middle = 1.0 - abs(2.0 * clamp(y, 0.0, 1.0) - 1.0);
                delta = value * (0.16 * (1.0 - 2.0 * y) * middle + 0.4 * (y - mean));
            }
            return vec4(clamp(rgb + vec3(delta), 0.0, 1.0) * s.a, s.a);
        }
        """))
    static func apply(_ effects: [EffectInstance], to original: CIImage, time: RationalTime = .zero) -> CIImage {
        effects.filter(\.isEnabled).reduce(original) { input, effect in
            let strength = max(0, min(1, effect.strength))
            guard strength > 0 else { return input }
            var image = input
            let key = effect.stableID.components(separatedBy: ".").last ?? ""
            func controls(_ saturation: Double = 1, _ brightness: Double = 0, _ contrast: Double = 1) {
                image = image.applyingFilter("CIColorControls", parameters: ["inputSaturation": saturation, "inputBrightness": brightness, "inputContrast": contrast])
            }
            func warmth(_ kelvin: Double, _ tint: Double = 0) {
                image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: kelvin, y: tint)])
            }
            func grain(_ amount: Double) {
                let frame = effect.stableID == "life.filter.VHS" ? floor(time.seconds * 30) : 0
                let seed = Double(effect.seed % 1_000_003) + frame
                image = noise.value?.apply(extent: image.extent, arguments: [image, amount, seed]) ?? image
            }
            if effect.stableID.hasPrefix("life.adjust.") {
                let definition = NativeEffectRegistry.definition(for: effect.stableID)?.parameters.first { $0.name == "value" }
                let requested = effect.parameters["value"] ?? definition?.defaultValue ?? 0
                let value = max(definition?.range.lowerBound ?? -10000, min(definition?.range.upperBound ?? 10000, requested))
                switch key {
                case "exposure": image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": value])
                case "brightness": controls(1, value)
                case "contrast": controls(1, 0, value)
                case "highlights": image = image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": value])
                case "shadows": image = image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": value])
                case "whites", "blackPoint", "brilliance":
                    guard value != 0 else{return input}
                    let mode=key == "whites" ? 0.0:(key == "blackPoint" ? 1.0:2.0)
                    let radius=max(1,min(96,min(image.extent.width,image.extent.height)*0.015))
                    let neighborhood=key == "brilliance" ? image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:["inputRadius":radius]).cropped(to:image.extent):image
                    image=tonal.value?.apply(extent:image.extent,arguments:[image,neighborhood,value,mode]) ?? image
                case "saturation": controls(value)
                case "vibrance": image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": value])
                case "temperature": warmth(6500 + value)
                case "tint": warmth(6500, value)
                case "hue": image = image.applyingFilter("CIHueAdjust", parameters: ["inputAngle": value * .pi / 180])
                case "bloom": image = image.applyingFilter("CIBloom", parameters: ["inputIntensity": value, "inputRadius": 12])
                case "sharpen": image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": value])
                case "clarity": image = image.applyingFilter("CIUnsharpMask", parameters: ["inputIntensity": value, "inputRadius": 2.5])
                case "noiseReduction": image = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": value * 0.1, "inputSharpness": 0.4])
                case "vignette": image = image.applyingFilter("CIVignette", parameters: ["inputIntensity": value, "inputRadius": min(image.extent.width, image.extent.height) * 0.4])
                case "grain": grain(value)
                default: break
                }
            } else {
                switch key {
                case "grayscale": controls(0)
                case "highContrast": controls(0, -0.02, 1.4)
                case "LA": warmth(7600); controls(0.9, 0.025, 0.92)
                case "desert": warmth(8200, 7); controls(0.82, 0.01, 1.1)
                case "clean": controls(1.03, 0.015, 1.05)
                case "vivid": controls(1.35, 0.005, 1.1)
                case "softPortrait": controls(0.92, 0.025, 0.92); image = image.applyingFilter("CIBloom", parameters: ["inputIntensity": 0.12, "inputRadius": 4])
                case "cool": warmth(4900); controls(0.92, 0, 1.03)
                case "cinematic": warmth(5700, -6); controls(0.78, -0.015, 1.18)
                case "goldenHour": warmth(9000, 5); controls(1.05, 0.025, 1.04)
                case "fadedFilm": warmth(7000); controls(0.76, 0.035, 0.82); grain(max(0, min(1, effect.parameters["grain"] ?? 0.2)) * 0.18)
                case "Y2K": controls(1.22, 0.01, 1.22); image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.5])
                case "VHS":
                    warmth(7200, 5); controls(0.7, sin(floor(time.seconds * 30) * 0.71 + Double(effect.seed % 1000)) * 0.008, 0.9)
                    image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.45]).cropped(to: input.extent)
                    grain(max(0, min(1, effect.parameters["grain"] ?? 0.2)) * 0.25)
                case "disposable": warmth(7800, 4); controls(0.88, 0.015, 1.2); grain(max(0, min(1, effect.parameters["grain"] ?? 0.2)) * 0.25)
                case "neon": warmth(5000, 12); controls(1.4, -0.025, 1.2)
                case "mutedPastel": controls(0.62, 0.045, 0.83)
                default: return input
                }
            }
            return input.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": image, "inputTime": strength]).cropped(to: input.extent)
        }
    }

    static func transform(_ image: CIImage, visual: VisualTransform?, canvas: CGRect) -> CIImage {
        guard let v = visual else { return image }
        let e = image.extent
        let crop = CGRect(x: e.minX + e.width * v.cropLeft, y: e.minY + e.height * v.cropBottom,
                          width: e.width * (1 - v.cropLeft - v.cropRight), height: e.height * (1 - v.cropTop - v.cropBottom))
        return image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -canvas.midX, y: -canvas.midY))
            .transformed(by: CGAffineTransform(scaleX: v.scaleX * (v.flipHorizontal ? -1 : 1), y: v.scaleY * (v.flipVertical ? -1 : 1)))
            .transformed(by: CGAffineTransform(rotationAngle: v.rotationDegrees * .pi / 180))
            .transformed(by: CGAffineTransform(translationX: v.x * canvas.width, y: (1 - v.y) * canvas.height))
    }
}

/// A compiled Core Image kernel is immutable. Applying it creates independent
/// image graphs; no mutable filter or render context is shared through this box.
/// Older SDKs omit Sendable annotations for this immutable Objective-C API.
private final class ImmutableColorKernel: @unchecked Sendable {
    let value: CIColorKernel?
    init(_ value: CIColorKernel?) { self.value = value }
}
