import Foundation

/// 一轮自动锁屏尝试。任何撤销都会作废它的 id。
public struct LockRound: Sendable, Equatable {
    public let id: UUID
    public let reason: LockReason

    public init(id: UUID = UUID(), reason: LockReason) {
        self.id = id
        self.reason = reason
    }
}

public enum GateEffect: Sendable, Equatable {
    case showWarning(roundID: UUID, until: Instant)
    case hideWarning
    /// 放行：交给协调器做执行前复核。放行 ≠ 锁屏。
    case execute(LockRound, warningStartedAt: Instant)
    case blockedByActivity(LockRound, idle: Duration)
    case cancelledByUser(LockRound)
    case revoked(LockRound, InterruptReason)
}

/// 活动守卫闸门（纯逻辑），位于在场状态机和锁屏协调器之间。
/// 设备离开只是申请；键鼠空闲 ≥ 门槛、预警期间无输入才放行。
public struct LockGate: Sendable {
    public enum Phase: Sendable, Equatable {
        case closed
        case holding(LockRound, reportedBlock: Bool)
        case warning(LockRound, startedAt: Instant)
        case released(LockRound)
        /// 用户明确取消了本轮；设备连续在场后才回到 closed。
        case endedByUser
    }

    public private(set) var phase: Phase = .closed
    public var config: DoormanConfig

    public init(config: DoormanConfig = .init()) {
        self.config = config
    }

    public var currentRoundID: UUID? {
        switch phase {
        case .holding(let round, _), .warning(let round, _), .released(let round):
            return round.id
        case .closed, .endedByUser:
            return nil
        }
    }

    public var isEndedByUser: Bool {
        if case .endedByUser = phase { return true }
        return false
    }

    /// 来自在场状态机的锁屏申请。已有轮次或本轮被用户取消时忽略。
    public mutating func onLockWanted(_ reason: LockReason, roundID: UUID = UUID()) {
        guard case .closed = phase else { return }
        phase = .holding(LockRound(id: roundID, reason: reason), reportedBlock: false)
    }

    /// - Parameter lastInputAt: 最后一次键鼠输入的时刻；读不到时传 nil，本轮直接撤销（宁可漏锁）。
    public mutating func onTick(at now: Instant, lastInputAt: Instant?) -> [GateEffect] {
        switch phase {
        case .holding(let round, let reported):
            guard let lastInputAt else { return revoke(.idleUnreadable) }
            let idle = now - lastInputAt
            if idle >= config.idleThreshold {
                phase = .warning(round, startedAt: now)
                return [.showWarning(roundID: round.id, until: now + config.warningLength)]
            }
            if !reported {
                phase = .holding(round, reportedBlock: true)
                return [.blockedByActivity(round, idle: idle)]
            }
            return []

        case .warning(let round, let start):
            guard let lastInputAt else { return revoke(.idleUnreadable) }
            if lastInputAt >= start {
                // 预警开始后有输入 = 用户明确取消，结束本轮
                phase = .endedByUser
                return [.hideWarning, .cancelledByUser(round)]
            }
            if now - start >= config.warningLength {
                phase = .released(round)
                return [.hideWarning, .execute(round, warningStartedAt: start)]
            }
            return []

        case .closed, .released, .endedByUser:
            return []
        }
    }

    /// 设备回到在场、暂停、睡眠、切换会话、蓝牙变化：撤下预警并作废本轮。
    public mutating func revoke(_ reason: InterruptReason) -> [GateEffect] {
        switch phase {
        case .holding(let round, _), .released(let round):
            phase = .closed
            return [.revoked(round, reason)]
        case .warning(let round, _):
            phase = .closed
            return [.hideWarning, .revoked(round, reason)]
        case .closed, .endedByUser:
            return []
        }
    }

    /// 执行前复核发现预警后有输入：视同用户取消。
    public mutating func endByUser() {
        phase = .endedByUser
    }

    /// 协调器已处理放行的轮次（调用了锁屏、跳过或放弃）。
    public mutating func finishExecution() {
        if case .released = phase { phase = .closed }
    }

    /// 设备连续在场 ≥ stableNearDuration：重新启用自动锁屏。
    public mutating func onStableNear() {
        if case .endedByUser = phase { phase = .closed }
    }

    /// 重新绑定设备等场景：完全复位。
    public mutating func reset() {
        phase = .closed
    }
}
