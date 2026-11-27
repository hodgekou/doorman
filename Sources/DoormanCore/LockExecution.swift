import Foundation

/// ③ 会话状态。只报告系统观察到的事实，不归因。
public enum SessionState: String, Sendable, Codable, Equatable {
    case unlocked
    case locked
    case unknown
}

/// 两路会话信号（均未文档化，M0 待验证）。一致才算数，缺失或冲突即「未知」。
public struct SessionEvidence: Sendable, Equatable {
    /// CGSessionCopyCurrentDictionary 中的 CGSSessionScreenIsLocked。
    public var screenLockedFlag: Bool?
    /// 最近一次 com.apple.screenIsLocked / screenIsUnlocked 分布式通知。
    public var lastNotification: Bool?

    public init(screenLockedFlag: Bool? = nil, lastNotification: Bool? = nil) {
        self.screenLockedFlag = screenLockedFlag
        self.lastNotification = lastNotification
    }

    public var state: SessionState {
        switch (screenLockedFlag, lastNotification) {
        case (true?, true?): return .locked
        case (false?, false?): return .unlocked
        default: return .unknown
        }
    }
}

public enum AbortReason: String, Sendable, Codable, Equatable {
    case roundInvalidated
    case idleUnreadable
    case inputAfterWarning
}

public enum ExecutionDecision: Sendable, Equatable {
    case proceed
    case skipAlreadyLocked
    case abort(AbortReason)
}

/// 执行前复核：所有自动锁屏路径的硬条件。
/// 调用方必须在调用系统锁屏的同一线程、紧挨着调用之前执行，中间不 await。
public enum ExecutionCheck {
    public static func evaluate(
        round: LockRound,
        currentRoundID: UUID?,
        session: SessionState,
        lastInputAt: Instant?,
        warningStartedAt: Instant
    ) -> ExecutionDecision {
        guard currentRoundID == round.id else { return .abort(.roundInvalidated) }
        guard session != .locked else { return .skipAlreadyLocked }
        guard let lastInputAt else { return .abort(.idleUnreadable) }
        guard lastInputAt < warningStartedAt else { return .abort(.inputAfterWarning) }
        return .proceed
    }
}

/// ② 锁屏尝试的结果追踪。只记录「请求后观察到已锁」，不判断是谁锁的。
public enum LockAttemptStatus: Sendable, Equatable {
    case idle
    case pending(LockRound, since: Instant, departureAt: Instant?)
    case observedLocked(LockRound, latency: Duration?)
    case unconfirmed(LockRound, since: Instant, lateBy: Duration?)
    case skippedAlreadyLocked(LockRound)
    case aborted(LockRound, AbortReason)
    case reminded(LockRound)
    case cancelled(LockRound, InterruptReason)
}

public enum AttemptOutcome: Sendable, Equatable {
    case observedLocked(LockRound, latency: Duration?)
    case unconfirmed(LockRound)
    case lateConfirmation(LockRound, after: Duration)
}

public struct LockAttemptTracker: Sendable {
    public private(set) var status: LockAttemptStatus = .idle
    public var confirmTimeout: Duration

    public init(confirmTimeout: Duration = .seconds(3)) {
        self.confirmTimeout = confirmTimeout
    }

    public var isPending: Bool {
        if case .pending = status { return true }
        return false
    }

    public mutating func begin(_ round: LockRound, at now: Instant, departureAt: Instant?) {
        status = .pending(round, since: now, departureAt: departureAt)
    }

    public mutating func record(_ newStatus: LockAttemptStatus) {
        status = newStatus
    }

    public mutating func onTick(at now: Instant, session: SessionState) -> AttemptOutcome? {
        switch status {
        case .pending(let round, let since, let departureAt):
            if session == .locked {
                let latency = departureAt.map { now - $0 }
                status = .observedLocked(round, latency: latency)
                return .observedLocked(round, latency: latency)
            }
            if now - since > confirmTimeout {
                status = .unconfirmed(round, since: since, lateBy: nil)
                return .unconfirmed(round)
            }
        case .unconfirmed(let round, let since, nil):
            // 迟到的确认：只记录，不改结果
            if session == .locked {
                let late = now - since
                status = .unconfirmed(round, since: since, lateBy: late)
                return .lateConfirmation(round, after: late)
            }
        default:
            break
        }
        return nil
    }

    /// 睡眠、切换会话时作废等待中的请求。
    @discardableResult
    public mutating func cancelPending(_ reason: InterruptReason) -> LockRound? {
        guard case .pending(let round, _, _) = status else { return nil }
        status = .cancelled(round, reason)
        return round
    }

    /// 用户解锁后回到空闲。
    public mutating func onUnlocked() {
        switch status {
        case .pending: return
        default: status = .idle
        }
    }
}
