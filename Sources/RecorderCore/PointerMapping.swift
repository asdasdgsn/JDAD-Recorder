import Foundation
import CoreGraphics
public enum PointerMapping {
    public static func normalize(point: CGPoint, contentRect: CGRect, destinationRect: CGRect, canvasSize: CGSize) -> CGPoint? {
        guard let local = normalize(point:point,contentRect:contentRect),canvasSize.width > 0,canvasSize.height > 0,destinationRect.width > 0,destinationRect.height > 0 else { return nil }
        let result = CGPoint(x:(destinationRect.minX+local.x*destinationRect.width)/canvasSize.width,y:(destinationRect.minY+local.y*destinationRect.height)/canvasSize.height)
        guard result.x.isFinite, result.y.isFinite, (0...1).contains(result.x), (0...1).contains(result.y) else { return nil }
        return result
    }
    /// Inputs use the same top-left screen coordinate system. Output is normalized top-left content space.
    public static func normalize(point: CGPoint, contentRect: CGRect) -> CGPoint? {
        guard contentRect.width > 0, contentRect.height > 0,
              [point.x,point.y,contentRect.minX,contentRect.minY,contentRect.width,contentRect.height].allSatisfy({ $0.isFinite }),
              contentRect.contains(point) else { return nil }
        return CGPoint(x: (point.x-contentRect.minX)/contentRect.width, y: (point.y-contentRect.minY)/contentRect.height)
    }
}
