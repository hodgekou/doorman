import Foundation
import UserNotifications

/// 本机通知。只有打包成 .app 运行时才可用（UNUserNotificationCenter 需要 bundle）。
@MainActor
final class Notifier {
    private let enabled: Bool

    init() {
        enabled = Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorization(_ completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in completion?() }
        }
    }

    func fetchPermission(_ completion: @escaping @MainActor @Sendable (PermissionStatus) -> Void) {
        guard enabled else {
            completion(.notDetermined)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PermissionStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = .granted
            case .denied: status = .denied
            default: status = .notDetermined
            }
            Task { @MainActor in completion(status) }
        }
    }

    /// 同一 id 的通知会被替换，避免堆积。
    func post(id: String, title: String, body: String) {
        guard enabled else {
            print("[Doorman] \(title)：\(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
