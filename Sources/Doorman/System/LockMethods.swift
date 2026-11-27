import ApplicationServices
import CoreGraphics
import Darwin

/// 锁屏方式。M0 逐个验证「触发 / 确认 / 分发」，最终只保留通过的那种。
@MainActor
protocol LockMethod {
    var kind: LockMethodKind { get }
    /// 当前能否触发锁屏。为 false 时产品状态为「仅提醒」。
    var canLock: Bool { get }
    /// 触发锁屏。返回值只表示调用是否发出，结果以会话观察为准。
    func lock() -> Bool
}

@MainActor
enum LockMethods {
    static func make(_ kind: LockMethodKind) -> LockMethod {
        switch kind {
        case .privateSAC: return PrivateSACLock()
        case .shortcut: return ShortcutLock()
        case .reminderOnly: return ReminderOnlyLock()
        }
    }
}

/// A1：login.framework 的私有函数 SACLockScreenImmediate。
/// 不能上架 Mac App Store，系统升级可能失效。运行时动态查找，找不到则 canLock = false。
@MainActor
final class PrivateSACLock: LockMethod {
    private typealias LockFn = @convention(c) () -> Int32
    private let fn: LockFn?

    let kind: LockMethodKind = .privateSAC

    init() {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let sym = dlsym(handle, "SACLockScreenImmediate") {
            fn = unsafeBitCast(sym, to: LockFn.self)
        } else {
            fn = nil
        }
    }

    var canLock: Bool { fn != nil }

    func lock() -> Bool {
        guard let fn else { return false }
        return fn() == 0
    }
}

/// B1：用公开的 CGEvent 合成系统锁屏快捷键 ⌃⌘Q。
/// 需要辅助功能权限，且依赖用户没有改这个快捷键；两者组合的行为没有文档承诺。
@MainActor
final class ShortcutLock: LockMethod {
    let kind: LockMethodKind = .shortcut
    private let qKeyCode: CGKeyCode = 12

    var canLock: Bool { AXIsProcessTrusted() }

    func lock() -> Bool {
        guard canLock, let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: qKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: qKeyCode, keyDown: false) else {
            return false
        }
        let flags: CGEventFlags = [.maskControl, .maskCommand]
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// 弹出系统的辅助功能授权提示。
    static func requestPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// D：不锁屏，只提醒。M0 锁屏链路不通过时的降级方案。
@MainActor
final class ReminderOnlyLock: LockMethod {
    let kind: LockMethodKind = .reminderOnly
    var canLock: Bool { false }
    func lock() -> Bool { false }
}
