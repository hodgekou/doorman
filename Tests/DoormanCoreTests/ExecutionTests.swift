import Foundation
import Testing
@testable import DoormanCore

@Suite("执行前复核")
struct ExecutionCheckTests {
    let t0 = ContinuousClock.now
    let round = LockRound(reason: .away)

    @Test("预警后无输入：放行")
    func proceed() {
        let d = ExecutionCheck.evaluate(round: round, currentRoundID: round.id, session: .unlocked,
                                        lastInputAt: t0 - .seconds(1), warningStartedAt: t0)
        #expect(d == .proceed)
    }

    @Test("放行后、执行前有输入：放弃")
    func inputAfterWarningAborts() {
        let d = ExecutionCheck.evaluate(round: round, currentRoundID: round.id, session: .unlocked,
                                        lastInputAt: t0 + .seconds(5), warningStartedAt: t0)
        #expect(d == .abort(.inputAfterWarning))
    }

    @Test("轮次已作废：放弃")
    func invalidatedRound() {
        let d = ExecutionCheck.evaluate(round: round, currentRoundID: UUID(), session: .unlocked,
                                        lastInputAt: t0 - .seconds(1), warningStartedAt: t0)
        #expect(d == .abort(.roundInvalidated))
    }

    @Test("读不到空闲时长：放弃")
    func idleUnreadable() {
        let d = ExecutionCheck.evaluate(round: round, currentRoundID: round.id, session: .unlocked,
                                        lastInputAt: nil, warningStartedAt: t0)
        #expect(d == .abort(.idleUnreadable))
    }

    @Test("会话已锁：跳过")
    func alreadyLocked() {
        let d = ExecutionCheck.evaluate(round: round, currentRoundID: round.id, session: .locked,
                                        lastInputAt: t0 - .seconds(1), warningStartedAt: t0)
        #expect(d == .skipAlreadyLocked)
    }
}

@Suite("会话证据")
struct SessionEvidenceTests {
    @Test("两路一致才算数，缺失或冲突为未知")
    func agreement() {
        #expect(SessionEvidence(screenLockedFlag: true, lastNotification: true).state == .locked)
        #expect(SessionEvidence(screenLockedFlag: false, lastNotification: false).state == .unlocked)
        #expect(SessionEvidence(screenLockedFlag: true, lastNotification: false).state == .unknown)
        #expect(SessionEvidence(screenLockedFlag: nil, lastNotification: true).state == .unknown)
    }
}

@Suite("锁屏尝试追踪")
struct LockAttemptTrackerTests {
    let t0 = ContinuousClock.now
    let round = LockRound(reason: .away)

    @Test("确认时限内观察到已锁")
    func observed() {
        var tracker = LockAttemptTracker(confirmTimeout: .seconds(3))
        tracker.begin(round, at: t0, departureAt: t0 - .seconds(12))
        #expect(tracker.onTick(at: t0 + .seconds(1), session: .unknown) == nil)
        let outcome = tracker.onTick(at: t0 + .seconds(2), session: .locked)
        #expect(outcome == .observedLocked(round, latency: .seconds(14)))
    }

    @Test("超时未确认，迟到的确认只记录不改结果")
    func unconfirmedThenLate() {
        var tracker = LockAttemptTracker(confirmTimeout: .seconds(3))
        tracker.begin(round, at: t0, departureAt: nil)
        #expect(tracker.onTick(at: t0 + .seconds(4), session: .unknown) == .unconfirmed(round))
        #expect(tracker.onTick(at: t0 + .seconds(5), session: .locked) == .lateConfirmation(round, after: .seconds(5)))
        guard case .unconfirmed(_, _, .some) = tracker.status else {
            Issue.record("结果应保持未确认，实际 \(tracker.status)")
            return
        }
        // 只报告一次
        #expect(tracker.onTick(at: t0 + .seconds(6), session: .locked) == nil)
    }

    @Test("睡眠作废待确认请求")
    func cancelPending() {
        var tracker = LockAttemptTracker()
        tracker.begin(round, at: t0, departureAt: nil)
        #expect(tracker.cancelPending(.systemSleep) == round)
        #expect(!tracker.isPending)
    }
}
