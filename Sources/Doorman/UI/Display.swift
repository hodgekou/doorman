import Foundation
import DoormanCore

// 状态与原因的中文显示文案。

extension LockReason {
    var title: String {
        switch self {
        case .away: return L("离开")
        case .lost: return L("失联")
        case .sensorUnavailable: return L("蓝牙不可用")
        case .manual: return L("手动")
        }
    }
}

extension MonitorIssue {
    var title: String {
        switch self {
        case .bluetoothOff: return L("蓝牙已关闭")
        case .bluetoothUnauthorized: return L("没有蓝牙权限")
        case .notFoundAfterWake: return L("唤醒后未找到设备")
        }
    }
}

extension InterruptReason {
    var title: String {
        switch self {
        case .deviceReturned: return L("设备回到在场")
        case .paused: return L("监控暂停")
        case .systemSleep: return L("系统睡眠")
        case .sessionSwitched: return L("切换会话")
        case .sensorUnavailable: return L("本机蓝牙不可用")
        case .sensorRestored: return L("本机蓝牙恢复")
        case .idleUnreadable: return L("读不到键鼠空闲时长")
        case .rebound: return L("重新绑定设备")
        }
    }
}

extension AbortReason {
    var title: String {
        switch self {
        case .roundInvalidated: return L("轮次已作废")
        case .idleUnreadable: return L("读不到键鼠空闲时长")
        case .inputAfterWarning: return L("预警开始后有新输入")
        }
    }
}

extension Presence {
    var title: String {
        switch self {
        case .resampling: return L("重新采样中")
        case .near: return L("在场")
        case .leaving: return L("离开中")
        case .away: return L("已离开")
        case .lost: return L("失联")
        case .unavailable(let issue): return L("监控不可用 · %@", issue.title)
        }
    }
}

extension ProductState {
    var title: String {
        switch self {
        case .autoLockAvailable: return L("自动锁屏可用")
        case .reminderOnly: return L("仅提醒")
        case .notReady(let reason): return L("监控未就绪 · %@", reason.title)
        }
    }

    var symbolName: String {
        switch self {
        case .autoLockAvailable: return "lock.shield"
        case .reminderOnly: return "bell"
        case .notReady: return "lock.slash"
        }
    }
}

extension ProductState.NotReadyReason {
    var title: String {
        switch self {
        case .noDeviceBound: return L("未绑定设备")
        case .autoLockDisabled: return L("自动锁屏已关闭")
        case .paused: return L("已暂停")
        case .bluetoothOff: return L("蓝牙已关闭")
        case .bluetoothUnauthorized: return L("没有蓝牙权限")
        case .resampling: return L("正在寻找设备")
        case .notFoundAfterWake: return L("找不到设备")
        case .signalUnstable: return L("主设备信号不稳定")
        }
    }
}

extension LockGate.Phase {
    var title: String {
        switch self {
        case .closed: return L("未触发")
        case .holding: return L("拦截中 · 等待键鼠空闲")
        case .warning: return L("锁前预警")
        case .released: return L("已放行")
        case .endedByUser: return L("本轮已结束（用户取消）")
        }
    }
}

extension LockLogEntry.Kind {
    var title: String {
        switch self {
        case .blockedByActivity: return L("活动守卫拦截")
        case .warningCancelled: return L("预警被取消")
        case .abortedBeforeExecution: return L("执行前放弃")
        case .observedLocked: return L("观察到已锁")
        case .unconfirmed: return L("锁屏未确认")
        case .lateConfirmation: return L("确认迟到")
        case .skippedAlreadyLocked: return L("跳过（已锁）")
        case .reminded: return L("仅提醒")
        case .revoked: return L("轮次撤销")
        case .monitorNotReady: return L("监控未就绪")
        case .quickUnlockClue: return L("误锁线索")
        case .manualLock: return L("手动锁屏")
        case .lockCallFailed: return L("锁屏调用失败")
        }
    }
}

extension AppModel {
    var deviceLine: String {
        guard let name = settings.boundDeviceName else { return L("未绑定设备") }
        if let estimate { return "\(name) · \(estimate) dBm" }
        return L("%@ · 无信号", name)
    }

    var idleText: String {
        guard let idleSeconds else { return L("读不到") }
        return L("%d 秒", Int(idleSeconds))
    }

    var bluetoothHint: String {
        switch bluetooth {
        case .unknown: return L("正在打开蓝牙…首次使用时请在系统弹窗中允许 Doorman 使用蓝牙。")
        case .poweredOn: return L("正在扫描附近设备…")
        case .poweredOff: return L("蓝牙已关闭，请先打开蓝牙。")
        case .unauthorized: return L("Doorman 没有蓝牙权限，请在「系统设置 › 隐私与安全性 › 蓝牙」中允许。")
        case .unsupported: return L("这台 Mac 不支持低功耗蓝牙。")
        }
    }

