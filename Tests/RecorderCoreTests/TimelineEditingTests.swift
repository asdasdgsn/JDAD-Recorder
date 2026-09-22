import XCTest
@testable import RecorderCore

final class TimelineEditingTests: XCTestCase {
    func testSplitPreservesFrameMappingAndRejectsBoundarySlivers() {
        var t = EditTimeline(kept:[.init(start:2,end:10)])
        XCTAssertTrue(t.split(at:3))
        XCTAssertEqual(t.kept,[.init(start:2,end:5),.init(start:5,end:10)])
        XCTAssertEqual(t.sourceTime(at:3.5),5.5)
        XCTAssertFalse(t.split(at:3))
        XCTAssertFalse(t.split(at:0.001))
        XCTAssertFalse(t.split(at:.nan))
        XCTAssertEqual(t.duration,8)
    }
    func testMoveClosesGapsAndMapsBothDirections() {
        var t = EditTimeline(kept:[.init(start:0,end:2),.init(start:2,end:5),.init(start:8,end:10)])
        XCTAssertTrue(t.moveClip(from:2,toBoundary:0))
        XCTAssertEqual(t.kept,[.init(start:8,end:10),.init(start:0,end:2),.init(start:2,end:5)])
        XCTAssertEqual(t.boundaries,[0,2,4,7])
        XCTAssertEqual(t.sourceTime(at:0.5),8.5)
        XCTAssertEqual(t.outputTime(at:0.5),2.5)
        XCTAssertTrue(t.moveClip(from:0,toBoundary:3))
        XCTAssertEqual(t.kept.last,.init(start:8,end:10))
        XCTAssertFalse(t.moveClip(from:2,toBoundary:3))
        XCTAssertFalse(t.moveClip(from:8,toBoundary:0))
    }
    func testReorderedProjectValidatesButOverlappingSourceDoesNot() throws {
        var p = Project(duration:10,sourceRelativePath:"media/original.mov")
        p.kept = [.init(start:8,end:10),.init(start:0,end:3)]
        XCTAssertNoThrow(try p.validate())
        p.kept.append(.init(start:1,end:2))
        XCTAssertThrowsError(try p.validate())
    }
    func testCutAfterReorderPreservesOutputOrder() {
        var t = EditTimeline(kept:[.init(start:8,end:10),.init(start:0,end:3)])
        t.delete(outputRange:.init(start:1,end:3))
        XCTAssertEqual(t.kept,[.init(start:8,end:9),.init(start:1,end:3)])
    }
    func testSnapUsesVisualToleranceAndFrameRounding() {
        XCTAssertEqual(TimelineSnap.resolve(2.04,targets:[2,4],tolerance:0.06,range:0...5).time,2)
        XCTAssertEqual(TimelineSnap.resolve(2.04,targets:[2,4],tolerance:0.01,range:0...5).time,61.0/30,accuracy:0.000001)
        XCTAssertNil(TimelineSnap.resolve(2.04,targets:[2],tolerance:0.01,range:0...5).target)
        XCTAssertEqual(TimelineSnap.resolve(-4,targets:[],tolerance:0.1,range:0...5).time,0)
    }
    func testResizeZoomClampsAtNeighborsAndRemainsEditableAfterReorder() throws {
        var p = Project(duration:10,sourceRelativePath:"media/original.mov")
        p.kept = [.init(start:6,end:10),.init(start:0,end:6)]
        let zoom = ZoomSegment(start:7,end:9,centerX:0.5,centerY:0.5)
        p.zooms = [.init(start:6,end:6.5,centerX:0.5,centerY:0.5),zoom]
        p = p.resizingZoom(zoom.id,inClip:0,edge:.start,toOutputTime:0)
        XCTAssertEqual(p.zooms.first(where:{$0.id == zoom.id})?.start,6.5)
        XCTAssertNoThrow(try p.validate())
        p = p.resizingZoom(zoom.id,inClip:0,edge:.end,toOutputTime:4)
        XCTAssertEqual(p.zooms.first(where:{$0.id == zoom.id})?.end,10)
    }
    func testResizeClippedZoomLeavesOtherClipTimingAndCameraUntouched() throws {
        var p = Project(duration:8,sourceRelativePath:"media/original.mov")
        p.kept = [.init(start:0,end:4),.init(start:4,end:8)]
        let z = ZoomSegment(start:2,end:6,centerX:0.7,centerY:0.5,scale:2,manual:true)
        p.zooms = [z]
        let before = CameraTrack(segments:p.zooms,samples:[]).evaluate(time:3.9)
        p = p.resizingZoom(z.id,inClip:1,edge:.start,toOutputTime:4.5)
        XCTAssertEqual(p.zooms.count,2)
        XCTAssertEqual(p.zooms.first?.start,2)
        XCTAssertEqual(p.zooms.first?.end,4)
        XCTAssertEqual(p.zooms.last?.start,4.5)
        XCTAssertEqual(CameraTrack(segments:p.zooms,samples:[]).evaluate(time:3.9),before)
        XCTAssertNoThrow(try p.validate())
    }
    func testHistoryRoundTripsSplitReorderAndResize() {
        let original = Project(duration:8,sourceRelativePath:"media/original.mov")
        var p = original, history = EditHistory()
        history.record(p)
        var t = p.timeline; _ = t.split(at:3); _ = t.moveClip(from:1,toBoundary:0); p.kept = t.kept
        let edited = p
        p = history.undo(current:p)!
        XCTAssertEqual(p,original)
        XCTAssertEqual(history.redo(current:p),edited)
    }
}

extension TimelineEditingTests {
    func testResizeDoesNotChangeAutomaticFollowOnUntouchedClip() {
        var p = Project(duration:8,sourceRelativePath:"media/original.mov")
        p.kept = [.init(start:0,end:4),.init(start:4,end:8)]
        let z = ZoomSegment(start:2,end:6,centerX:0.5,centerY:0.5,scale:2)
        p.zooms = [z]
        let samples = [PointerSample(time:2,x:0.5,y:0.5,clicked:true),.init(time:3.9,x:0.9,y:0.5,clicked:false),.init(time:4.1,x:0.1,y:0.5,clicked:false)]
        let before = CameraTrack(segments:p.zooms,samples:samples).evaluate(time:3.95)
        p = p.resizingZoom(z.id,inClip:1,edge:.start,toOutputTime:4.5)
        XCTAssertEqual(CameraTrack(segments:p.zooms,samples:samples).evaluate(time:3.95),before)
    }
}
