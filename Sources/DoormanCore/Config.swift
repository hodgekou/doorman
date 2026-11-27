import Foundation

/// 单调时钟时刻。睡眠期间继续计时，所以唤醒后要靠 epoch 作废睡前的计时。
public typealias Instant = ContinuousClock.Instant

/// 所有可调参数。默认值是技术方案 v0.5 中的初定值，均待真机标定。
public struct DoormanConfig: Sendable, Equatable {
    /// 原始 RSSI ≥ 此值即判定「在场」（dBm）。
    public var presentRSSI: Int
    /// 滤波后 RSSI < 此值开始离开倒计时（dBm）。
    public var leaveRSSI: Int
    /// 离开倒计时。
    public var leaveDelay: Duration
    /// 这么久没有有效样本判定「失联」。
    public var signalTimeout: Duration
    /// 样本最大年龄，过期样本不参与中位数。
    public var sampleMaxAge: Duration
    /// 唤醒 / 恢复后多久找不到设备就判定「监控不可用」。
    public var resampleTimeout: Duration
    /// 活动守卫：键鼠空闲多久才允许进入锁前预警。
    public var idleThreshold: Duration
    /// 锁前预警时长。
    public var warningLength: Duration
    /// 用户取消预警后，设备需连续在场这么久才启用下一轮。
    public var stableNearDuration: Duration
    /// 调用系统锁屏后，等待会话确认的时限。
    public var confirmTimeout: Duration
    /// 中值滤波窗口大小。
    public var filterSize: Int

    public init(
        presentRSSI: Int = -60,
        leaveRSSI: Int = -80,
        leaveDelay: Duration = .seconds(5),
        signalTimeout: Duration = .seconds(60),
        sampleMaxAge: Duration = .seconds(6),
        resampleTimeout: Duration = .seconds(15),
        idleThreshold: Duration = .seconds(10),
        warningLength: Duration = .seconds(5),
        stableNearDuration: Duration = .seconds(10),
        confirmTimeout: Duration = .seconds(3),
        filterSize: Int = 5
    ) {
        self.presentRSSI = presentRSSI
        self.leaveRSSI = leaveRSSI
        self.leaveDelay = leaveDelay
        self.signalTimeout = signalTimeout
        self.sampleMaxAge = sampleMaxAge
        self.resampleTimeout = resampleTimeout
        self.idleThreshold = idleThreshold
        self.warningLength = warningLength
        self.stableNearDuration = stableNearDuration
        self.confirmTimeout = confirmTimeout
        self.filterSize = max(1, filterSize)
    }
}

public extension Duration {
    /// 以秒为单位的浮点值，用于显示和日志。
    var secondsValue: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
