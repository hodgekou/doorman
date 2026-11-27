import CoreGraphics
import DoormanCore

/// 读取键鼠空闲时长。只读时间戳，不采集按键内容，不监听事件。
enum IdleClock {
    /// kCGAnyInputEventType
    private static let anyInput = CGEventType(rawValue: ~0)!

    /// 距最后一次硬件输入的秒数；读数异常时返回 nil（调用方据此放弃锁屏）。
    /// 用 .hidSystemState 只统计硬件输入，避免软件模拟的输入顶住守卫（M0 待验证覆盖范围）。
    static func secondsSinceLastInput() -> Double? {
        let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    /// 最后一次输入的时刻（单调时钟）。
    static func lastInputAt(now: Instant) -> Instant? {
        secondsSinceLastInput().map { now - .seconds($0) }
    }
}
