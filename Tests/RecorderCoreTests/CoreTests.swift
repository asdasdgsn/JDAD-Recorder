import XCTest
@testable import RecorderCore
final class CoreTests: XCTestCase {
    func testDeleteMiddlePreservesSourceTime() {
        var t = EditTimeline(kept: [.init(start: 0, end: 10)])
        t.delete(outputRange: .init(start: 3, end: 7))
        XCTAssertEqual(t.duration, 6)
        XCTAssertEqual(t.sourceTime(at: 3.5)!, 7.5)
        XCTAssertEqual(t.sourceTime(at: 3)!, 7)
        XCTAssertNil(t.sourceTime(at: -1))
    }
    func testRetainAcrossCutAndEmpty() {
        var t = EditTimeline(kept: [.init(start: 0,end: 2), .init(start: 6,end: 8)])
        t.retain(outputRange: .init(start: 1,end: 3))
        XCTAssertEqual(t.kept, [.init(start: 1,end: 2), .init(start: 6,end: 7)])
        t.delete(outputRange: .init(start: 0,end: 2))
        XCTAssertEqual(t.duration, 0)
    }
    func testClicksMergeAndEdgesRemainInBounds() {
        let samples = [PointerSample(time: 1,x: 0.99,y: 0.01,clicked: true), .init(time: 1.5,x: 0.95,y: 0.02,clicked: true)]
        let zooms = AutoZoomPlanner.plan(samples: samples, duration: 5)
        XCTAssertEqual(zooms.count, 1)
        let c = CameraEvaluator.evaluate(time: 1.5, segments: zooms, samples: samples)
        XCTAssertGreaterThan(c.scale, 1)
        XCTAssertLessThanOrEqual(c.centerX + 0.5/c.scale, 1.000001)
        XCTAssertGreaterThanOrEqual(c.centerY - 0.5/c.scale, -0.000001)
        XCTAssertEqual(AutoZoomPlanner.plan(samples: [],duration: 4).count, 0)
        XCTAssertEqual(CameraEvaluator.evaluate(time: 4.9,segments: zooms,samples: samples).scale,1)
    }
    func testMappingNegativeOriginAndChangedWindow() {
        XCTAssertEqual(PointerMapping.normalize(point: CGPoint(x:-960,y:540),contentRect: CGRect(x:-1920,y:0,width:1920,height:1080)), CGPoint(x:0.5,y:0.5))
        XCTAssertNil(PointerMapping.normalize(point: .zero, contentRect: CGRect(x:100,y:100,width:200,height:100)))
        XCTAssertEqual(PointerMapping.normalize(point: CGPoint(x:200,y:150),contentRect: CGRect(x:100,y:100,width:200,height:100)), CGPoint(x:0.5,y:0.5))
        XCTAssertNil(PointerMapping.normalize(point: .zero,contentRect: .zero))
    }
    func testProjectRejectsUnsafeAndInvalidMetadata() throws {
        var p = Project(duration: 10,sourceRelativePath: "media/original.mov")
        XCTAssertNoThrow(try p.validate())
        p.sourceRelativePath = "../secret.mov"
        XCTAssertThrowsError(try p.validate())
        p.sourceRelativePath = "media/original.mov"
        p.kept = [.init(start: 8,end: 11)]
        XCTAssertThrowsError(try p.validate())
        p.kept = [.init(start: 0,end: 10)]
        p.duration = .infinity
        XCTAssertThrowsError(try p.validate())
    }
    func testHistoryRestoresEdits() {
        var h = EditHistory()
        let p = Project(duration: 10,sourceRelativePath: "media/original.mov")
        var edited = p
        edited.kept = [.init(start: 2,end: 8)]
        h.record(p)
        let restored = h.undo(current: edited)
        XCTAssertEqual(restored?.kept, p.kept)
        XCTAssertEqual(h.redo(current: p)?.kept, edited.kept)
    }
}

extension CoreTests {
    func testLetterboxedWindowMappingUsesActualContentRectangle() {
        // A square window in a 1600x900 output occupies x=350...1250.
        let p = PointerMapping.normalize(point:CGPoint(x:100,y:100),contentRect:CGRect(x:100,y:100,width:900,height:900),destinationRect:CGRect(x:350,y:0,width:900,height:900),canvasSize:CGSize(width:1600,height:900))
        XCTAssertEqual(p?.x,0.21875)
        XCTAssertEqual(p?.y,0)
    }
    func testCameraTrackUsesSourceTimeAfterCut() {
        let z = ZoomSegment(start:6,end:8,centerX:0.8,centerY:0.5,scale:2,manual:true)
        let track = CameraTrack(segments:[z],samples:[])
        let timeline = EditTimeline(kept:[.init(start:0,end:2),.init(start:6,end:8)])
        let c = track.evaluate(time:timeline.sourceTime(at:2.5)!)
        XCTAssertEqual(c.scale,2)
        XCTAssertEqual(c.centerX,0.75)
        XCTAssertEqual(track.evaluate(time:2.5).scale,1)
    }
}

extension CoreTests {
    func testRejectsUnrepresentableProjectDuration() {
        let p = Project(duration:1e100,sourceRelativePath:"media/original.mov")
        XCTAssertThrowsError(try p.validate())
    }
    func testRetinaContentPointsConvertToOutputPixels() {
        let p = PointerMapping.normalize(point:CGPoint(x:480,y:270),contentRect:CGRect(x:0,y:0,width:960,height:540),destinationRect:CGRect(x:0,y:0,width:960,height:540),canvasSize:CGSize(width:1920,height:1080),surfaceScale:2)
        XCTAssertEqual(p,CGPoint(x:0.5,y:0.5))
    }
    @MainActor func testCompletionGateWaitsForExistingSaveAndCancellationCleanup() async {
        let gate = CompletionGate()
        let save = gate.begin(), export = gate.begin()
        var completed = false
        let waiter = Task { await gate.wait(); completed = true }
        await Task.yield()
        XCTAssertFalse(completed)
        gate.end(save)
        await Task.yield()
        XCTAssertFalse(completed)
        gate.end(export)
        await waiter.value
        XCTAssertTrue(completed)
    }
    func testCaptureAttemptRetainsEarlyFailureAndRejectsStaleCallback() {
        var attempt = CaptureAttempt()
        let first = attempt.begin()
        attempt.fail("disk full",generation:first)
        XCTAssertEqual(attempt.failure,"disk full")
        attempt.end()
        let second = attempt.begin()
        attempt.fail("late old error",generation:first)
        XCTAssertNil(attempt.failure)
        attempt.fail("source lost",generation:second)
        XCTAssertEqual(attempt.failure,"source lost")
    }
}

extension CoreTests {
    func testTenMinuteCameraTrackHasBoundedOutput() {
        var samples: [PointerSample] = []
        for i in 0..<36000 {
            let time = Double(i) / 60.0
            let x = Double(i % 600) / 600.0
            samples.append(PointerSample(time:time,x:x,y:0.5,clicked:(i % 60 == 0)))
        }
        let zooms = AutoZoomPlanner.plan(samples:samples,duration:600)
        let track = CameraTrack(segments:zooms,samples:samples)
        for i in 0..<18000 {
            let c = track.evaluate(time:Double(i)/30)
            XCTAssertTrue(c.scale.isFinite)
            XCTAssertGreaterThanOrEqual(c.centerX-0.5/c.scale,-0.000001)
            XCTAssertLessThanOrEqual(c.centerX+0.5/c.scale,1.000001)
        }
    }
}
