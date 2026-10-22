import Foundation

public struct CropSize:Equatable,Sendable {
    public var width:Double
    public var height:Double
    public init(width:Double,height:Double){self.width=width;self.height=height}
    public var isValid:Bool{width.isFinite && height.isFinite && width>0 && height>0}
}
public enum CropAspect:String,CaseIterable,Sendable {
    case free="Free",landscape="16:9",portrait="9:16",square="1:1",feed="4:5"
    public var ratio:Double?{switch self{case .free:nil;case .landscape:16.0/9;case .portrait:9.0/16;case .square:1;case .feed:4.0/5}}
}
public enum CropFitMode:Sendable {case fit,fill}
public enum CropGeometryError:LocalizedError {
    case dimensions,transform,scale
    public var errorDescription:String?{switch self{case .dimensions:"Source dimensions are unavailable.";case .transform:"The crop is invalid.";case .scale:"This crop exceeds the supported transform range."}}
}
/// Matches the shared renderer: crop the oriented, aspect-fitted source first;
/// flip and scale about the canvas center, rotate counterclockwise, then position.
public enum CropGeometry {
    /// A preset chooses the largest source rectangle of that ratio. Retains the
    /// existing crop center wherever the full rectangle fits, otherwise clamps it.
    /// Free preserves the rectangle and leaves individual edges editable.
    public static func applying(_ aspect:CropAspect,to visual:VisualTransform,source:CropSize)throws->VisualTransform {
        guard source.isValid else{throw CropGeometryError.dimensions}
        guard visual.isValid else{throw CropGeometryError.transform}
        guard let ratio=aspect.ratio else{return visual}
        let width=min(1,(source.height/source.width)*ratio)
        let height=min(1,(source.width/source.height)/ratio)
        guard width.isFinite,height.isFinite,width>0,height>0 else{throw CropGeometryError.dimensions}
        let centerX=min(1-width/2,max(width/2,(visual.cropLeft+1-visual.cropRight)/2))
        let centerY=min(1-height/2,max(height/2,(visual.cropTop+1-visual.cropBottom)/2))
        var result=visual
        result.cropLeft=max(0,centerX-width/2);result.cropRight=max(0,1-centerX-width/2)
        result.cropTop=max(0,centerY-height/2);result.cropBottom=max(0,1-centerY-height/2)
        guard result.isValid else{throw CropGeometryError.transform};return result
    }
    public static func resettingCrop(in visual:VisualTransform)->VisualTransform {
        var result=visual;result.cropLeft=0;result.cropRight=0;result.cropTop=0;result.cropBottom=0;return result
    }
    /// Fit contains the rotated crop. Fill covers all four canvas corners. Both
    /// use uniform scale, recenter the crop, retain rotation/flips, and never resize
    /// the project. Unsupported extreme crops fail instead of falsely claiming fill.
    public static func placing(_ visual:VisualTransform,source:CropSize,canvas:CropSize,mode:CropFitMode)throws->VisualTransform {
        guard source.isValid,canvas.isValid else{throw CropGeometryError.dimensions}
        guard visual.isValid else{throw CropGeometryError.transform}
        let initial=min(canvas.width/source.width,canvas.height/source.height)
        let fittedWidth=source.width*initial,fittedHeight=source.height*initial
        let width=fittedWidth*(1-visual.cropLeft-visual.cropRight)
        let height=fittedHeight*(1-visual.cropTop-visual.cropBottom)
        let radians=visual.rotationDegrees.truncatingRemainder(dividingBy:360)*Double.pi/180
        let cosine=cos(radians),sine=sin(radians),c=abs(cosine),s=abs(sine)
        let scale:Double
        switch mode {
        case .fit:scale=min(canvas.width/(width*c+height*s),canvas.height/(width*s+height*c))
        case .fill:scale=max((canvas.width*c+canvas.height*s)/width,(canvas.width*s+canvas.height*c)/height)
        }
        guard scale.isFinite,(0.001...100).contains(scale) else{throw CropGeometryError.scale}
        let dx=fittedWidth*(visual.cropLeft-visual.cropRight)/2*scale*(visual.flipHorizontal ? -1:1)
        let dy=fittedHeight*(visual.cropBottom-visual.cropTop)/2*scale*(visual.flipVertical ? -1:1)
        var result=visual;result.scaleX=scale;result.scaleY=scale
        result.x=0.5-(dx*cosine-dy*sine)/canvas.width
        result.y=0.5+(dx*sine+dy*cosine)/canvas.height
        guard result.isValid else{throw CropGeometryError.scale};return result
    }
    public static func straightenComponents(_ rotation:Double)->(base:Double,angle:Double) {
        guard rotation.isFinite else{return (0,0)}
        let base=(rotation/90).rounded()*90
        return (base,rotation-base)
    }
}
