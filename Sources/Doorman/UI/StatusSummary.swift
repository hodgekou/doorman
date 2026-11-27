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
        return settings.boundDeviceName ?? "随身设备"
    }

    /// 设备图标：用户选的类型优先，其次按设备名猜测
    var deviceSymbol: String {
        settings.deviceKind.symbol ?? DeviceGlyph.symbol(for: settings.boundDeviceName ?? "")
    }

    var summary: StatusSummary {
        let device = deviceName

        if !settings.onboardingCompleted && settings.boundDeviceID == nil {
            return StatusSummary(
                headline: "尚未设置", detail: "完成几步设置后开始保护这台 Mac",
                tone: .warn, heroSymbol: "sparkles", menuSymbol: "lock.slash",
                issue: .init(message: "还没有完成设置", actionTitle: "开始设置", fix: .openOnboarding)
            )
        }
        if bluetoothPermission != .granted {
            return StatusSummary(
                headline: "需要蓝牙权限", detail: "没有蓝牙权限就无法感知你的设备",
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: "Doorman 需要蓝牙权限", actionTitle: "去授权", fix: .openPermissions)
            )
        }
        if settings.boundDeviceID == nil {
            return StatusSummary(
                headline: "未选择设备", detail: "选择一台随身设备后开始保护",
                tone: .warn, heroSymbol: "applewatch.slash", menuSymbol: "lock.slash",
                issue: .init(message: "还没有选择随身设备", actionTitle: "选择设备", fix: .chooseDevice)
            )
        }
        if paused {
            let detail = pausedUntil.map { "将在 \($0.formatted(date: .omitted, time: .shortened)) 自动恢复" } ?? "直到你手动恢复"
            return StatusSummary(
                headline: "已暂停", detail: detail,
                tone: .neutral, heroSymbol: "pause.circle.fill", menuSymbol: "pause.circle",
                issue: nil
            )
        }
        if !settings.autoLockEnabled {
            return StatusSummary(
                headline: "自动锁屏已关闭", detail: "只显示信号，离开时不会锁屏",
                tone: .neutral, heroSymbol: "lock.open.fill", menuSymbol: "lock.open",
                issue: .init(message: "自动锁屏已关闭", actionTitle: "开启", fix: .enableAutoLock)
            )
        }

        switch productState {
        case .notReady(.bluetoothOff):
            return StatusSummary(
                headline: "蓝牙已关闭", detail: "打开蓝牙后自动恢复保护",
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: "蓝牙已关闭，离开时不会自动锁屏", actionTitle: "打开蓝牙设置", fix: .openBluetoothSettings)
            )
        case .notReady(.bluetoothUnauthorized):
            return StatusSummary(
                headline: "需要蓝牙权限", detail: "没有蓝牙权限就无法感知你的设备",
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: "Doorman 需要蓝牙权限", actionTitle: "去授权", fix: .openPermissions)
            )
        case .notReady(.resampling):
            return StatusSummary(
                headline: "正在寻找设备", detail: "正在连接 \(device)…",
                tone: .neutral, heroSymbol: "antenna.radiowaves.left.and.right", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: "正在连接…"
            )
        case .notReady(.notFoundAfterWake):
            return StatusSummary(
                headline: "找不到设备", detail: "\(device) 回到附近后自动恢复保护",
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: .init(message: "一直找不到 \(device)？可以重新选择设备", actionTitle: "重新选择", fix: .chooseDevice),
                deviceDetail: "找不到设备"
            )
        case .notReady(.signalUnstable):
            return StatusSummary(
                headline: "信号不稳定", detail: "已取消这次锁屏。设备在你身边稳定 10 秒后恢复保护",
                tone: .warn, heroSymbol: "waveform.path.ecg", menuSymbol: "exclamationmark.shield",
                issue: nil
            )
        case .notReady:
            return StatusSummary(
                headline: "未就绪", detail: productState.title,
                tone: .warn, heroSymbol: "exclamationmark.shield.fill", menuSymbol: "exclamationmark.shield",
                issue: nil
            )
        case .reminderOnly:
            return StatusSummary(
                headline: "仅提醒", detail: "这台 Mac 当前无法自动锁屏，离开时只发通知",
                tone: .warn, heroSymbol: "bell.fill", menuSymbol: "bell",
                issue: nil
            )
        case .autoLockAvailable:
            break
        }

        if session == .locked {
            return StatusSummary(
                headline: "已锁定", detail: "回来后用 Apple Watch、触控 ID 或密码解锁",
                tone: .info, heroSymbol: "lock.fill", menuSymbol: "lock.shield.fill",
                issue: nil
            )
        }
        switch gatePhase {
        case .warning:
            return StatusSummary(
                headline: "即将锁屏", detail: "动一下鼠标或键盘即可取消",
                tone: .bad, heroSymbol: "timer", menuSymbol: "lock.shield.fill",
                issue: nil, deviceDetail: "即将锁屏 · 动一下鼠标即可取消"
            )
        case .holding:
            return StatusSummary(
                headline: "检测到你在使用", detail: "\(device) 信号变弱，但你刚操作过电脑，暂不锁屏",
                tone: .info, heroSymbol: "keyboard", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: "信号变弱 · 你在使用电脑，暂不锁屏"
            )
        default:
            break
        }
        switch presence {
        case .leaving:
            return StatusSummary(
                headline: "保护中", detail: "\(device) 信号在变弱，继续观察",
                tone: .warn, heroSymbol: "checkmark.shield.fill", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: "信号在变弱"
            )
        case .away, .lost:
            return StatusSummary(
                headline: "保护中", detail: "\(device) 已离开",
                tone: .good, heroSymbol: "checkmark.shield.fill", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: "已离开"
            )
        default:
            return StatusSummary(
                headline: "保护中", detail: "\(device) 在你身边",
                tone: .good, heroSymbol: "checkmark.shield.fill", menuSymbol: "lock.shield",
                issue: nil, deviceDetail: "在你身边"
            )
        }
    }

    var lastLockDescription: String? {
        guard let date = lastLockDate else { return nil }
        let time = date.formatted(date: .omitted, time: .shortened)
        if let latency = lastLockLatency {
            return "上次自动锁屏 \(time) · 离开后 \(Int(latency.rounded())) 秒"
        }
        return "上次锁屏 \(time)"
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
