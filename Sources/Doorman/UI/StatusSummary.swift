import AppKit
import SwiftUI
import DoormanCore

/// 面向用户的状态摘要：一句话回答「我现在被保护着吗」，出问题时给出修复入口。
/// 菜单栏图标、弹出窗口、概览页都用它，保证各处说法一致。
struct StatusSummary {
    enum Fix {
        case openOnboarding
        case openPermissions
        case chooseDevice
        case openBluetoothSettings
        case resume
        case enableAutoLock
    }

    struct Issue {
        let message: String
        let actionTitle: String
        let fix: Fix
    }

    var headline: String
    var detail: String
    var tone: Tone
    /// 大图标（概览页）
    var heroSymbol: String
    /// 菜单栏图标
    var menuSymbol: String
    var issue: Issue?
    /// 设备卡片里紧跟设备名的一句状态（不重复设备名）；为 nil 时用 detail
    var deviceDetail: String? = nil
}

extension AppModel {
    /// 显示名称：用户起的名字优先，其次是设备广播的名称
    var deviceName: String {
        let alias = settings.deviceAlias.trimmingCharacters(in: .whitespaces)
        if !alias.isEmpty { return alias }
        return settings.boundDeviceName ?? L("随身设备")
    }

    /// 设备图标：用户选的类型优先，其次按设备名猜测
    var deviceSymbol: String {
        settings.deviceKind.symbol ?? DeviceGlyph.symbol(for: settings.boundDeviceName ?? "")
    }

    var summary: StatusSummary {
        let device = deviceName

        if !settings.onboardingCompleted && settings.boundDeviceID == nil {
            return StatusSummary(
                headline: L("尚未设置"), detail: L("完成几步设置后开始保护这台 Mac"),
                tone: .warn, heroSymbol: "sparkles", menuSymbol: "lock.slash",
                issue: .init(message: L("还没有完成设置"), actionTitle: L("开始设置"), fix: .openOnboarding)
            )
        }
        if bluetoothPermission != .granted {
            return StatusSummary(
                headline: L("需要蓝牙权限"), detail: L("没有蓝牙权限就无法感知你的设备"),
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: L("Doorman 需要蓝牙权限"), actionTitle: L("去授权"), fix: .openPermissions)
            )
        }
        if settings.boundDeviceID == nil {
            return StatusSummary(
                headline: L("未选择设备"), detail: L("选择一台随身设备后开始保护"),
                tone: .warn, heroSymbol: "applewatch.slash", menuSymbol: "lock.slash",
                issue: .init(message: L("还没有选择随身设备"), actionTitle: L("选择设备"), fix: .chooseDevice)
            )
        }
        if paused {
            let detail = pausedUntil.map { L("将在 %@ 自动恢复", L10n.time($0)) } ?? L("直到你手动恢复")
            return StatusSummary(
                headline: L("已暂停"), detail: detail,
                tone: .neutral, heroSymbol: "pause.circle.fill", menuSymbol: "pause.circle",
                issue: nil
            )
        }
        if !settings.autoLockEnabled {
            return StatusSummary(
                headline: L("自动锁屏已关闭"), detail: L("只显示信号，离开时不会锁屏"),
                tone: .neutral, heroSymbol: "lock.open.fill", menuSymbol: "lock.open",
                issue: .init(message: L("自动锁屏已关闭"), actionTitle: L("开启"), fix: .enableAutoLock)
            )
        }

