import CoreImage
import LifeCore

/// Runs inside the same linear working graph for clips and adjustment layers.
/// Every operator preserves premultiplied alpha and uses no random or frame state.
enum AdvancedColorRenderer {
    private final class Kernel:@unchecked Sendable {
        let value:CIColorKernel?
        init(_ source:String){value=CIColorKernel(source:source)}
    }
    private static let curves=Kernel("""
        float curve(float x, vec4 p, float end) {
            float v = clamp(x, 0.0, 1.0) * 4.0;
            if (v < 1.0) return mix(p.x,p.y,v);
            if (v < 2.0) return mix(p.y,p.z,v-1.0);
            if (v < 3.0) return mix(p.z,p.w,v-2.0);
            return mix(p.w,end,v-3.0);
        }
        kernel vec4 lifeCurve(__sample s, vec4 points, float end, float channel) {
            vec3 rgb = s.a > 0.000001 ? s.rgb / s.a : vec3(0.0);
            if (channel < 0.5) rgb = vec3(curve(rgb.r,points,end),curve(rgb.g,points,end),curve(rgb.b,points,end));
            else if (channel < 1.5) rgb.r = curve(rgb.r,points,end);
            else if (channel < 2.5) rgb.g = curve(rgb.g,points,end);
            else rgb.b = curve(rgb.b,points,end);
            return vec4(rgb * s.a,s.a);
        }
        """)
    private static let levels=Kernel("""
        kernel vec4 lifeLevels(__sample s, float black, float white, float gamma) {
            vec3 rgb = s.a > 0.000001 ? s.rgb / s.a : vec3(0.0);
            rgb = pow(clamp((rgb-vec3(black))/(white-black),0.0,1.0),vec3(1.0/gamma));
            return vec4(rgb * s.a,s.a);
        }
        """)
    private static let hsl=Kernel("""
        vec3 toHSL(vec3 rgb) {
            float hi = max(rgb.r,max(rgb.g,rgb.b));
            float lo = min(rgb.r,min(rgb.g,rgb.b));
            float d = hi-lo;
            float l = (hi+lo)*0.5;
            float sat = d > 0.000001 ? d/max(0.000001,1.0-abs(2.0*l-1.0)) : 0.0;
            float h = 0.0;
            if (d > 0.000001) {
                if (hi == rgb.r) h = (rgb.g-rgb.b)/d;
                else if (hi == rgb.g) h = (rgb.b-rgb.r)/d+2.0;
                else h = (rgb.r-rgb.g)/d+4.0;
                h = fract(h/6.0+1.0);
            }
            return vec3(h,sat,l);
        }
        vec3 fromHSL(vec3 hsl) {
            vec3 k = mod(vec3(0.0,8.0,4.0)+hsl.x*12.0,12.0);
            float a = hsl.y*min(hsl.z,1.0-hsl.z);
            return hsl.z-a*max(vec3(-1.0),min(min(k-3.0,9.0-k),vec3(1.0)));
        }
        kernel vec4 lifeSelectiveHSL(__sample s, __sample original, float center, float hue, float saturation, float lightness) {
            vec3 rgb = s.a > 0.000001 ? s.rgb / s.a : vec3(0.0);
            vec3 source = original.a > 0.000001 ? original.rgb / original.a : vec3(0.0);
            vec3 selected = toHSL(clamp(source,0.0,1.0));
            float distance = abs(selected.x-center);
            distance = min(distance,1.0-distance);
            float weight = (1.0-smoothstep(0.0,1.0/6.0,distance))*smoothstep(0.0,0.1,selected.y);
            vec3 value = toHSL(clamp(rgb,0.0,1.0));
            value.x = fract(value.x+hue*weight/360.0+1.0);
            value.y = clamp(value.y*(1.0+saturation*weight),0.0,1.0);
            value.z = clamp(value.z+lightness*weight*0.5,0.0,1.0);
            return vec4(fromHSL(value)*s.a,s.a);
        }
        """)
    static func apply(_ effect:EffectInstance,to input:CIImage)->CIImage {
        var image=input
        switch effect.stableID {
        case "life.adjust.curves":
            for (index,channel) in AdvancedColor.curveChannels.enumerated() {
                let p=AdvancedColor.curve(effect,channel:channel)
                guard p != [0,0.25,0.5,0.75,1] else{continue}
                image=curves.value?.apply(extent:input.extent,arguments:[image,CIVector(x:p[0],y:p[1],z:p[2],w:p[3]),p[4],Double(index)]) ?? image
            }
        case "life.adjust.levels":
            let black=effect.parameters["black"] ?? 0,white=effect.parameters["white"] ?? 1,gamma=effect.parameters["gamma"] ?? 1
            guard black != 0 || white != 1 || gamma != 1,black<white else{return image}
            image=levels.value?.apply(extent:input.extent,arguments:[image,black,white,gamma]) ?? image
        case "life.adjust.hsl":
            for (index,band) in AdvancedColor.hueBands.enumerated() {
                let hue=effect.parameters[band+"Hue"] ?? 0,saturation=effect.parameters[band+"Saturation"] ?? 0,lightness=effect.parameters[band+"Lightness"] ?? 0
                guard hue != 0 || saturation != 0 || lightness != 0 else{continue}
                image=hsl.value?.apply(extent:input.extent,arguments:[image,input,Double(index)/6,hue,saturation,lightness]) ?? image
            }
        default:break
        }
        return image
    }
}
