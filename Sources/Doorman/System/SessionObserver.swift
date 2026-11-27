import AppKit
import CoreGraphics
import DoormanCore

/// ③ 会话观察：只报告系统观察到的事实。
/// 两路信号均未文档化（M0 用独立观测做对照验证），一致才算数。
@MainActor
final class SessionObserver {
    var onStateChange: (@MainActor (SessionState) -> Void)?
    var onWillSleep: (@MainActor () -> Void)?
    var onDidWake: (@MainActor () -> Void)?
    var onSessionResignActive: (@MainActor () -> Void)?
    var onSessionBecomeActive: (@MainActor () -> Void)?

    private(set) var evidence: SessionEvidence
    private var tokens: [NSObjectProtocol] = []

    var state: SessionState { evidence.state }

    init() {
        let flag = Self.readScreenLockedFlag()
        // App 只在已登录会话中启动，以启动时的标志作为通知信号的初值
        evidence = SessionEvidence(screenLockedFlag: flag, lastNotification: flag)
        observe()
    }

    /// 每秒轮询一次标志；收到通知时也会立即轮询。
    func poll() {
        let before = evidence.state
        evidence.screenLockedFlag = Self.readScreenLockedFlag()
        if evidence.state != before { onStateChange?(evidence.state) }
    }

    private func observe() {
        let dnc = DistributedNotificationCenter.default()
        tokens.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notified(locked: true) }
        })
        tokens.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notified(locked: false) }
        })

        let wnc = NSWorkspace.shared.notificationCenter
        tokens.append(wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWillSleep?() }
        })
        tokens.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDidWake?() }
        })
        // 会话切出（如快速切换用户）不能单独证明屏幕已锁，只用于撤销轮次
        tokens.append(wnc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSessionResignActive?() }
        })
        tokens.append(wnc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSessionBecomeActive?() }
        })
    }

    private func notified(locked: Bool) {
        let before = evidence.state
        evidence.lastNotification = locked
        evidence.screenLockedFlag = Self.readScreenLockedFlag()
        if evidence.state != before { onStateChange?(evidence.state) }
    }

    /// 解锁时字典里没有这个键，视为 false；拿不到字典时返回 nil。
    private static func readScreenLockedFlag() -> Bool? {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        if let value = dict["CGSSessionScreenIsLocked"] as? Bool { return value }
        if let value = dict["CGSSessionScreenIsLocked"] as? Int { return value == 1 }
        return false
    }
}