    var lockMethodStatus: String {
        switch settings.lockMethod {
        case .privateSAC:
            return lockMethodCanLock ? L("可用。私有接口，不能上架 Mac App Store，系统升级后可能失效。") : L("当前系统找不到这个接口，产品状态降为「仅提醒」。")
        case .shortcut:
            return lockMethodCanLock ? L("可用。依赖 ⌃⌘Q 快捷键未被修改。") : L("需要辅助功能权限，授权前产品状态为「仅提醒」。")
        case .reminderOnly:
            return L("不锁屏，离开时只发本机通知。你已经走开时很可能看不到。")
        }
    }
}

// MARK: - 状态胶囊的文案与颜色

extension ProductState {
    var tone: Tone {
        switch self {
        case .autoLockAvailable: return .good
        case .reminderOnly: return .warn
        case .notReady: return .warn
        }
    }
}

extension Presence {
    var tone: Tone {
        switch self {
        case .near: return .good
        case .leaving: return .warn
        case .away, .lost: return .bad
        case .resampling: return .neutral
        case .unavailable: return .warn
        }
    }
}

extension LockGate.Phase {
    var tone: Tone {
        switch self {
        case .closed: return .neutral
        case .holding: return .warn
        case .warning: return .bad
        case .released: return .info
        case .endedByUser: return .neutral
        }
    }
}

extension LockAttemptStatus {
    var title: String {
        switch self {
        case .idle: return L("无")
        case .pending: return L("等待确认")
        case .observedLocked(_, let latency):
            if let latency { return String(format: L("请求后观察到已锁 · %.1f 秒"), latency.secondsValue) }
            return L("请求后观察到已锁")
        case .unconfirmed(_, _, let late):
            if let late { return String(format: L("锁屏未确认 · 迟到 %.1f 秒"), late.secondsValue) }
            return L("锁屏未确认")
        case .skippedAlreadyLocked: return L("跳过（已锁）")
        case .aborted(_, let reason): return L("执行前放弃 · %@", reason.title)
        case .reminded: return L("已提醒")
        case .cancelled(_, let reason): return L("已取消 · %@", reason.title)
        }
    }

    var tone: Tone {
        switch self {
        case .idle, .skippedAlreadyLocked, .cancelled: return .neutral
        case .pending, .reminded: return .warn
        case .observedLocked, .aborted: return .good
        case .unconfirmed: return .bad
        }
    }
}

extension SessionState {
    var title: String {
        switch self {
        case .unlocked: return L("未锁")
        case .locked: return L("已锁")
        case .unknown: return L("未知")
        }
    }
}

extension PermissionStatus {
    var title: String {
        switch self {
        case .granted: return L("已允许")
        case .notDetermined: return L("未授权")
        case .denied: return L("已拒绝")
        case .notNeeded: return L("不需要")
        }
    }

    var tone: Tone {
        switch self {
        case .granted: return .good
        case .notDetermined: return .warn
        case .denied: return .bad
        case .notNeeded: return .neutral
        }
    }
}

// MARK: - 面向用户的文案

extension Presence {
    var friendlyTitle: String {
        switch self {
        case .resampling: return L("寻找中")
        case .near: return L("在身边")
        case .leaving: return L("信号变弱")
        case .away: return L("已离开")
        case .lost: return L("没有信号")
        case .unavailable: return L("不可用")
        }
    }
}

extension LockLogEntry.Kind {
    var friendlyTitle: String {
        switch self {
        case .blockedByActivity: return L("你在使用电脑，没有锁屏")
        case .warningCancelled: return L("你取消了锁屏倒计时")
        case .abortedBeforeExecution: return L("锁屏前检测到操作，已取消")
        case .observedLocked: return L("已锁屏")
        case .unconfirmed: return L("锁屏没有成功确认")
        case .lateConfirmation: return L("锁屏确认较慢")
        case .skippedAlreadyLocked: return L("屏幕已经锁着")
        case .reminded: return L("已提醒你锁屏")
        case .revoked: return L("取消了一次锁屏")
        case .monitorNotReady: return L("监控暂时中断")
        case .quickUnlockClue: return L("锁屏后很快解锁（可能误锁）")
        case .manualLock: return L("手动锁屏")
        case .lockCallFailed: return L("锁屏调用失败")
        }
    }

    var symbol: String {
        switch self {
        case .blockedByActivity: return "keyboard"
        case .warningCancelled, .abortedBeforeExecution: return "hand.raised.fill"
        case .observedLocked: return "lock.fill"
        case .unconfirmed: return "exclamationmark.triangle.fill"
        case .lateConfirmation: return "clock"
        case .skippedAlreadyLocked: return "lock"
        case .reminded: return "bell.fill"
        case .revoked: return "arrow.uturn.backward"
        case .monitorNotReady: return "antenna.radiowaves.left.and.right.slash"
        case .quickUnlockClue: return "questionmark.circle"
        case .manualLock: return "lock"
        case .lockCallFailed: return "xmark.octagon.fill"
        }
    }

    var tone: Tone {
        switch self {
        case .observedLocked: return .good
        case .blockedByActivity: return .info
        case .unconfirmed, .reminded, .monitorNotReady, .quickUnlockClue: return .warn
        case .lockCallFailed: return .bad
        default: return .neutral
        }
    }
}
