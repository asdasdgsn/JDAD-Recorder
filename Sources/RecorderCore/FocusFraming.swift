import Foundation

/// Top-left normalized source coordinates, shared by visual positioning and export.
public enum FocusFraming {
    public static func imageRect(image: CGSize, in container: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let ratio = min(container.width/image.width,container.height/image.height)
        let size = CGSize(width:image.width*ratio,height:image.height*ratio)
        return CGRect(x:(container.width-size.width)/2,y:(container.height-size.height)/2,width:size.width,height:size.height)
    }
    public static func point(_ point: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0,
              point.x >= imageRect.minX, point.x <= imageRect.maxX,
              point.y >= imageRect.minY, point.y <= imageRect.maxY else { return nil }
        return CGPoint(x:(point.x-imageRect.minX)/imageRect.width,y:(point.y-imageRect.minY)/imageRect.height)
    }
    public static func camera(center: CGPoint, scale: Double) -> CameraState {
        let scale = scale.isFinite ? min(3,max(1,scale)) : 1
        let half = 0.5/scale
        return CameraState(centerX:min(1-half,max(half,center.x.isFinite ? center.x : 0.5)),
                           centerY:min(1-half,max(half,center.y.isFinite ? center.y : 0.5)),scale:scale)
    }
    public static func crop(_ camera: CameraState) -> CGRect {
        CGRect(x:camera.centerX-0.5/camera.scale,y:camera.centerY-0.5/camera.scale,width:1/camera.scale,height:1/camera.scale)
    }
    public static func drag(_ initial: CameraState, translation: CGSize, in imageRect: CGRect) -> CameraState {
        guard imageRect.width > 0, imageRect.height > 0 else { return initial }
        return camera(center:CGPoint(x:initial.centerX+translation.width/imageRect.width,y:initial.centerY+translation.height/imageRect.height),scale:initial.scale)
    }
}
