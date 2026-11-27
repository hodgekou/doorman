import ServiceManagement

/// 登录时启动（SMAppService.mainApp，macOS 13+）。
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已开启"
        case .notRegistered: return "未开启"
        case .requiresApproval: return "需要在「系统设置 › 通用 › 登录项」中允许"
        case .notFound: return "未找到 App（请从 .app 运行）"
        @unknown default: return "未知"
        }
    }

    /// 返回错误描述；成功时返回 nil。
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
