import Foundation
import ScreenCaptureKit

public enum CapturePermissionGuidance {
    public static func message(for error: Error, applicationPath: String) -> String {
        let error = error as NSError
        guard error.domain == SCStreamErrorDomain, error.code == SCStreamError.Code.userDeclined.rawValue else {
            return "无法读取屏幕和窗口：\(error.localizedDescription)"
        }
        return "系统尚未允许当前这份应用读取屏幕。\n\n如果权限已经开启，请先完全退出 JDAD Recorder，再从下方路径重新打开。仍然失败时，在系统设置 → 隐私与安全性 → 录屏与系统录音中移除旧的 JDAD Recorder 条目，重新添加下方这份应用并开启权限，然后退出重开。\n\n当前应用：\(applicationPath)\n\n旧测试版更新后签名变化，可能导致开关显示开启但系统仍拒绝访问。"
    }
}
