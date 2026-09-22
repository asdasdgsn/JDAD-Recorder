import XCTest
@testable import RecorderCore

final class FocusFramingTests: XCTestCase {
    func testWideVideoUsesActualImageBoundsAndIgnoresLetterbox() {
        let frame = FocusFraming.imageRect(image:CGSize(width:1920,height:1080),in:CGSize(width:800,height:600))
        XCTAssertEqual(frame,CGRect(x:0,y:75,width:800,height:450))
        XCTAssertNil(FocusFraming.point(CGPoint(x:400,y:30),in:frame))
        XCTAssertEqual(FocusFraming.point(CGPoint(x:600,y:187.5),in:frame),CGPoint(x:0.75,y:0.25))
    }
    func testPortraitImageAndTopLeftCoordinates() {
        let frame = FocusFraming.imageRect(image:CGSize(width:1080,height:1920),in:CGSize(width:600,height:600))
        XCTAssertEqual(frame.width,337.5)
        XCTAssertEqual(FocusFraming.point(CGPoint(x:frame.minX,y:0),in:frame),.zero)
        XCTAssertNil(FocusFraming.point(CGPoint(x:1,y:300),in:frame))
    }
    func testCropStaysInsideSourceAndMatchesRenderedCamera() {
        let camera = FocusFraming.camera(center:CGPoint(x:0.99,y:0.01),scale:2)
        XCTAssertEqual(camera,CameraState(centerX:0.75,centerY:0.25,scale:2))
        XCTAssertEqual(FocusFraming.crop(camera),CGRect(x:0.5,y:0,width:0.5,height:0.5))
        let zoom = ZoomSegment(start:0,end:4,centerX:camera.centerX,centerY:camera.centerY,scale:2,manual:true)
        XCTAssertEqual(CameraEvaluator.evaluate(time:2,segments:[zoom],samples:[]),camera)
        XCTAssertEqual(FocusFraming.camera(center:CGPoint(x:0.99,y:0),scale:1),CameraState())
    }
    func testDragPreservesGrabOffsetAndClampsAtEdge() {
        let rect = CGRect(x:0,y:75,width:800,height:450)
        let origin = CameraState(centerX:0.5,centerY:0.5,scale:2)
        XCTAssertEqual(FocusFraming.drag(origin,translation:CGSize(width:80,height:-45),in:rect),CameraState(centerX:0.6,centerY:0.4,scale:2))
        XCTAssertEqual(FocusFraming.drag(origin,translation:CGSize(width:2000,height:2000),in:rect),CameraState(centerX:0.75,centerY:0.75,scale:2))
    }
}
