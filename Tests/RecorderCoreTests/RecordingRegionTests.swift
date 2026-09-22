import XCTest
@testable import RecorderCore

final class RecordingRegionTests: XCTestCase {
    func testRetinaCropUsesLocalPointsButProducesPixels() throws {
        let region = try RecordingRegion(selection:CGRect(x:120,y:80,width:640,height:360),displayBounds:CGRect(x:0,y:0,width:1512,height:982),pixelScale:2)
        XCTAssertEqual(region.sourceRect,CGRect(x:120,y:80,width:640,height:360))
        XCTAssertEqual(region.outputSize,CGSize(width:1280,height:720))
        XCTAssertEqual(region.normalizedPointer(CGPoint(x:440,y:260)),CGPoint(x:0.5,y:0.5))
        XCTAssertNil(region.normalizedPointer(CGPoint(x:100,y:260)))
    }
    func testSecondaryScreenWithNegativeOriginUsesSameTopLeftCoordinates() throws {
        let region = try RecordingRegion(selection:CGRect(x:100,y:150,width:600,height:400),displayBounds:CGRect(x:-1440,y:-300,width:1440,height:900),pixelScale:1)
        XCTAssertEqual(region.globalRect,CGRect(x:-1340,y:-150,width:600,height:400))
        XCTAssertEqual(region.normalizedPointer(CGPoint(x:-1040,y:50)),CGPoint(x:0.5,y:0.5))
        XCTAssertEqual(region.sourceRect.minX,100)
    }
    func testRejectsTinyOutsideOrInvalidRegion() {
        let bounds = CGRect(x:0,y:0,width:1000,height:800)
        for rect in [CGRect(x:1,y:1,width:1,height:20),CGRect(x:-10,y:10,width:100,height:100),CGRect(x:900,y:700,width:101,height:100),CGRect(x:0,y:0,width:Double.nan,height:100)] {
            XCTAssertThrowsError(try RecordingRegion(selection:rect,displayBounds:bounds,pixelScale:2))
        }
        XCTAssertThrowsError(try RecordingRegion(selection:CGRect(x:0,y:0,width:200,height:100),displayBounds:bounds,pixelScale:0))
    }
    func testOutputIsEvenAndCappedWithoutUsingFullScreenSize() throws {
        let region = try RecordingRegion(selection:CGRect(x:0,y:0,width:3001,height:2001),displayBounds:CGRect(x:0,y:0,width:4000,height:3000),pixelScale:2)
        XCTAssertEqual(region.outputSize.width,3840)
        XCTAssertEqual(Int(region.outputSize.height)%2,0)
        XCTAssertEqual(region.outputSize.width/region.outputSize.height,3001.0/2001.0,accuracy:0.002)
    }
    func testReverseDragClampsToScreenEdges() {
        let rect = RecordingRegion.selection(from:CGPoint(x:700,y:500),to:CGPoint(x:-20,y:80),in:CGSize(width:800,height:600))
        XCTAssertEqual(rect,CGRect(x:0,y:80,width:700,height:420))
    }
    func testFractionalDragToDisplayEdgeNeverExceedsBounds() {
        let rect = RecordingRegion.selection(from:CGPoint(x:10.5,y:10.5),to:CGPoint(x:100,y:100),in:CGSize(width:100,height:100))
        XCTAssertEqual(rect,CGRect(x:11,y:11,width:89,height:89))
        XCTAssertNoThrow(try RecordingRegion(selection:rect,displayBounds:CGRect(x:0,y:0,width:100,height:100),pixelScale:2))
    }
    func testMovingAtFractionalCoordinatesDoesNotGrowRegion() {
        let initial = CGRect(x:120,y:80,width:640,height:360)
        let result = RecordingRegion.moving(initial,by:CGSize(width:0.5,height:0.5),in:CGSize(width:1000,height:800))
        XCTAssertEqual(result.size,initial.size)
        let edge = RecordingRegion.moving(initial,by:CGSize(width:999,height:999),in:CGSize(width:1000,height:800))
        XCTAssertEqual(edge,CGRect(x:360,y:440,width:640,height:360))
    }
}
