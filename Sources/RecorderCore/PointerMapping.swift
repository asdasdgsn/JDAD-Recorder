import Foundation
import CoreGraphics
public enum PointerMapping {
    /// Inputs use the same top-left screen coordinate system. Output is normalized top-left content space.
    public static func normalize(point: CGPoint, contentRect: CGRect) -> CGPoint? {
        guard contentRect.width > 0, contentRect.height > 0,
              [point.x,point.y,contentRect.minX,contentRect.minY,contentRect.width,contentRect.height].allSatisfy({ $0.isFinite }),
              contentRect.contains(point) else { return nil }
        return CGPoint(x: (point.x-contentRect.minX)/contentRect.width, y: (point.y-contentRect.minY)/contentRect.height)
    }
}
