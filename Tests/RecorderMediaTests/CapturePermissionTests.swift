import XCTest
import ScreenCaptureKit
@testable import RecorderMedia

final class CapturePermissionTests: XCTestCase {
    func testTCCDenialExplainsEnabledButStalePermissionAndCurrentApp() {
        let error = NSError(domain:SCStreamErrorDomain,code:SCStreamError.Code.userDeclined.rawValue)
        let message = CapturePermissionGuidance.message(for:error,applicationPath:"/Applications/Demo Recorder.app")
        XCTAssertTrue(message.contains("已经开启"))
        XCTAssertTrue(message.contains("退出"))
        XCTAssertTrue(message.contains("/Applications/Demo Recorder.app"))
    }
    func testOtherErrorsDoNotMisdiagnosePermission() {
        let error = NSError(domain:NSURLErrorDomain,code:-1,userInfo:[NSLocalizedDescriptionKey:"测试连接失败"])
        let message = CapturePermissionGuidance.message(for:error,applicationPath:"/Applications/Demo Recorder.app")
        XCTAssertTrue(message.contains("测试连接失败"))
        XCTAssertFalse(message.contains("权限"))
    }
}
