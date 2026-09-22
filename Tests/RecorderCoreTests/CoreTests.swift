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
