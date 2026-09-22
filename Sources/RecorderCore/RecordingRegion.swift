import Foundation

/// Selection is in display-local logical points, measured from the top left.
public struct RecordingRegion: Sendable {
    public let sourceRect: CGRect
    public let globalRect: CGRect
    public let outputSize: CGSize
    public init(selection: CGRect, displayBounds: CGRect, pixelScale: Double) throws {
        guard [selection.minX,selection.minY,selection.width,selection.height,displayBounds.minX,displayBounds.minY,displayBounds.width,displayBounds.height,pixelScale].allSatisfy({$0.isFinite}),
              pixelScale > 0, pixelScale <= 8,
              selection.width >= 32, selection.height >= 32,
              selection.minX >= 0, selection.minY >= 0,
              selection.maxX <= displayBounds.width, selection.maxY <= displayBounds.height else {
            throw RecorderError.message("请选择屏幕内至少 32 × 32 的区域；显示器变化后请重新框选。")
        }
        sourceRect = selection
        globalRect = selection.offsetBy(dx:displayBounds.minX,dy:displayBounds.minY)
        let factor = min(1,3840/max(selection.width*pixelScale,selection.height*pixelScale))
        outputSize = CGSize(width:max(2,floor(selection.width*pixelScale*factor/2)*2),height:max(2,floor(selection.height*pixelScale*factor/2)*2))
    }
    public func normalizedPointer(_ point: CGPoint) -> CGPoint? { PointerMapping.normalize(point:point,contentRect:globalRect) }
    public static func selection(from start: CGPoint, to end: CGPoint, in size: CGSize) -> CGRect {
        let a = CGPoint(x:min(size.width,max(0,start.x.rounded())),y:min(size.height,max(0,start.y.rounded())))
        let b = CGPoint(x:min(size.width,max(0,end.x.rounded())),y:min(size.height,max(0,end.y.rounded())))
        return CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(b.x-a.x),height:abs(b.y-a.y))
    }
    public static func moving(_ rect: CGRect, by translation: CGSize, in size: CGSize) -> CGRect {
        CGRect(x:min(size.width-rect.width,max(0,(rect.minX+translation.width).rounded())),
               y:min(size.height-rect.height,max(0,(rect.minY+translation.height).rounded())),
               width:rect.width,height:rect.height)
    }
}