        switch productState {
        case .notReady(.bluetoothOff):
            return StatusSummary(
                headline: L("蓝牙已关闭"), detail: L("打开蓝牙后自动恢复保护"),
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: L("蓝牙已关闭，离开时不会自动锁屏"), actionTitle: L("打开蓝牙设置"), fix: .openBluetoothSettings)
            )
        case .notReady(.bluetoothUnauthorized):
            return StatusSummary(
                headline: L("需要蓝牙权限"), detail: L("没有蓝牙权限就无法感知你的设备"),
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: L("Doorman 需要蓝牙权限"), actionTitle: L("去授权"), fix: .openPermissions)
            )
        case .notReady(.resampling):
            return StatusSummary(
                headline: L("正在寻找设备"), detail: L("正在连接 %@…", device),
                tone: .neutral, heroSymbol: "antenna.radiowaves.left.and.right", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: L("正在连接…")
            )
        case .notReady(.notFoundAfterWake):
            return StatusSummary(
                headline: L("找不到设备"), detail: L("%@ 回到附近后自动恢复保护", device),
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: L("一直找不到 %@？可以重新选择设备", device), actionTitle: L("重新选择"), fix: .chooseDevice),
                deviceDetail: L("找不到设备")
            )
        case .notReady(.signalUnstable):
            return StatusSummary(
                headline: L("信号不稳定"), detail: L("已取消这次锁屏。设备在你身边稳定 10 秒后恢复保护"),
                tone: .warn, heroSymbol: "waveform.path.ecg", menuSymbol: "exclamationmark.shield",
                issue: nil
            )
        case .notReady:
            return StatusSummary(
                headline: L("未就绪"), detail: productState.title,
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: nil
            )
        case .reminderOnly:
            return StatusSummary(
                headline: L("仅提醒"), detail: L("这台 Mac 当前无法自动锁屏，离开时只发通知"),
                tone: .warn, heroSymbol: "bell.fill", menuSymbol: "bell",
                issue: nil
            )
        case .autoLockAvailable:
            break
        }

        if session == .locked {
            return StatusSummary(
                headline: L("已锁定"), detail: L("回来后用 Apple Watch、触控 ID 或密码解锁"),
                tone: .info, heroSymbol: "lock.fill", menuSymbol: "lock.shield.fill",
                issue: nil
            )
        }
        switch gatePhase {
        case .warning:
            return StatusSummary(
                headline: L("即将锁屏"), detail: L("动一下鼠标或键盘即可取消"),
                tone: .bad, heroSymbol: "timer", menuSymbol: "lock.shield.fill",
                issue: nil, deviceDetail: L("即将锁屏 · 动一下鼠标即可取消")
            )
        case .holding:
            return StatusSummary(
                headline: L("检测到你在使用"), detail: L("%@ 信号变弱，但你刚操作过电脑，暂不锁屏", device),
                tone: .info, heroSymbol: "keyboard", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: L("信号变弱 · 你在使用电脑，暂不锁屏")
            )
        default:
            break
        }
        switch presence {
        case .leaving:
            return StatusSummary(
                headline: L("保护中"), detail: L("%@ 信号在变弱，继续观察", device),
                tone: .warn, heroSymbol: "checkmark.shield.fill", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: L("信号在变弱")
            )
        case .away, .lost:
            return StatusSummary(
                headline: L("保护中"), detail: L("%@ 已离开", device),
                tone: .good, heroSymbol: "checkmark.shield.fill", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: L("已离开")
            )
        default:
            return StatusSummary(
                headline: L("保护中"), detail: L("%@ 在你身边", device),
                tone: .good, heroSymbol: "checkmark.shield.fill", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: L("在你身边")
            )
        }
    }

    var lastLockDescription: String? {
        guard let date = lastLockDate else { return nil }
        let time = L10n.time(date)
        if let latency = lastLockLatency {
            return L("上次自动锁屏 %@ · 离开后 %d 秒", time, Int(latency.rounded()))
        }
        return L("上次锁屏 %@", time)
    }

    func perform(_ fix: StatusSummary.Fix) {
        switch fix {
        case .openOnboarding:
            OnboardingWindowController.shared.show(model: self)
        case .openPermissions:
            if settings.onboardingCompleted {
                openSettings(.permissions)
            } else {
                OnboardingWindowController.shared.show(model: self)
            }
        case .chooseDevice:
            openSettings(.devices)
        case .openBluetoothSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                NSWorkspace.shared.open(url)
            }
        case .resume:
            resume()
        case .enableAutoLock:
            settings.autoLockEnabled = true
        }
    }

    func openSettings(_ section: SettingsSection) {
        settingsSection = section
        SettingsWindowController.shared.show(model: self)
    }
}
